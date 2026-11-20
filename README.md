# FLAT-20

The Korg MS-20, as firmware for the M-VAVE FM-1: the instrument's circuit, part for part, running on the FM-1's own
processor. Not affiliated with Korg; no Korg code. Built on [Dinghy](https://github.com/zvenson/dinghy) (GPL-3.0-only;
its own README is [docs/DINGHY.md](docs/DINGHY.md)), which carries Felucca's platform.

**Status: 0.2.** Runs on an FM-1, and was measured there: in tune over USB audio and at the speaker, every factory
preset identical to the same firmware run on a computer, 56 % of the audio interrupt's time.

## What it is

The engine (`firmware/src/ms20.h`) is the MS-20's first board set (KLM-127 with two KORG35 filters, KLM-128, KLM-129)
taken from Korg's service manual: each resistor and capacitor that shapes the sound is in the code under its part
number, and [docs/MS20-CIRCUIT.md](docs/MS20-CIRCUIT.md) lists them with where each came from. The handful of numbers
a diagram cannot give (the inside of the KORG35 chip, the curve of an "A" pot) come from recordings of instruments
and are marked as such.

What that means for how it plays, because these are the things an "MS-20-style" synthesizer usually gets wrong:

- **Pitch is Hz / V.** KBD CV OUT is 1 V at the lowest C and 8 V at the highest; VCO 1 + 2 CV IN and VCO 2 CV IN are
  linear (twice the volts, twice the hertz; 0 V is silence). Only the two FM knobs, MASTER TUNE and PITCH are
  exponential. EG1 reaches the VCOs as -5 V at rest: with EG1 / EXT up, a note climbs to its pitch.
- **Triggers are switch triggers:** +5 V at rest, ground while on. The MG's rectangle in TRIG IN plays the note while
  it is *low*; the momentary switch is a contact to ground and nothing else.
- **The filters are KORG35s:** a Sallen-Key pair on unequal capacitors into an amplifier of 58 with two diodes across
  it. The diodes are in the signal's path, so everything is squashed a little, more with both VCOs up, and a singing
  filter settles where the diodes let it. The high-pass is 6 dB an octave. The signal itself moves the chip's
  resistance, which is why the resonance is lopsided.
- **EG2 reaches the filters less SUSTAIN's voltage.** With SUSTAIN up, CUTOFF is where the filter sits while a key is
  held, and it is *below* that before and after the note. REV OUT is the same upside down.
- **The VCA is one transistor:** shut until EG2 is past 0.4 V, then in proportion, a little lopsided, into an
  amplifier that rolls off at 8.8 kHz. INITIAL GAIN is whichever of it and EG2 is higher, not their sum.
- **The "sample and hold" follows** its input while its clock is high (or unplugged) and holds while it is low: for
  steps, narrow the MG's rectangle with WAVE FORM.
- **The modulation VCA is opened by EG1** unless something is plugged into its CONTROL INPUT, and it is a lamp and a
  photocell: slow. MG into it and its output into TOTAL is the vibrato that comes in late.
- **The keyboard** plays the highest key held, and a new key while another is down does not start the envelopes
  again. PORTAMENTO glides only while a key is down.
- "Pink" noise falls 6 dB an octave, the triangle has one flattened tip, PW stops at a sliver, the MG runs 0.1 to
  20 Hz in proportion to its knob and its shape does not change its rate.

## What differs from an MS-20

- **The filter board is the first one.** Later MS-20s have a different filter (KLM-307, two LM13600s); it is not here.
- **No drift, no tolerances:** the two VCOs track each other exactly, every part has its printed value, the cutoff
  does not move with the room's temperature. There is no hum, and only a trace of hiss.
- **The external signal processor has no jack:** the FM-1 has no audio input, so its SIGNAL IN is a cable from
  another jack. (Its amplifier is made for a microphone: a patch-panel signal clips it almost at once.)
- **VCO 1 and VCO 2 are patch outputs** (marked `*` on the screen). The MS-20's panel has none.
- **The wheel** is the ALGORITHM encoder and stays where it is left; the momentary switch is REC.
- **PLAY** holds the key down for you; there are 16 presets, 8 cables, MIDI and USB audio.
- The FM-1 has 27 keys (the MS-20: 37, C3 to C6 at 8'); OCT- / OCT+ move them, MIDI plays any note.
- Where the service manual's diagram and its specification sheet disagree, the diagram is followed: MASTER TUNE is
  +-212 cents (sheet: 100), PITCH +-1.1 octaves, HOLD 14 s (20), DELAY 9.4 s (10), EG1's OUT jack 0 to +5 V (the sheet
  says -5 to 0 V; the panel's own legend says 0 to +5 V).
- Not measured on an instrument, and said so in the circuit document: how strongly the signal moves the KORG35's
  cutoff (taken from the device equation), the photocell's speed, the F-V converter's pulse width, and the direction
  of the headphone feedback loop (three inverting stages by the diagram: it thins and whistles, it does not fatten).

## How it was checked

**The circuit against itself** (`tests/ms20_test.c`, 74 checks, no hardware): pitch to a cent and a half over the
keyboard and every SCALE, the CV inputs' volts to hertz, each waveform's level, 500 Hz at CUTOFF 5 with PEAK at 10
(the adjustment procedure), 13 Hz and 15.3 kHz at the stops, the low-pass within 1 dB of two real poles and the
high-pass's 6 dB, where PEAK starts to sing, every envelope voltage and time against its RC, the trigger inputs, the
sample and hold, the modulation VCA, the F-V converter, and 400 random patches without a sample out of bounds.

**Recordings of instruments**, each used for one thing the diagram leaves open, not to tune the sound:

| What was open | From | Result |
| --- | --- | --- |
| Which C is 1 V | GAK's "Flat Beat" video (MS-20 mini): a 58.3 Hz note at 32' on the first octave's B flat | the lowest C is C3 at 8' |
| VCO 2's sawtooth level (the diagram shows it 9 dB hotter than VCO 1's) | GAK's "Da Funk" video: two sawtooths, both level knobs alike | fundamentals within 1 dB: both through 100 k |
| The KORG35's inner resistor ratio (where PEAK starts to sing) | Marc Doty's MS-20 mini filter video: resonant but silent near 7.5 - 8, singing by 8.7 - 9; Da Funk has both PEAKs at 8 | 1.5: it starts at 8.7 |
| The cutoff's octaves a volt | a vintage MS-20's low-pass singing from stop to stop: 13 Hz to 15.3 kHz (Kick.S) | +-5.27 octaves about 500 Hz |
| EG1's OUT jack: 0 to +5 V or -5 to 0 V | the panel's legend in the same videos | 0 to +5 V, as the diagram |
| An "A" pot's curve | none: the usual 15 % at the middle | see below |

*As a check, not a fit:* the Flat Beat patch with the panel as the video shows it (`tools/ms20fit/flatbeat.py`):
harmonics 1 to 21 from 20 to 300 ms into the note, 77 points. The note's loudness follows the recording within 2 dB
to 250 ms and 3 dB at 300 (the transistor VCA and the 15 % taper, nothing adjusted). The filter's opening is within what the knobs
can be read to: the whole comparison is 5.6 dB rms with EG2 / EXT at 10 and 3.9 dB at 9.8, a twentieth of a turn at
the steep end of an audio-taper pot. The engine before this one matched the same notes to 2.1 dB with its constants
fitted to them; none is fitted here.

**An FM-1** (`tools/ms20fit/device_check.py`, `tools/fm1_play_rec.py`): all sixteen presets played over USB MIDI and
recorded over USB audio beside the same firmware on the computer. The steady ones agree to 0.0 cents and half a dB in
third-octave bands; the others differ only by where their noise and free-running MG happened to be. A4 is 440.000 Hz
over USB and 440.25 Hz at the speaker (a microphone). The render takes 56 % of its time.

One thing found on the way belongs to the platform, not the synthesizer: a render longer than about 2 ms in one
piece starved the USB audio ring, and the computer recorded everything 1.9 % flat (33 cents) while the speaker was in
tune. `platform.c` now renders and hands over a half buffer in eight pieces.

## Playing it

| | |
| --- | --- |
| SELECT | the page: VCO 1, VCO 2, MIXER / FM, HIGH PASS, LOW PASS, MG / EG 1, EG 2, MORE, EXT SIGNAL PROC, PATCH PANEL |
| KNOB 1..4 | the page's four controls, 0.0 to 10.0 as on the panel |
| HOME, FX, ENV, LFO, EDIT | to the VCOs, the filters, the envelopes, the MG, the patch panel / ESP (press again: the next of the group) |
| PATCH PANEL | KNOB 1 the cable (1..8), KNOB 2 its output, KNOB 3 its input, KNOB 4 turned left pulls it out. A plug in an input disconnects what is wired to it inside, as on the MS-20 |
| ALGORITHM | the wheel, -5 .. +5 V (shown at the bottom) |
| REC | the momentary switch (to ground while held) |
| PLAY | hold: the key stays down |
| PRESETS, SAVE | one of 16 presets; SAVE keeps the sound in it (written when the sound stops) |
| OCT-, OCT+ | the octave |
| MIDI in (USB, TRS) | notes (48 = the MS-20's lowest C), pitch bend +-2, CC 1 the wheel's upper half, CC 2 the whole wheel (64 = centre), CC 64 the switch, CC 16..51 the knobs in the order of `ms20.h`, program change the preset |

The presets after INIT each show one of the MS-20's ways: FLAT BEAT and DA FUNK as the videos above set them, SCREAMER
and HP SQUEAL (the filters at the edge), RING BELL, S&H RANDOM, DELAY VIB (the modulation VCA and EG1), FEEDBACK
(PHONES into EXT SIGNAL IN), AUTO TRIG (the MG into TRIG IN), KICK (a singing filter, no oscillator), WIND, EG1 SWOOP,
WHEEL>VCO2 (a VCO off the keyboard, in Hz / V), F-V TRACK (the signal processor playing VCO 2).

## The panel on a Mac

`mac/` is a Mac app that shows the FM-1's settings as an MS-20 panel, knobs, cables and all, kept up to date over the
USB cable, and lets you patch it with the mouse. See [mac/README.md](mac/README.md).

## Building

`docs/DINGHY.md` has the set-up (JieLi toolchain, AC79 SDK, Docker on a Mac). Then:

```sh
./build.sh                                          # build/dinghy.fwsc, identity FM-1_950
python3 tools/fm1_install.py build/dinghy.fwsc      # onto the FM-1 over USB
sh tests/run_tests.sh                               # the engine's checks and the platform's, on this computer
cc -O2 -Ifirmware/src -o build/host/render tests/render.c
build/host/render out.wav 2 v1wave=pulse lpcut=6 lppeak=7 eg2rev:lpcut @100 on=57 @900 off    # the engine alone: any patch as a WAV
python3 tools/ms20fit/device_check.py               # an FM-1 on USB against tests/run_host.sh's binary
```

The engine is one header: float, no libm, no allocation; the same file runs in the FM-1's audio interrupt (built with
`-mcpu=r3 -mfprev1` for the chip's FPU; float is used nowhere else) and in the tests. It runs at 88.2 kHz and is
decimated. The instrument around it is `firmware/src/dinghy.c`.

Recording the FM-1 on a Mac for measurements: use PortAudio (`tools/fm1_play_rec.py`), not `ffmpeg -f avfoundation`,
which drops chunks of the stream.
