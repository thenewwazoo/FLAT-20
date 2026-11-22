#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""The FM-1 screen's panel art, drawn here once so the firmware's main loop (integer only) just copies it:

  - lettering: Roboto Condensed (SIL OFL 1.1; the notice goes into the header) cut to anti-aliased 4-bit bitmaps in
    gfx.c's felucca_font_t layout, capitals only (gfx.c folds lower case up);
  - the knob as seen from the front (a fluted skirt, a domed cap, its shadow), RGB565 on black;
  - a lamp, off and lit;
  - sin() in whole degrees, Q14, for the pointer and the scales.

    .venv/bin/python tools/gen_panel_art.py RobotoCondensed[wght].ttf OFL.txt > firmware/gen/panel_art.h

(github.com/google/fonts: ofl/robotocondensed)."""
import math
import sys
from PIL import Image, ImageDraw, ImageFont

FACES = [                           # (name, pixel size, weight, gamma)
    ("FONT_NUM", 8, 500, 0.7),      # a scale's numbers around a knob
    ("FONT_LBL", 10, 500, 0.75),    # a control's name under its knob
    ("FONT_TTL", 11, 700, 0.8),     # a section's title
    ("FONT_BIG", 19, 500, 0.9),     # the program's name
]
FIRST, LAST = 32, 95
PAD = 1
KNOB_R = 13                         # the knob's radius in pixels
SS = 8                              # supersampling for the pictures


def face(path, size, weight, gamma):
    f = ImageFont.truetype(path, size)
    try:
        f.set_variation_by_axes([weight])
    except OSError:
        pass
    asc, desc = f.getmetrics()
    H = asc + desc + 4
    glyphs = []
    for ch in range(FIRST, LAST + 1):
        c = chr(ch)
        adv = int(round(f.getlength(c)))
        im = Image.new("L", (adv + 2 * PAD + 4, H), 0)
        ImageDraw.Draw(im).text((PAD, 2), c, font=f, fill=255)
        glyphs.append((adv, im))
    cap = glyphs[ord("H") - FIRST][1].getbbox()     # rows: the capitals' top to the baseline, and a comma's tail
    top, base = cap[1], cap[3]
    h = base - top + 2
    out = []
    for adv, im in glyphs:
        bb = im.getbbox()
        w = 0 if bb is None else bb[2]
        rows = [[min(15, int(round(15 * (im.getpixel((x, y)) / 255.0) ** gamma))) for x in range(w)]
                for y in range(top, top + h)]
        out.append((adv, w, rows))
    return h, out


def arr(t, n, v, per=20):
    s = f"static const {t} {n}[] = {{\n"
    for i in range(0, len(v), per):
        s += "    " + ", ".join(str(x) for x in v[i:i + per]) + ",\n"
    return s + "};\n"


def emit_font(name, h, glyphs):
    adv, bw, off, data = [], [], [], []
    for a, w, rows in glyphs:
        adv.append(a)
        bw.append(w)
        off.append(len(data))
        for r in rows:
            r = r + [0] * (w & 1)
            data += [(r[i] << 4) | r[i + 1] for i in range(0, len(r), 2)]
    s = arr("uint8_t", name + "_ADV", adv) + arr("uint8_t", name + "_BW", bw)
    s += arr("uint16_t", name + "_OFF", off) + arr("uint8_t", name + "_DATA", data)
    s += f"static const felucca_font_t {name} = {{ {h}, {PAD}, {FIRST}, {LAST}, {name}_ADV, {name}_BW, {name}_OFF, {name}_DATA }};\n"
    return s


def rgb565(p):
    r, g, b = p[:3]
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def knob():
    """The knob from the front, lit from the upper left: a soft shadow down-right, a fluted skirt, a domed cap."""
    R = KNOB_R
    N = 2 * R + 4                                   # (room for the shadow)
    S = N * SS
    c = (R + 1) * SS + SS / 2                       # the knob's center (supersampled), one pixel in from the top left
    im = Image.new("RGB", (S, S), (0, 0, 0))
    px = im.load()
    r_out, r_cap = R * SS, R * 0.74 * SS
    flutes = 20
    for y in range(S):
        for x in range(S):
            dx, dy = x + 0.5 - c, y + 0.5 - c
            d = math.hypot(dx, dy)
            sd = math.hypot(dx - 1.6 * SS, dy - 2.2 * SS)
            if d > r_out:
                if sd < r_out + SS:
                    k = max(0.0, min(1.0, (r_out + SS - sd) / (1.5 * SS)))
                    px[x, y] = (int(10 * k),) * 3       # the shadow on the panel (black to a near black)
                continue
            a = math.atan2(dy, dx)
            lit = max(0.0, math.cos(a - math.radians(-135)))   # toward the upper left
            if d > r_cap:
                fl = 0.5 + 0.5 * math.cos(a * flutes)
                v = 22 + 40 * lit * (0.35 + 0.65 * fl) + 10 * fl
                if d > r_out - 0.9 * SS:
                    v = v * 0.75 + 18
                px[x, y] = (int(v), int(v), int(v + 2))
            else:
                # the cap: a dome, brightest a third of the way to the upper left, a dark edge
                hx, hy = dx + 0.38 * r_cap, dy + 0.45 * r_cap
                g = max(0.0, 1.0 - math.hypot(hx, hy) / (1.5 * r_cap))
                v = 9 + 46 * g * g
                if d > r_cap - 0.9 * SS:
                    v *= 0.55
                px[x, y] = (int(v), int(v), int(v + 2))
    im = im.resize((N, N), Image.BOX)
    return N, [rgb565(im.getpixel((x, y))) for y in range(N) for x in range(N)]


def lamp(on):
    """A small red lamp in a black bezel: 9 x 9."""
    N, S = 9, 9 * SS
    im = Image.new("RGB", (S, S), (0, 0, 0))
    px = im.load()
    c = S / 2
    for y in range(S):
        for x in range(S):
            d = math.hypot(x + 0.5 - c, y + 0.5 - c) / SS
            if d > 4.4:
                continue
            if d > 3.4:
                px[x, y] = (48, 46, 46)             # the bezel
                continue
            hx, hy = (x + 0.5 - c) / SS + 1.0, (y + 0.5 - c) / SS + 1.1
            h = max(0.0, 1.0 - math.hypot(hx, hy) / 3.2)
            if on:
                px[x, y] = (int(200 + 55 * h), int(30 + 170 * h ** 3), int(20 + 150 * h ** 3))
            else:
                px[x, y] = (int(48 + 40 * h * h), int(10 + 14 * h * h), int(10 + 14 * h * h))
    im = im.resize((N, N), Image.BOX)
    return N, [rgb565(im.getpixel((x, y))) for y in range(N) for x in range(N)]


def main():
    path, ofl = sys.argv[1], sys.argv[2]
    notice = open(ofl, encoding="utf-8").read().strip().splitlines()
    print("/* generated by tools/gen_panel_art.py: the screen's lettering (Roboto Condensed, github.com/google/fonts,")
    print(" * ofl/robotocondensed: " + ", ".join(f"{n} {s} px weight {w}" for n, s, w, _ in FACES) + "),")
    print(" * the knob, the lamp and a sine table. The font's licence:")
    print(" *")
    for line in notice:
        print((" * " + line.replace("*/", "* /")).rstrip())
    print(" */")
    for n, size, w, g in FACES:
        h, gl = face(path, size, w, g)
        print(emit_font(n, h, gl))
    n, k = knob()
    print(f"#define KNOB_R {KNOB_R}\n#define KNOB_N {n}                      /* the picture's side; the knob's center is at ({KNOB_R + 1}, {KNOB_R + 1}) */")
    print(f"#define KNOB_C {KNOB_R + 1}")
    print(arr("uint16_t", "KNOB_PX", k, 16))
    n, l0 = lamp(False)
    _, l1 = lamp(True)
    print(f"#define LAMP_N {n}")
    print(arr("uint16_t", "LAMP_PX", l0 + l1, 18))
    print(arr("int16_t", "SIN_Q14", [int(round(16384 * math.sin(math.radians(d)))) for d in range(91)], 13))
    # ms20.h's ms_taper (an "A" pot, 15 % at the middle) at each of a knob's 128 steps, Q16
    taper = [(2 ** (v / 127 * 5.0048) - 1) / 31.11 for v in range(128)]
    print("/* ms_taper(v / 127), Q16: an A pot's share of its resistance at each knob step (ms20.h) */")
    print(arr("uint16_t", "TAPER_Q16", [min(65535, int(round(65536 * t))) for t in taper], 16))
    print("/* exp(-i / 32), Q12, i = 0 .. 256 (8 time constants): an RC's charge and discharge */")
    print(arr("uint16_t", "EXP_Q12", [int(round(4096 * math.exp(-i / 32))) for i in range(257)], 16))
    pal, runs = splash()
    print("/* the splash screen (assets/splash.png, 240 x 240): 32 colours (RGB565), then runs of (colour, length - 1) row by row */")
    print(arr("uint16_t", "SPLASH_PAL", pal, 16))
    print(arr("uint8_t", "SPLASH_RLE", runs, 24))


def splash():
    """assets/splash.png as a 32-colour palette and runs of up to 256 pixels of one colour (most of it is flat)."""
    from pathlib import Path
    im = Image.open(Path(__file__).resolve().parent.parent / "assets" / "splash.png").convert("RGBA")
    flat = Image.new("RGB", im.size, (0, 0, 0))
    flat.paste(im, mask=im.split()[3])
    if flat.size != (240, 240):
        raise SystemExit("assets/splash.png: 240 x 240, please")
    q = flat.quantize(32, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    p = q.getpalette()[:96]
    pal = [rgb565((p[3 * i], p[3 * i + 1], p[3 * i + 2])) for i in range(32)]
    d = [q.getpixel((x, y)) for y in range(240) for x in range(240)]
    runs, i = [], 0
    while i < len(d):
        j = i
        while j < len(d) and d[j] == d[i] and j - i < 256:
            j += 1
        runs += [d[i], j - i - 1]
        i = j
    return pal, runs


if __name__ == "__main__":
    main()
