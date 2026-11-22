#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Virtual FM-1 for testing the macOS panel app (mac/) without hardware.
# Runs the host firmware build (build/host/flat20) and replays its SysEx output over a virtual MIDI port.
#   fake_fm1.py [SCRIPT] [--loop] [--port NAME]   (default script cycles through all 16 presets)
import argparse, os, re, subprocess, sys, tempfile, time
import mido

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TOUR = """# every preset in turn: a note held, a knob turned, then the next
%s
%d end
"""

def tour():
    lines, t = [], 300
    for p in range(16):
        lines += ["%d midi 0xC0 %d 0" % (t, p), "%d keys 1" % (t + 400), "%d enc 2 4" % (t + 900), "%d enc 2 -4" % (t + 1300),
                  "%d enc 1 2" % (t + 1600), "%d enc 1 -2" % (t + 2000), "%d keys 0" % (t + 2200)]
        t += 3000
    # some patching on INIT 16: three cables in, one out
    lines += ["%d midi 0xC0 15 0" % t, "%d btn 6" % (t + 300)]
    for i, (k1, k2, k3) in enumerate([(0, 3, 6), (1, 2, 1), (1, 9, 11)]):
        lines += ["%d enc 2 %d" % (t + 600 + i * 900, k1), "%d enc 3 %d" % (t + 800 + i * 900, k2), "%d enc 4 %d" % (t + 1000 + i * 900, k3)]
    lines += ["%d enc 5 -1" % (t + 4000), "%d btn 6" % (t + 4600)]
    return TOUR % ("\n".join(lines), t + 6000)

def main():
    a = argparse.ArgumentParser()
    a.add_argument("script", nargs="?")
    a.add_argument("--loop", action="store_true")
    a.add_argument("--port", default="FM-1 Midi (simulated)")
    o = a.parse_args()
    exe = os.path.join(ROOT, "build/host/flat20")
    subprocess.run(["cc", "-O2", "-w", "-DDINGHY_HOST", '-DAPP_VER="dev"', "-I" + ROOT + "/firmware/hal", "-I" + ROOT + "/firmware/src",
                    "-I" + ROOT + "/firmware/gen", "-o", exe, ROOT + "/firmware/src/flat20.c"], check=True)
    d = tempfile.mkdtemp()
    script = o.script
    if not script:
        script = os.path.join(d, "tour.txt"); open(script, "w").write(tour())
    log = subprocess.run([exe, os.path.join(d, "out"), script], capture_output=True, text=True, check=True).stdout
    msgs = []
    for line in log.splitlines():
        m = re.match(r"\s*(\d+) ms  SysEx out (.*)", line)
        if m:
            b = [int(x, 16) for x in m.group(2).split()]
            msgs.append((int(m.group(1)) / 1000.0, b[1:-1]))
    print("%d messages over %.1f s, through \"%s\"" % (len(msgs), msgs[-1][0], o.port), flush=True)
    port = mido.open_output(o.port, virtual=True)
    time.sleep(1.0)                                  # (time for listeners to see the new port)
    while True:
        t0 = time.time()
        for t, data in msgs:
            dt = t0 + t - time.time()
            if dt > 0: time.sleep(dt)
            port.send(mido.Message("sysex", data=data))
        if not o.loop: break
    time.sleep(0.5)

if __name__ == "__main__":
    main()
