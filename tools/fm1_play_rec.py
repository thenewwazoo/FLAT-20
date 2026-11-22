#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
# Send MIDI events to a connected FM-1 while recording its USB audio output.
#   fm1_play_rec.py OUT.wav SECONDS [T:EVENT ...]   (T in seconds; EVENT: pc=N, on=NOTE, off=NOTE, cc=NUM,VAL, bend=-8192..8191)
# Uses PortAudio (sounddevice) instead of ffmpeg avfoundation, which drops frames on macOS.
import sys, time, wave, threading
import mido, sounddevice as sd

def main():
    out, secs = sys.argv[1], float(sys.argv[2])
    ev = []
    for a in sys.argv[3:]:
        t, e = a.split(":", 1); k, v = (e.split("=", 1) + [""])[:2]; ev.append((float(t), k, v))
    ev.sort()
    port = [n for n in mido.get_output_names() if "FM-1" in n or "FLAT" in n.upper()][0]
    dev = [i for i, d in enumerate(sd.query_devices()) if d["max_input_channels"] > 0 and ("felucca" in d["name"].lower() or "fm-1" in d["name"].lower())][0]
    fs = int(sd.query_devices(dev)["default_samplerate"])
    o = mido.open_output(port)
    x = sd.rec(int(secs * fs), samplerate=fs, channels=2, dtype="int16", device=dev, blocksize=4096)
    t0 = time.time()
    for t, k, v in ev:
        d = t0 + t - time.time()
        if d > 0: time.sleep(d)
        if k == "pc": o.send(mido.Message("program_change", program=int(v)))
        elif k == "on": o.send(mido.Message("note_on", note=int(v), velocity=100))
        elif k == "off": o.send(mido.Message("note_off", note=int(v)))
        elif k == "cc": n, val = v.split(","); o.send(mido.Message("control_change", control=int(n), value=int(val)))
        elif k == "bend": o.send(mido.Message("pitchwheel", pitch=int(v)))
    sd.wait()
    w = wave.open(out, "wb"); w.setnchannels(2); w.setsampwidth(2); w.setframerate(fs); w.writeframes(x.tobytes()); w.close()

if __name__ == "__main__":
    main()
