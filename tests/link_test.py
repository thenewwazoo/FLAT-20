#!/usr/bin/env python3
"""The panel link (firmware/src/ms20_link.h): run the host build on scripts, parse every SysEx it sends,
decode STATE / LIVE, and check content, timing, rate limits and echo safety."""
import os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, "build/host/flat20")
TMP = tempfile.mkdtemp()
fails = checks = 0

def check(name, cond, detail=""):
    global fails, checks
    checks += 1
    if not cond:
        fails += 1
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else "  [" + str(detail) + "]"))

def enums():
    txt = open(os.path.join(ROOT, "firmware/src/ms20.h")).read()
    out = {}
    for m in re.finditer(r"enum\s*\{(.*?)\};", txt, re.S):
        body = re.sub(r"/\*.*?\*/", "", m.group(1), flags=re.S)
        names = [n.strip() for n in body.split(",") if n.strip()]
        if names and (names[0].startswith("P_") or names[0].startswith("SRC_") or names[0].startswith("DST_")):
            for i, n in enumerate(names):
                out[n] = i
    ncable = int(re.search(r"#define MS_NCABLE (\d+)", txt).group(1))
    return out, ncable

E, NCABLE = enums()
NPARAM, NSRC, NDST = E["MS_NPARAM"], E["MS_NSRC"], E["MS_NDST"]
NJACK = NSRC + NDST - 1
LINK_VER = 2
jout = lambda src: E[src]                      # MS_JACK_OUT
jin = lambda dst: NSRC - 1 + E[dst]            # MS_JACK_IN
SRC_NAMES = {v: k for k, v in E.items() if k.startswith("SRC_") and v < NSRC}
DST_NAMES = {v: k for k, v in E.items() if k.startswith("DST_") and v < NDST}
def jname(j):
    """a jack number as a name: output jacks -> SRC_*, input jacks -> DST_*"""
    if j == 0: return "-"
    if j < NSRC: return SRC_NAMES.get(j, "?out%d" % j)
    if j < NJACK: return DST_NAMES.get(j - NSRC + 1, "?in%d" % j)
    return "?%d" % j
def cname(c): return (jname(c[0]), jname(c[1]))
def plug_end(cab, c, end, e):
    """model of plug_end() in flat20.c: cab is a list of [a, b]; returns a new list"""
    cab = [list(x) for x in cab]
    j = (cab[c][end] + e + 4 * NJACK) % NJACK
    if j and j == cab[c][end ^ 1]:
        j = (j + (1 if e > 0 else -1) + NJACK) % NJACK
    cab[c][end] = j
    for k in range(len(cab)):
        for m in range(2):
            if j and (k != c or m != end) and cab[k][m] == j:
                cab[k][m] = 0
    return [tuple(x) for x in cab]
STATE_LEN = 7 + 3 + NPARAM + 2 * NCABLE + 3 + 12 + 1
LIVE_LEN = 14

def build():
    os.makedirs(os.path.dirname(BIN), exist_ok=True)
    subprocess.check_call(["cc", "-O2", "-Wall", "-Wno-unused-function", "-Wno-initializer-overrides", "-DDINGHY_HOST",
        "-DAPP_VER=\"dev\"", "-Ifirmware/hal", "-Ifirmware/src", "-Ifirmware/gen", "-o", BIN, "firmware/src/flat20.c"], cwd=ROOT)

def run(name, lines, env=None):
    """run a script; returns (messages [(ms, bytes)], stdout, wav path)"""
    script = os.path.join(TMP, name + ".txt")
    open(script, "w").write("\n".join(lines) + "\n")
    prefix = os.path.join(TMP, name)
    e = dict(os.environ)
    e.pop("DINGHY_SYSEX_FULL", None)
    e.update(env or {})
    r = subprocess.run([BIN, prefix, script], cwd=ROOT, env=e, capture_output=True, text=True, timeout=300)
    msgs = []
    for ln in r.stdout.splitlines():
        m = re.match(r"\s*(\d+) ms\s+SysEx out ((?:[0-9A-Fa-f]{2} ?)+)", ln)
        if m:
            msgs.append((int(m.group(1)), bytes(int(x, 16) for x in m.group(2).split())))
    return msgs, r.stdout, prefix + ".wav"

def state(b):
    n = b[7:10]
    p = list(b[10:10 + NPARAM])
    o = 10 + NPARAM
    cab = [(b[o + 2 * i], b[o + 2 * i + 1]) for i in range(NCABLE)]
    o += 2 * NCABLE
    name = bytes(b[o + 3:o + 15]).split(b"\0")[0].decode()
    return dict(counts=tuple(n), p=p, cab=cab, preset=b[o], flags=b[o + 1], oct=b[o + 2], name=name)

def live(b):
    return dict(gate=b[7], note=b[8], wheel=(b[9] << 7 | b[10]) - 127, button=b[11], lamps=b[12])

def states(msgs): return [(t, state(b)) for t, b in msgs if len(b) > 6 and b[6] == 1]
def lives(msgs): return [(t, live(b)) for t, b in msgs if len(b) > 6 and b[6] == 2]
def after(lst, t0, t1=10**9): return [(t, d) for t, d in lst if t0 <= t < t1]

def unpack7(data):   # ota_unpack7 from firmware/src/ota.c
    acc = nb = 0
    out = []
    for x in data:
        acc |= (x & 0x7F) << nb
        nb += 7
        if nb >= 8:
            out.append(acc & 0xFF)
            acc >>= 8
            nb -= 8
    return out

def turn(v, e):
    v += e * (4 if e > 2 or e < -2 else 2)
    return max(0, min(127, v))

def gaps_ok(lst, mn): return all(b[0] - a[0] >= mn for a, b in zip(lst, lst[1:]))

def main():
    build()
    all_msgs = []

    # --- idle run: boot state, heartbeat
    msgs, _, _ = run("idle", ["5000 end"])
    all_msgs += msgs
    S, L = states(msgs), lives(msgs)
    # 1. well formed
    bad = []
    for t, b in msgs:
        ok = (b[:5] == bytes([0xF0, 0x7D, 0x46, 0x32, 0x30]) and b[5] == LINK_VER and b[6] in (1, 2) and b[-1] == 0xF7
              and len(b) == (STATE_LEN if b[6] == 1 else LIVE_LEN) and all(x < 0x80 for x in b[1:-1]))
        if not ok: bad.append((t, b.hex()))
    check("1 every SysEx is well formed (header, version, type, length, 7-bit)", msgs and not bad, bad[:1])
    check("1 LINK_VERSION 2 in every message", msgs and all(b[5] == LINK_VER for _, b in msgs), [b[5] for _, b in msgs][:1])
    check("1 STATE counts equal ms20.h (%d/%d/%d)" % (NPARAM, NSRC, NDST), S and all(s["counts"] == (NPARAM, NSRC, NDST) for _, s in S))
    # 2. boot state
    first = [s for t, s in S if t <= 50]
    s = first[0] if first else {}
    exp_p = {"P_V1WAVE": 2 * 32 + 16, "P_V1SCALE": 16, "P_LP_PEAK": round(4.5 * 12.7)}
    check("2 a STATE within the first 50 ms", bool(first), [t for t, _ in S[:1]])
    check("2 boot params (V1WAVE, V1SCALE, LP_PEAK)", s and all(s["p"][E[k]] == v for k, v in exp_p.items()), s and [s["p"][E[k]] for k in exp_p])
    check("2 boot cables: 0 = EG2_REV jack <-> LP_CUT jack, rest (0,0)",
          s and s["cab"] == [(jout("SRC_EG2_REV"), jin("DST_LP_CUT"))] + [(0, 0)] * (NCABLE - 1), s and [cname(c) for c in s["cab"]])
    check("2 boot name FLAT BEAT, preset 1, flags 4 (takes CABLES), octave 3",
          s and (s["name"], s["preset"], s["flags"], s["oct"]) == ("FLAT BEAT", 1, 4, 3), s and (s["name"], s["preset"], s["flags"], s["oct"]))
    # 3. heartbeat
    def beats(lst): return all(b[0] - a[0] <= 1100 for a, b in zip(lst, lst[1:])) and lst[-1][0] >= 3900
    check("3 STATE at least every 1100 ms over 5 s", beats(S), [t for t, _ in S])
    check("3 LIVE at least every 1100 ms over 5 s", beats(L), [t for t, _ in L])
    check("3 no two STATEs closer than 25 ms", gaps_ok(S, 25))

    # 4. knob
    msgs, _, _ = run("knob", ["800 enc 2 -3", "2000 end"])
    all_msgs += msgs
    S = states(msgs)
    got = after(S, 800, 850)
    want = turn(127, -3)
    check("4 knob turn: STATE within 50 ms, LP_CUT %d, edited flag" % want,
          got and got[-1][1]["p"][E["P_LP_CUT"]] == want and got[-1][1]["flags"] & 2,
          got and (got[-1][1]["p"][E["P_LP_CUT"]], got[-1][1]["flags"]))

    # 5. program change
    msgs, _, _ = run("pc", ["300 midi 0xC0 6 0", "1500 end"])
    all_msgs += msgs
    S = [s for t, s in states(msgs) if t >= 300]
    s = S[0] if S else {}
    want = [(jout("SRC_WHITE"), jin("DST_SH_IN")), (jout("SRC_MG_RECT"), jin("DST_SH_CLOCK")), (jout("SRC_SH"), jin("DST_TOTAL"))]
    check("5 program change 6: preset, name, three cables",
          s and s["preset"] == 6 and s["name"] == "S&H RANDOM" and s["cab"] == want + [(0, 0)] * (NCABLE - 3),
          s and (s["preset"], s["name"], s["cab"]))

    # 6. patch editing (EDIT, then KNOB2/KNOB3 move a plug through all jacks; KNOB4 left unplugs both ends)
    msgs, _, _ = run("patch", ["300 btn 6", "600 enc 3 1", "900 enc 4 2", "1300 enc 5 -1", "2000 end"])
    all_msgs += msgs
    S = states(msgs)
    c0 = lambda lo, hi: [s["cab"][0] for t, s in after(S, lo, hi)]
    start = [(jout("SRC_EG2_REV"), jin("DST_LP_CUT"))] + [(0, 0)] * (NCABLE - 1)
    m1 = plug_end(start, 0, 0, 1)
    m2 = plug_end(m1, 0, 1, 2)
    check("6 KNOB2 +1 moves cable 0's first jack one on (%s)" % (cname(m1[0]),), c0(600, 800) and c0(600, 800)[-1] == m1[0], c0(600, 800))
    check("6 KNOB3 +2 moves cable 0's second jack two on (%s)" % (cname(m2[0]),), c0(900, 1200) and c0(900, 1200)[-1] == m2[0], c0(900, 1200))
    check("6 KNOB4 left unplugs both ends of cable 0", c0(1300, 1600) and c0(1300, 1600)[-1] == (0, 0), c0(1300, 1600))
    # wrap and steal: KNOB2 -1 from jack 0 wraps to the last jack; KNOB3 stepping onto a jack another end holds clears that end
    msgs, _, _ = run("patch2", ["300 btn 6", "600 enc 3 -1", "1000 enc 3 1", "1400 enc 5 1", "2000 end"])
    all_msgs += msgs
    S = states(msgs)
    w1 = plug_end(start, 0, 0, -1)
    check("6 KNOB2 -1 steps down one jack (%s)" % (cname(w1[0]),), c0(600, 900) and c0(600, 900)[-1] == w1[0], c0(600, 900))
    w2 = plug_end(w1, 0, 0, 1)
    check("6 KNOB2 +1 back again", c0(1000, 1300) and c0(1000, 1300)[-1] == w2[0] == start[0], c0(1000, 1300))
    check("6 KNOB4 right does nothing (cable 0 unchanged, no new STATE)", not c0(1400, 1900) or c0(1400, 1900)[-1] == start[0], c0(1400, 1900))
    # a plug stepped onto the other end's jack steps past it; moving onto another cable's jack takes it
    msgs, _, _ = run("patch3", ["300 midi 0xC0 6 0", "600 btn 6", "800 enc 4 1", "1200 enc 3 1", "2500 end"])
    all_msgs += msgs
    S = states(msgs)
    base = [(jout("SRC_WHITE"), jin("DST_SH_IN")), (jout("SRC_MG_RECT"), jin("DST_SH_CLOCK")), (jout("SRC_SH"), jin("DST_TOTAL"))] + [(0, 0)] * (NCABLE - 3)
    a = plug_end(base, 0, 1, 1)
    b = plug_end(a, 0, 0, 1)
    got = after(S, 800, 1100)
    check("6 KNOB3 +1 onto the next jack: cable 0 second end %s" % jname(a[0][1]), got and got[-1][1]["cab"] == a, got and got[-1][1]["cab"])
    got = after(S, 1200, 1500)
    check("6 KNOB2 +1 on preset 6: model of plug_end (steals, steps past)", got and got[-1][1]["cab"] == b, (got and got[-1][1]["cab"], b))
    other = lambda cab: sorted(j for c in cab for j in c if j)
    check("6 no jack ever has two plugs after editing", got and len(other(got[-1][1]["cab"])) == len(set(other(got[-1][1]["cab"]))), got and got[-1][1]["cab"])

    # 7. LIVE
    msgs, _, _ = run("live", ["500 keys 1", "900 keys 0", "1200 enc 1 1", "1600 enc 1 3", "2000 midi 0xB0 64 127", "2300 midi 0xB0 64 0", "3000 end"])
    all_msgs += msgs
    L = lives(msgs)
    d = after(L, 500, 540)
    check("7 key down: LIVE gate 1 note 53 within 40 ms", d and d[-1][1]["gate"] == 1 and d[-1][1]["note"] == 53, d)
    d = after(L, 900, 940)
    check("7 key up: gate 0, note still 53", d and d[-1][1]["gate"] == 0 and d[-1][1]["note"] == 53, d)
    w1, w2 = after(L, 1200, 1300), after(L, 1600, 1700)
    check("7 wheel 1 detent = +4", w1 and w1[-1][1]["wheel"] == 4, w1)
    check("7 wheel 3 detents = +24 more (28)", w2 and w2[-1][1]["wheel"] == 28, w2)
    on, off = after(L, 2000, 2100), after(L, 2300, 2400)
    check("7 MIDI CC 64 127 sets button, 0 clears", on and on[-1][1]["button"] == 1 and off and off[-1][1]["button"] == 0, (on, off))

    # 8. rate limit
    dirs = [-1] * 70 + [1] * 30          # 127 down to 0 (clamped), then up: the end value is not just a clamp
    ev = ["%d enc 2 %d" % (1000 + 5 * i, d) for i, d in enumerate(dirs)] + ["2500 end"]
    msgs, _, _ = run("rate", ev)
    all_msgs += msgs
    S = states(msgs)
    check("8 STATEs during a fast knob stream are >= 25 ms apart", gaps_ok(after(S, 900, 1700), 25), [t for t, _ in after(S, 900, 1700)])
    want = 127
    for d in dirs: want = turn(want, d)
    check("8 the last STATE reflects the final value (%d)" % want, S[-1][1]["p"][E["P_LP_CUT"]] == want, S[-1][1]["p"][E["P_LP_CUT"]])

    # 9. SysEx queue full
    msgs, out, wav = run("full", ["500 keys 1", "900 keys 0", "300 enc 2 1", "2500 end"], {"DINGHY_SYSEX_FULL": "1"})
    check("9 queue full: runs to the end, no SysEx, WAV written", not msgs and os.path.exists(wav) and os.path.getsize(wav) > 44, (len(msgs), os.path.exists(wav)))

    # 10. echo safety
    firsts = {unpack7(b[1:])[0] for _, b in all_msgs}
    check("10 echo safety: unpack7 of the bytes after F0 never starts with 0 (%d messages)" % len(all_msgs), all_msgs and 0 not in firsts, firsts)

    # 11. CABLES (computer -> FM-1)
    def hx(b): return " ".join("%02X" % x for x in b)
    def cables(pairs, ver=LINK_VER, nsrc=None, ndst=None, extra=0, cut=0):
        pairs = list(pairs) + [(0, 0)] * (NCABLE - len(pairs))
        b = [0xF0, 0x7D, 0x46, 0x32, 0x30, ver, 3, NSRC if nsrc is None else nsrc, NDST if ndst is None else ndst]
        for sd in pairs: b += list(sd)
        b += [0] * extra
        b = b[:len(b) - cut] if cut else b
        return b + [0xF7]
    def sysex(t, b): return "%d sysex %s" % (t, hx(b))
    def unclaimed(out): return [int(m.group(1)) for m in re.finditer(r"(\d+) ms\s+SysEx in, not the app's", out)]
    A, B = (jout("SRC_WHITE"), jin("DST_SH_IN")), (jout("SRC_MG_RECT"), jin("DST_SH_CLOCK"))
    pad = lambda l: l + [(0, 0)] * (NCABLE - len(l))

    msgs, out, _ = run("cab_ok", [sysex(300, cables([A, B])), "1500 end"])
    all_msgs += msgs
    S = states(msgs)
    check("11 every STATE has flag 4 (takes CABLES)", S and all(s["flags"] & 4 for _, s in S), [s["flags"] for _, s in S if not s["flags"] & 4][:1])
    got = after(S, 300, 350)
    check("11 valid CABLES: STATE within 50 ms with exactly those cables, edited flag",
          got and got[0][1]["cab"] == pad([A, B]) and got[0][1]["flags"] & 2, got and (got[0][1]["cab"], got[0][1]["flags"]))
    check("11 valid CABLES is claimed by the app", not unclaimed(out), unclaimed(out))

    I1, I2 = jin("DST_SH_IN"), jin("DST_LP_CUT")
    bads = [("two cables into one input", cables([A, (jout("SRC_MG_RECT"), I1)])),
            ("an output used by two cables", cables([A, (A[0], jin("DST_TOTAL"))])),
            ("an input used twice, in one cable and another", cables([A, (jin("DST_TOTAL"), A[1])])),
            ("both ends in one jack (input)", cables([A, B, (I2, I2)])),
            ("both ends in one jack (output)", cables([A, B, (3, 3)])),
            ("end >= MS_NJACK (first)", cables([A, B, (NJACK, 5)])),
            ("end >= MS_NJACK (second)", cables([A, B, (5, NJACK)])),
            ("end 127", cables([A, B, (5, 127)])),
            ("wrong version (1)", cables([(3, I2)], ver=1)),
            ("wrong version (3)", cables([(3, I2)], ver=3)),
            ("wrong NSRC", cables([(3, I2)], nsrc=NSRC + 1)),
            ("wrong NDST", cables([(3, I2)], ndst=NDST + 1)),
            ("one byte too short", cables([(3, I2)], cut=1)),
            ("one byte too long", cables([(3, I2)], extra=1))]
    ev = [sysex(300, cables([A, B]))] + [sysex(1500 + 1500 * i, b) for i, (_, b) in enumerate(bads)] + ["%d end" % (1500 * len(bads) + 3000)]
    msgs, out, _ = run("cab_bad", ev)
    all_msgs += msgs
    S = states(msgs)
    base = after(S, 300, 350)
    base = base[0][1] if base else None
    for i, (name, _) in enumerate(bads):
        t = 1500 + 1500 * i
        w = after(S, t, t + 1400)
        check("11 invalid CABLES (%s): cables and flags unchanged, claimed" % name,
              base and w and all(s == base for _, s in w) and t not in [x for x in unclaimed(out)] and not [x for x in unclaimed(out) if t <= x < t + 1400],
              w and [(s["cab"], s["flags"]) for _, s in w][:1])

    # accepted: a dummy plug, input-to-input, output-to-output, mixed
    for nm, cl in [("dummy plug (input jack, 0)", [A, (I2, 0)]), ("dummy plug (0, output jack)", [A, (0, 3)]),
                   ("input-to-input cable", [A, (I2, jin("DST_TOTAL"))]),
                   ("output-to-output cable", [A, (jout("SRC_MG_RECT"), jout("SRC_SH"))])]:
        msgs, out, _ = run("cab_acc", [sysex(300, cables(cl)), "1500 end"])
        all_msgs += msgs
        got = after(states(msgs), 300, 350)
        check("11 %s is accepted: next STATE has exactly those cables (%s)" % (nm, [cname(c) for c in cl]),
              got and got[0][1]["cab"] == pad(cl) and got[0][1]["flags"] & 2 and not unclaimed(out),
              got and [cname(c) for c in got[0][1]["cab"]])

    msgs, out, _ = run("cab_zero", [sysex(300, cables([A, B])), sysex(1000, cables([])), "2000 end"])
    all_msgs += msgs
    got = after(states(msgs), 1000, 1050)
    check("11 all-zero CABLES unplugs everything", got and got[0][1]["cab"] == pad([]), got and got[0][1]["cab"])

    msgs, out, _ = run("cab_cap", ["1500 end"])
    cap = [b for _, b in msgs if len(b) > 6 and b[6] == 1][0]
    msgs, out, _ = run("cab_foreign", [sysex(300, cables([A, B])), sysex(1000, [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]),
                                       sysex(2000, list(cap)), "3000 end"])
    S = states(msgs)
    check("11 foreign SysEx (identity request) is not claimed", [x for x in unclaimed(out) if 1000 <= x < 1100], unclaimed(out))
    w = after(S, 1000, 1900)
    check("11 foreign SysEx changes nothing", w and all(s["cab"] == pad([A, B]) for _, s in w), w and w[0][1]["cab"])
    w = after(S, 2000, 2900)
    check("11 echoed STATE: not claimed, cables unchanged", [x for x in unclaimed(out) if 2000 <= x < 2100] and w and all(s["cab"] == pad([A, B]) for _, s in w),
          (unclaimed(out), w and w[0][1]["cab"]))

    shutil.rmtree(TMP, ignore_errors=True)
    print("%d checks, %d failed" % (checks, fails))
    return 1 if fails else 0

sys.exit(main())
