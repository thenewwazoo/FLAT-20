# SPDX-License-Identifier: GPL-3.0-only
# Compare the engine against the GAK "KORG Sound Icons" MS-20 mini Flat Beat recording
# (harmonics 1, 3, 5, 7, 9, 13, 21 from 20 to 300 ms). Used as a validation check, not a fit.
#   flatbeat.py REF.wav [render args to override]   (REF.wav: video audio; notes at 97.28 s and 99.28 s)
import numpy as np, wave, subprocess, os, sys, tempfile
H = [1, 3, 5, 7, 9, 13, 21]; T = [20, 30, 40, 50, 70, 90, 120, 150, 200, 250, 300]
def table(path, t0, t1, onset=None, f0=58.3):
    w = wave.open(path); fs = w.getframerate(); ch = w.getnchannels()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).reshape(-1, ch)[:, 0].astype(float) / 32768
    x = x[int(t0 * fs):int(t1 * fs)]; X0 = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / fs); hop = fs // 200; E = []
    for h in H:
        X = X0.copy(); X[(f < f0 * h - f0 * 0.6) | (f > f0 * h + f0 * 0.6)] = 0
        X2 = np.zeros(len(x), complex); X2[:len(X)] = 2 * X; X2[0] = 0
        E.append(np.abs(np.fft.ifft(X2))[::hop])
    if onset is None:
        env = E[0]; thr = env.max() * 0.35; onset = [i for i in range(2, len(env)) if env[i] > thr and env[i - 2] < thr * 0.5][0]
    else: onset = int((onset - t0) * 200)
    ref = E[0][onset:onset + 60].max()
    return np.array([[20 * np.log10(e[onset + t // 5] / ref + 1e-6) for e in E] for t in T])
if __name__ == "__main__":
    ref = sys.argv[1]
    real = (table(ref, 96.5, 98.5, 97.28) + table(ref, 98.5, 100.5, 99.28)) / 2
    out = os.path.join(tempfile.gettempdir(), "flatbeat.wav")
    here = os.path.dirname(os.path.abspath(__file__))
    args = ["v1wave=pulse", "v1pw=0", "v1scale=32", "mix1=9.5", "hpcut=0.3", "lpcut=10", "lppeak=4.5", "lpeg=10", "e2atk=0",
            "e2dec=1.6", "e2sus=0", "e2rel=0", "volume=10", "eg2rev:lpcut"] + sys.argv[2:] + ["@200", "on=58", "@800", "off"]
    subprocess.run([os.path.join(here, "../../build/host/render"), out, "1.5"] + args, check=True, stderr=subprocess.DEVNULL)
    m = table(out, 0, 1.5, None)
    d = np.clip(m, -58, 5) - np.clip(real, -58, 5)
    print("rms error %.1f dB, worst %.1f dB, over %d points" % (np.sqrt(np.mean(d * d)), np.abs(d).max(), d.size))
    print("  ms   MS-20 mini: " + " ".join("h%-3d" % h for h in H) + "   | engine")
    for i, t in enumerate(T): print("%4d              " % t + " ".join("%4.0f" % v for v in real[i]) + "   | " + " ".join("%4.0f" % v for v in m[i]))
