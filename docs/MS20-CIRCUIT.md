# MS-20 Circuit Reference (`firmware/src/ms20.h`)

This document traces every constant and circuit block in `firmware/src/ms20.h` back to its source.

## Source legend

- **D** — Korg MS-20 Service Manual: schematics (1) KLM-127 and (2) KLM-128 / KLM-129, block diagram test points, specification sheet, and adjustment procedure. Covers the first board revision (dual KORG35 filters). Reference scans on archive.org: `korg_MS-20_SERVICE_MANUAL`, `JL11276` (schematics are not included in this repo).
- **S** — T. E. Stinchcombe, *A Study of the Korg MS10 & MS20 Filters* (2006), covering the internal topology and behavior of the KORG35 IC.
- **R** — Hardware recordings, used only where the schematic doesn't specify a value (internal IC parameters, pot taper) or where two readings of the schematic needed disambiguation.
- **A** — Assumed standard component value, noted inline.

All internal signals in the engine are represented in real MS-20 voltages. Most of the entries below are verified by `tests/ms20_test.c`.

## Pitch & Keyboard

| Circuit block | Source | Model in `ms20.h` |
| --- | --- | --- |
| Keyboard resistor ladder (1% resistors, read from top end) | D (1) | High-note priority; single trigger held while any key is down |
| `KBD CV OUT` (0 to +8 V, exponential; C3 is half of C4) | D spec, adjustment | 1 V at lowest C, 8 V at highest: `volts = 2^((note - 48) / 12)` |
| Reference C for 1 V | R: GAK "Flat Beat" video (58.3 Hz on lowest Bb at 32') | Lowest C is C3 at 8' (130.81 Hz/V), MIDI note 48 |
| VCO core: CV via `SCALE` resistors (8 × 100 kΩ, 0.1%) into transistor pair; C2 = 6200 pF, C11 = 3000 pF | D (1) | `freq = (volts + offset) * Hz_per_volt(scale)`; stops below the offset |
| VCO trickle: R203 (220 kΩ) / R201 (1 kΩ) off +15 V into R202 (10 MΩ); VCO 2: R205 / R204 / R206 | D (1) | 6.79 nA into the integrator whatever the CV (`ms20_voff`) |
| Pitch adjustment (7-2): "high" screw VR1 / VR6 (exponential pair bias: gain), "low" screw VR2 / VR5 (TL081 offset null), tuned at 8' to ±2 cents; other footages ±10 cents | D adjustment, (1) | Offset null cancels the trickle at 8' exactly; at other footages it remains: VCO 1 at 32' +4.0 mV (lowest C ~7 cents sharp), at 4' -0.7 mV; VCO 2 at 16' +2.6 mV, at 2' -2.0 mV |
| `VCO 1+2 CV IN`, `VCO 2 CV IN` (linear response, switching jacks) | D spec, (1) | Plugging in disconnects keyboard CV (`VCO 2 CV IN` affects VCO 2 only) |
| FM inputs: R43 / R44 (100 kΩ) into IC4 (R39 = 110 kΩ), R40 (5.11 kΩ) / R38 (100 Ω) to expo pair base | D (1) | 21.1 mV/V = 1.178 oct/V at knob 10 (17.92 mV/oct at 300 K) |
| `MASTER TUNE`: VR11 (±15 V) through R36 (10 MΩ) into IC4 | D (1) | ±0.177 oct (±212 cents; spec sheet claims ±100 cents) |
| `VCO 2 PITCH`: VR2 (±15 V) through R55 (75 kΩ) into R47 (100 Ω) | D (1) | ±1.115 oct (spec sheet claims ±1 oct) |
| `TOTAL`: buffer IC6 behind R71 (10 kΩ) / R72 (100 kΩ), normalled to MG triangle | D (1) | Gain × 0.909, routed to all three `MG / T.EXT` knobs |
| `FREQ`: normalled to EG1 through R1 (1 kΩ) / R2 (2 kΩ) to ground | D (2) | -5 V at rest, 0 V at peak (raising `EG1 / EXT` makes notes climb into pitch) |
| `PORTAMENTO`: VR10 (2 MΩ A) + R30 (680 Ω) into C6 (0.22 µF), gated by FET Q23 (on while key held) | D (1) | RC slew on linear Hz/V CV (up to 0.44 s); freezes when key is released |
| Power-on: no key down puts the ladder at 0 V; C6 starts discharged | D (1) | `KBD CV OUT` is 0 V until the first key: the VCOs stand at 8' and creep on the trickle elsewhere (VCO 1 at 32': 0.13 Hz) |
| Modulation intensity pots: 100 kΩ A, wiper loaded by 100 kΩ | D (1) | Loaded taper: `a / (1 + a * (1 - a))` |

## Oscillators & Mixer

| Circuit block | Source | Model in `ms20.h` |
| --- | --- | --- |
| Sawtooth (7.5 V p-p) | D block diagram, test points 10 & 11 | ±3.75 V rising ramp |
| VCO 1 pulse: comparator IC2 vs. VR9 (1 MΩ B under R10 = 300 kΩ, R11 = 100 kΩ across); ±13.5 V through R2 (100 kΩ) / R1 (6.8 kΩ) | D (1) | ±0.86 V; 50% duty at `PW` 0, 3.5% at `PW` 10 |
| VCO 1 triangle: sawtooth through D2 / D3 into IC2, R6 (10 kΩ) / R7 (100 kΩ) to +15 V | D (1) | Lookup table of `|saw|` minus diode drop into 100 kΩ; one peak flattened, 3 V p-p |
| VCO 1 noise waveform | D (1), (2) | Same signal as `WHITE` noise jack (5 V p-p) |
| VCO 2 square / narrow pulse: comparator IC6, threshold 0 V or R70 (100 kΩ) / R69 (22 kΩ) = 2.7 V | D (1) | 50% duty (square) or 14% duty (pulse) |
| `RING`: CD4011 XOR of VCO 1 pulse (independent of VCO 1 `WAVE FORM`) and VCO 2 square; R65 (47 kΩ), R67 (4.7 kΩ), R68 (100 kΩ) to -15 V | D (1) | +0.69 V / -0.62 V |
| Mixer level pots: 100 kΩ A into 100 kΩ; sawtooth through R4 (100 kΩ), other waves from low-Z sources | D (1) | Per-waveform levels derived from source impedance |
| VCO 2 sawtooth level (schematic omits series resistor, which would make it 9 dB hotter than VCO 1) | **R**: GAK "Da Funk" video (two sawtooths at equal mixer knobs have fundamentals within 1 dB) | Matched to VCO 1 (100 kΩ series) |
| Mixer IC8: 100 kΩ inverting summer; `EXT SIGNAL IN` is third input | D (1) | Sum clipped at ±13.5 V |

## Filters (Dual KORG35)

| Circuit block | Source | Model in `ms20.h` |
| --- | --- | --- |
| Input attenuators: HP uses R100 (20 kΩ) / R104 (47 Ω); LP uses R108 (2.2 kΩ) / R109 (47 Ω) | D (1) | Attenuation 1/427 (HP) and 1/47.8 (LP) — a few mV at the KORG35 input |
| Core topology: two transistors as voltage-controlled resistors, C = 3300 pF (feedback) and 1000 pF (ground), buffer, amp | D (1), S figs. 1 & 3 | Trapezoidal-integrated Sallen-Key solved per sample; self-oscillation frequency defines cutoff |
| High-pass mode: same core, signal injected at ground side of 1000 pF cap | D (1), S sec. 7 | 6 dB/octave roll-off |
| Feedback amp: gain `1 + 270 kΩ / 4.7 kΩ` (58.4), antiparallel 1S1555 diodes across 270 kΩ | D (1), S sec. 5 | `vB = Rg * (vd / Rf + 2 * Is * sinh(vd / (n * VT)))`, solved with 2 Newton iterations. Diode modeled as 1N4148: `Is = 2.52 nA`, `n = 1.752` (**A**) |
| `PEAK`: 10 kΩ B pot, 2.2 kΩ from top to wiper, feeding 5.6 kΩ + 220 Ω | D (1), S fig. 1 | Loop gain 0 to 2.21, steep initial taper |
| Internal KORG35 R2/R1 ratio (sets `PEAK` oscillation threshold: 1 → 7.3, 3 → barely oscillates) | **R**: Marc Doty MS-20 mini demo (resonant at 7.5–8, oscillating by 8.7–9) and Da Funk (both `PEAK`s at 8, no self-oscillation) | 1.5 (self-oscillates around 8.7) |
| Signal-dependent transistor conductance (causes asymmetric resonance) | S sec. 4 | Conductance scaled by `exp(-v / VT)` where `v` is mean voltage across each transistor; scale factor 1 from device equation (**not measured on hardware**) |
| Cutoff summing: `CUTOFF` (±15 V via 470 kΩ), `EG2 / EXT` and `MG / T.EXT` (via 100 kΩ each), summed on R95 (10 kΩ), ×22.3 (R94 = 100 kΩ, R97 = 4.7 kΩ) | D (1) | 1 V at an intensity knob set to 10 equals 0.3133 of `CUTOFF` half-range |
| Cutoff octaves/volt | **R**: Vintage MS-20 LP self-oscillation sweep, 13 Hz to 15.3 kHz (Kick.S); D adjustment: 500 Hz at knob 5 | ±5.27 oct around 500 Hz with top-end compression `f / (1 + f / 75 kHz)` (~1.65 oct/V; spec sheet says 2 oct/V) |
| Output coupling caps C14, C32 (33 µF) | D (1) | 2.7 Hz and 1.4 Hz DC-blocking high-pass filters |

**Omitted from filter model:** C27 / C30 (1000 pF across 5.6 kΩ, phase lead above 28 kHz), op-amp finite bandwidth, thermal drift, and the later KLM-307 (LM13600) filter board.

## Envelopes & VCA

| Circuit block | Source | Model in `ms20.h` |
| --- | --- | --- |
| Trigger inputs: R193 (220 kΩ pull-up), D31, D27, R187 (100 kΩ) / R186 (33 kΩ) into Q22 | D (1) | Active when input < 2.2 V; unplugged = off. `TRIG OUT` is +5 V idle, 0 V while key held |
| EG1: C38 (3.3 µF), +10 V at rest (R159 = 1 kΩ / R160 = 2 kΩ), `ATTACK` VR28 and `RELEASE` VR29 (2 MΩ A), CD4007 switches | D (1) | Simple RC charge/discharge up to 6.6 s; 400 Ω switch on-resistance (**A**) |
| EG1 outputs: VCO normal (-5 to 0 V), `OUT` via R19 (1 kΩ) / R18 (2 kΩ) to +15 V (0 to +5 V), `REV OUT` (+5 to 0 V), mod VCA normal (0 to +5 V) | D (2), panel silkscreen (**R**: MS-20 mini video; spec sheet erroneously lists `OUT` as -5 to 0 V) | Follows schematic and panel silkscreen |
| `DELAY`: VR27 (2 MΩ A), C39 (6.8 µF) into CMOS threshold | D (1) | `0.69 * RC`, up to 9.4 s at knob 10 |
| EG2: C40 (6.8 µF); `ATTACK` VR33 (2 MΩ A) from R180 (470 Ω) / R179 (680 Ω) = 8.87 V up to 5.07 V threshold (R181 = 43 kΩ, R176 = 150 kΩ, Q21); `DECAY` VR32 (1 MΩ A) + R178 (1 kΩ) to sustain; `RELEASE` (1 MΩ A) | D (1) | Same RC stages and thresholds |
| `SUSTAIN`: VR31 (10 kΩ B) with R168 (2.7 kΩ) across it, under R169 (4.3 kΩ) | D (1) (scan looks like "43 K"; 4.3 kΩ produces the specified 0–5 V range) | 0 to 4.96 V |
| **EG2 to filters and `REV OUT`:** IC20 difference amp (R177, R173, R171, R172 = 100 kΩ) subtracting `SUSTAIN` wiper | D (1) | Filters receive `EG2 - SUSTAIN`; `REV OUT` is `SUSTAIN - EG2`. With `SUSTAIN` raised, `CUTOFF` sets the held frequency and the filter sits below it before/after the note |
| `HOLD`: VR34 (2 MΩ A), C42 (10 µF), CMOS threshold; sits after `TRIG IN` and feeds EG2 only | D (1) | Extends EG2 gate by `0.69 * RC`, up to 13.9 s at knob 10 |
| VCA: R123 (6.2 kΩ) / R121 (220 Ω), series transistor Q19 (2SC945, unbiased collector), C35 (10 µF), IC11 with R118 (180 kΩ) and C34 (100 pF) | D (1) | `I = bR * Ib * (1 - exp(-v / VT))` into 180 kΩ (asymmetric except at small signals); 8.8 kHz low-pass roll-off. `bR = 5`, `Is = 2e-14 A` (**A**) |
| VCA control: EG2 via R125 (100 kΩ), R122 (1 MΩ) to ground, R124 (1 MΩ); `INITIAL GAIN` via diode D22 | D (1) | Closed below ~0.4 V EG2; `INITIAL GAIN` takes `max(INITIAL GAIN, EG2)` |
| Output stage: C33 (1 µF), R119 (1 kΩ), `VOLUME`; headphone amp R41 (27 kΩ) / R42 (4.7 kΩ), inverting | D (1), (2) | 14.5 Hz high-pass; `PHONES = -5.74 * SIGNAL OUT` (see feedback note below) |
| Audio-taper ("A") pot curve | **A**: standard 15% midpoint. **R**: gives 0.17 s EG2 decay at 1.6, matching Flat Beat amplitude within 2 dB from 20–250 ms (3 dB at 300 ms) | Exponential taper |

## MG, Noise, Track & Hold, Modulation VCA

| Circuit block | Source | Model in `ms20.h` |
| --- | --- | --- |
| MG core: integrator C22 (0.1 µF), Schmitt trigger R149 (20 kΩ) / R150 (100 kΩ); `FREQUENCY` VR25 (10 kΩ B) between R147 (2.2 kΩ) and R148 (48 Ω); `WAVE FORM` VR26 (1 MΩ B) via R154 (8.2 kΩ), switched by Q17 / Q18 | D (1) | ±2.7 V triangle/ramp; 0.096 to 20.2 Hz linear with knob; waveform does not affect rate |
| MG rectangle: R145 (4.3 kΩ) / R146 (2.7 kΩ), D14 | D (1) | 0 V / +5.2 V, high while triangle is falling |
| White noise (5 V p-p); "pink" noise: R35 (6.8 kΩ) into IC4 with R28 (220 kΩ), C2 (0.022 µF) | D (2) | "Pink" is a 1-pole 6 dB/oct low-pass at 33 Hz (not true 3 dB/oct pink) |
| Sample & Hold: FET F1 between IC2 and C1 (0.1 µF), conducts when `CLOCK > 1.36 V` (R6 = 10 kΩ / R9 = 1 kΩ); `CLOCK` pulled up by R38 (220 kΩ) | D (2); confirmed on hardware (Arturia forum) | Track-and-hold: tracks input when clock is high or unplugged, holds when low |
| Modulation VCA: IC3 (× -0.75), optocoupler, IC3; LED driven by TR1, R26 (1 kΩ), R27 (33 kΩ); `CONTROL INPUT` normalled to EG1 (0 to +5 V) | D (2) | Driven by EG1 unless patched. Photocell law (`current^0.75`) and rise/fall times (3 ms / 40 ms): **A** |
| Mod wheel (-5 to +5 V); momentary switch (contact to ground) | D (2), spec | Switch pulls a `TRIG IN` to ground; outputs no voltage on its own |

## External Signal Processor (ESP)

| Circuit block | Source | Model in `ms20.h` |
| --- | --- | --- |
| Input amp: VR7 (1 MΩ B) with R53 (1 MΩ) across, over R51 (2.2 kΩ), followed by ×22; `OUT` via R47 (22 kΩ) / R46 (2.7 kΩ) | D (2) | Up to 10,000× gain (mic preamp); internal patch signals clip it almost immediately |
| `LOW CUT`: 2-pole, 0.033 µF, 2 kΩ + 100 kΩ C; `HIGH CUT`: 4-pole, 0.015 µF | D (2) | 47 Hz – 2.4 kHz (`LOW CUT`); 104 Hz – 5.3 kHz (`HIGH CUT`) |
| Envelope follower: D4, R48 (1 kΩ), C1 (1 µF), R3 (22 kΩ) off preamp; `ENV OUT` via R11 / R35 | D (2) | 1 ms attack, 18 ms release, 0 to +6 V |
| `TRIG OUT`: comparator vs. VR3 (R20 = 680 Ω, R1 = 820 Ω), hysteresis R19 / R21 | D (2) | +5 V idle, 0 V when signal exceeds threshold |
| F-to-V converter: fixed-width pulse per cycle, 2-pole low-pass (0.056 µF, 10 kΩ + `LOW CUT` pot); `CV ADJUST` VR4 (10 kΩ A) over R38 (1 kΩ) | D (2) | Linear Hz/V output (can pitch-track VCOs via `CV IN`). Pulse width 1.5 ms: **A** |

Because the FM-1 has no physical audio input, `ESP SIGNAL IN` is fed by patching from another internal jack.

## Patch panel wiring

A cable connects any two jacks regardless of direction. Each output is modeled as a Thévenin voltage source behind its output resistor; each input (once a plug opens its switching contact and breaks its normal) is modeled as its internal bias voltage and resistance. Every connected group of jacks resolves to `sum(V / R) / sum(1 / R)`.

Because the network is solved directly from these impedances, no special cases are needed—dummy plugs, the momentary switch, output loading, input-to-input connections, and output-to-output summing all fall out naturally:

| Output jack | Output impedance | Input jack | Tip sees (when plugged) |
| --- | --- | --- | --- |
| `KBD CV OUT` | 100 Ω (R46) | `TOTAL` | 100 kΩ to ground (R72) |
| `KBD TRIG OUT` | 880 Ω (R82 = 1.3 kΩ, R81 = 2.7 kΩ) | `FREQ` | 100 kΩ to ground (`EG1 / EXT`) |
| `MG OUT` (triangle) | 1 kΩ (R144) | `VCO 1+2 CV IN`, `VCO 2 CV IN` | SCALE ladder (~400 kΩ to ground) + R207 (22 MΩ to +15 V): 0.27 V via 393 kΩ |
| `MG OUT` (rectangle) | 1.66 kΩ (R145 = 4.3 kΩ, R146 = 2.7 kΩ) | `EXT SIGNAL IN` | 50 kΩ (R90 = 100 kΩ to ground, R75 = 100 kΩ to mixer) |
| `EG 1 OUT` | 667 Ω (R19 = 1 kΩ, R18 = 2 kΩ) | `CUTOFF FREQ` (HP & LP) | 100 kΩ to ground (`EG2 / EXT`) |
| `EG 1 REV OUT` | 1.35 kΩ (R164, R165) | `INITIAL GAIN` | 1 MΩ to ground (R122) |
| `EG 2 REV OUT` | 1 kΩ (R170) | `TRIG IN`, `EG 1 TRIG IN` | 220 kΩ to +15 V (R193, R158): off |
| `S&H OUT` | 1 kΩ (R7) | `S&H IN` | 100 kΩ to ground (R10) |
| `MOD VCA OUT` | 470 Ω (R23) | `S&H CLOCK` | 220 kΩ up, 100 kΩ down (R38, R13): 4.7 V via 69 kΩ |
| `WHITE`, `PINK` | 1 kΩ (R37, R30) | `VCA IN` | 100 kΩ (R17) |
| Wheel | ~2.5 kΩ (10 kΩ pot) | `CONTROL INPUT` | 110 kΩ to ground (R22, R25) |
| Momentary switch | Contact to ground | `ESP SIGNAL IN` | ~1 MΩ (R51, `SIGNAL LEVEL`) |
| `SIGNAL OUT`, `PHONES` | ~2 kΩ, 220 Ω | | |
| ESP outputs | 1.35–2.4 kΩ (output dividers) | | |

Examples that emerge directly from this model (matching the real instrument):
- Dummy plug in `TRIG IN` disconnects keyboard triggering.
- Dummy plug in `CONTROL INPUT` closes the modulation VCA.
- Dummy plug in `VCO 2 CV IN` leaves VCO 2 idling at ~35 Hz (0.27 V pull-up).
- Patching `S&H CLOCK` to `CONTROL INPUT` partially opens the modulation VCA (2.9 V).
- Patching two outputs together simply shorts them through their output resistors with nothing reading the node.
- Patching the wheel into a VCO `CV IN` drops 0.6% due to loading.

### Feedback patching polarity

Per the schematic, the audio path has two inversions before `SIGNAL OUT` (mixer IC8 and VCA IC11) and a third inversion through the headphone amp (`PHONES = -5.74 * SIGNAL OUT`):

- **`PHONES -> EXT SIGNAL IN`** has 3 inversions (negative feedback at low/mid frequencies), which cancels bass and drops level until filter phase shift flips it to positive feedback near cutoff (thinning and whistling rather than fattening).
- **`SIGNAL OUT -> EXT SIGNAL IN`** skips the headphone amp (2 inversions = positive feedback, at unity gain).
- **Classic MS-20 overdrive** on hardware (e.g., Patchwerks and Switched On Austin MS-20 Mini demos) avoids direct `PHONES -> EXT SIGNAL IN` cancellation by either routing **`SIGNAL OUT -> ESP SIGNAL IN -> ESP BPF OUT -> EXT SIGNAL IN`** (positive feedback with `SIGNAL LEVEL` and `LOW CUT`/`HIGH CUT` shaping) or **`PHONES -> ESP SIGNAL IN -> ESP OUT -> TOTAL`** (audio-rate filter cutoff FM).

## Not modeled

- Oscillator/filter thermal drift and warm-up
- Component tolerances (both VCOs track identically)
- Mains hum and realistic noise floor (only a tiny noise floor is injected so filters can self-oscillate)
- 7 ms mechanical key-contact trigger delay
- Op-amp slew rate and finite bandwidth
- Later KLM-307 (LM13600) filter board
