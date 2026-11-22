#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Compare a USB-connected FM-1 against build/host/flat20 across all factory presets.
# Records each preset over USB audio while triggering via USB MIDI, then compares dominant pitch
# and normalized 1/3-octave spectra (independent of MASTER volume).
#   device_check.py [OUT_DIR]   (requires build/host/flat20; run tests/run_host.sh first)
import os, subprocess, sys, tempfile, wave
import numpy as np
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.join(HERE, "..", "..")
NAMES = ["INIT", "FLAT BEAT", "DA FUNK", "SCREAMER", "HP SQUEAL", "RING BELL", "S&H RANDOM", "DELAY VIB", "FEEDBACK", "AUTO TRIG",
         "KICK", "WIND", "EG1 SWOOP", "WHEEL>VCO2", "F-V TRACK", "INIT 16",
         "FADE TO GRY", "LEATHERETTE", "FAD GADGET", "JARRE SWEEP", "DIDGERIDOO", "STEREOLAB", "SOUR TIMES", "VOODOO PPL", "SEXY BOY", "STRICT MCH"]
STEP, NOTE = 3.0, 57
# a held, steady note: what must agree. The others move while they sound (an envelope on the filter, the MG, noise):
# they are listed, but two takes of them differ as much as these do
STEADY = {"INIT", "DA FUNK", "SCREAMER", "RING BELL", "DELAY VIB", "WHEEL>VCO2", "F-V TRACK", "INIT 16",
          "FADE TO GRY", "LEATHERETTE", "FAD GADGET", "STEREOLAB", "SOUR TIMES", "VOODOO PPL", "SEXY BOY", "STRICT MCH"}

def load(p):
    w = wave.open(p); fs = w.getframerate(); ch = w.getnchannels()
    return np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch)[:, 0].astype(float) / 32768, fs

def bands(x, fs):
    N = len(x); sp = np.abs(np.fft.rfft(x * np.hanning(N))) ** 2; f = np.fft.rfftfreq(N, 1 / fs)
    fc = 31.25 * 2 ** (np.arange(0, 27) / 3.0)          # 31 Hz .. 12.7 kHz
    p = np.array([sp[(f >= c / 2 ** (1 / 6)) & (f < c * 2 ** (1 / 6))].sum() for c in fc])
    k = np.argmax(sp[int(25 * N / fs):]) + int(25 * N / fs)
    return fc, 10 * np.log10(p / p.sum() + 1e-12), f[k], np.sqrt(np.mean(x * x))

def notes(x, fs, t_first):
    """the held part of each preset's note: found by its onset near where it was asked for"""
    out = []
    env = np.sqrt(np.convolve(x * x, np.ones(int(fs * 0.005)) / int(fs * 0.005), "same"))
    for i in range(16):
        a = int((t_first + i * STEP - 0.25) * fs); b = int((t_first + i * STEP + 0.6) * fs)
        seg = env[a:b]; thr = max(seg.max() * 0.2, 1e-4); on = a + int(np.argmax(seg > thr))
        out.append(x[on + int(0.25 * fs): on + int(1.15 * fs)])
    return out

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else tempfile.gettempdir()
    script = os.path.join(out, "device_check.txt"); ev = []
    with open(script, "w") as f:
        for i in range(16):
            t = 300 + int(i * STEP * 1000)
            f.write("%d midi 0xC0 %d 0\n%d midi 0x90 %d 100\n%d midi 0x80 %d 0\n" % (t, i, t + 500, NOTE, t + 1900, NOTE))
            ev += ["%.3f:pc=%d" % (t / 1000, i), "%.3f:on=%d" % ((t + 500) / 1000, NOTE), "%.3f:off=%d" % ((t + 1900) / 1000, NOTE)]
        f.write("%d end\n" % (300 + int(16 * STEP * 1000)))
    host = os.path.join(out, "device_check_host")
    subprocess.run([os.path.join(ROOT, "build/host/flat20"), host, script], check=True, stdout=subprocess.DEVNULL)
    dev = os.path.join(out, "device_check_fm1.wav")
    subprocess.run([sys.executable, os.path.join(ROOT, "tools/fm1_play_rec.py"), dev, str(1.0 + 16 * STEP)] + ev, check=True)
    xh, fh = load(host + ".wav"); xd, fd = load(dev)
    nh = notes(xh, fh, 0.8); nd = notes(xd, fd, 0.8)
    print("%-12s %10s %10s %8s   %s" % ("preset", "FM-1 Hz", "host Hz", "cents", "spectrum: rms difference over the bands within 40 dB of the loudest"))
    worst = worst_c = 0
    for i in range(16):
        fc, bd, pd, rd = bands(nd[i], fd); _, bh, ph, rh = bands(nh[i], fh)
        m = (bh > bh.max() - 40) | (bd > bd.max() - 40)
        e = np.sqrt(np.mean((bd[m] - bh[m]) ** 2)); c = 1200 * np.log2(pd / ph) if ph > 0 and pd > 0 else 0
        if NAMES[i] in STEADY: worst = max(worst, e); worst_c = max(worst_c, abs(c))
        print("%-12s %10.2f %10.2f %+8.1f   %.2f dB   (level re INIT: FM-1 %+.1f dB, host %+.1f dB)" % (NAMES[i] + ("" if NAMES[i] in STEADY else " ~"), pd, ph, c, e,
              20 * np.log10(rd / (np.sqrt(np.mean(nd[0] ** 2)) + 1e-12) + 1e-12), 20 * np.log10(rh / (np.sqrt(np.mean(nh[0] ** 2)) + 1e-12) + 1e-12)))
    print("steady presets: worst pitch difference %.1f cents, worst spectrum difference %.2f dB   (~: moving sounds, not counted)" % (worst_c, worst))
    sys.exit(0 if worst < 1.0 and worst_c < 2.0 else 1)

if __name__ == "__main__":
    main()
