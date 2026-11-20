# The MS-20's circuit, as `firmware/src/ms20.h` has it

Where every number in the engine comes from. Three kinds of source, marked in the tables:

- **D** – Korg's MS-20 service manual: circuit diagrams (1) KLM-127 and (2) KLM-128 / KLM-129, the block diagram's
  check points, the specifications, the adjustment procedure. This is the first board set, with two KORG35 filters.
  (archive.org: `korg_MS-20_SERVICE_MANUAL`, `JL11276`. Korg's drawings are not in this repository.)
- **S** – T. E. Stinchcombe, *A Study of the Korg MS10 & MS20 Filters* (2006): the KORG35's inside and how it works.
- **R** – a recording of an instrument, where the diagram cannot say (the inside of a chip, a pot's curve) or where
  two readings of the diagram had to be told apart. Each is named.
- **A** – assumed: a typical part's figure, said so.

Voltages are the MS-20's own; the engine works in volts throughout. `tests/ms20_test.c` checks most rows.

## Pitch

| What | Source | In the engine |
| --- | --- | --- |
| Keyboard: a chain of 1 % resistors read from its top end | D (1) | the highest key held counts; one trigger while any key is down |
| KBD CV OUT 0 .. +8 V, "exponential"; C-3 "exactly half" C-4 | D spec, adjustment | 1 V at the lowest C, 8 V at the highest: volts = 2^((note - 48) / 12) |
| Which C is which | R: GAK's Flat Beat video, a 58.3 Hz note at 32' played on the first octave's B flat | the lowest C is C3 at 8' (130.81 Hz a volt), MIDI note 48 |
| VCO: CV through SCALE's resistors (100 k x 8, 0.1 %) into a transistor pair, C2 6200 p / C11 3000 p | D (1) | frequency = volts x Hz-per-volt of the scale; 0 V and below: stopped |
| VCO 1 + 2 CV IN, VCO 2 CV IN: "linear response", switched jacks | D spec, (1) | a plug replaces the keyboard's voltage (VCO 2's: for VCO 2 alone) |
| FM: R43 / R44 100 k into IC4 (R39 110 k), R40 5.11 k / R38 100 onto the pair's base | D (1) | 21.1 mV a volt = 1.178 octaves a volt at knob 10 (17.92 mV an octave, 300 K) |
| MASTER TUNE: VR11 +-15 V through R36 10 M into the same amplifier | D (1) | +-0.177 octave (the spec sheet says +-100 cents) |
| VCO 2 PITCH: VR2 +-15 V through R55 75 k onto R47 100 | D (1) | +-1.115 octave (spec: +-1) |
| TOTAL: buffer IC6 behind R71 10 k / R72 100 k, wired to the MG's triangle | D (1) | x 0.909, to the three MG / T.EXT knobs |
| FREQ: wired to EG1 through R1 1 k / R2 2 k to ground | D (2) | -5 V at rest, 0 V at the top: with EG1 / EXT up the note climbs to its pitch |
| PORTAMENTO: VR10 2 M A + R30 680 into C6 0.22 uF, behind FET Q23 (on while a key is down) | D (1) | an RC on the voltage (so on the frequency), up to 0.44 s; it stops where it is when the key is let go |
| Intensity pots: 100 k A, wiper into 100 k | D (1) | the load bends the taper: a / (1 + a (1 - a)) |

## Oscillators and mixer

| What | Source | In the engine |
| --- | --- | --- |
| Sawtooth 7.5 V p-p | D block diagram, check points 10, 11 | +-3.75 V, rising |
| VCO 1 pulse: comparator IC2 against VR9 (1 M B under R10 300 k, R11 100 k across), +-13.5 V through R2 100 k / R1 6.8 k | D (1) | +-0.86 V; half the cycle at PW 0, 3.5 % at 10 |
| VCO 1 triangle: the sawtooth through D2 / D3 into IC2 (the diodes in the signal's way), R6 10 k / R7 100 k to +15 V | D (1) | \|saw\| less a diode's drop into 100 k (a table): one tip rounded flat, 3 V p-p |
| VCO 1 noise position: the white noise jack's signal | D (1), (2) | 5 V p-p |
| VCO 2 square / pulse: comparator IC6, threshold 0 V or R70 100 k / R69 22 k (2.7 V) | D (1) | half the cycle, or 14 % |
| RING: a 4011 as exclusive-or of VCO 1's pulse (whatever its WAVE FORM) and VCO 2's square; R65 47 k, R67 4.7 k, R68 100 k to -15 V | D (1) | +0.69 / -0.62 V |
| Level pots 100 k A into 100 k; sawtooth through R4 100 k, the others from a few k | D (1) | each waveform's level by its source resistance |
| VCO 2's sawtooth: the diagram shows no series resistor (it would be 9 dB louder than VCO 1's) | **R**: GAK's Da Funk video, two sawtooths with both level knobs alike: fundamentals within 1 dB | as VCO 1's (through 100 k) |
| Mixer IC8: 100 k all round, inverting; EXT SIGNAL IN its third input | D (1) | sum, clipped at +-13.5 V |

## Filters (KORG35, twice)

| What | Source | In the engine |
| --- | --- | --- |
| Into the high-pass: R100 20 k / R104 47; into the low-pass: R108 2.2 k / R109 47 | D (1) | 1 / 427 and 1 / 47.8: a few millivolts at the chip |
| Topology: two transistors as resistors, C 3300 p (to the feedback) and 1000 p (to ground), buffer, amplifier | D (1), S fig. 1, 3 | Sallen-Key, solved before each sample (trapezoidal); self-oscillation frequency = "the cutoff" |
| High-pass: the same, the signal entering at the 1000 p's ground end | D (1), S section 7 | 6 dB an octave |
| Amplifier: 1 + 270 k / 4.7 k (58.4), two diodes (1S1555) across the 270 k | D (1), S section 5 | vB = Rg (vd / Rf + 2 Is sinh(vd / n VT)): Newton, 2 steps. Diode as a 1N4148: Is 2.52 nA, n 1.752 (**A**) |
| PEAK: 10 k B, 2.2 k from top to wiper, into 5.6 k + 220 | D (1), S fig. 1 | loop gain 0 .. 2.21, steep at first |
| R2 / R1 inside the chip (sets where on PEAK it sings: 1 would be 7.3, 3 would be never quite) | **R**: Marc Doty's MS-20 mini filter video (PEAK near 7.5 - 8: resonant, not singing; near 8.7 - 9: singing) and the Da Funk patch (both PEAKs at 8, no whistle) | 1.5: it starts at about 8.7 |
| The signal moves the transistors' resistance (lopsided resonance) | S section 4 | conductance x exp(-v / VT), v the mean voltage across each; strength 1 from the device equation, **not measured** |
| CUTOFF: +-15 V through 470 k; EG2 / EXT and MG / T.EXT pots through 100 k each; summed on R95 10 k, x 22.3 (R94 100 k, R97 4.7 k) | D (1) | a volt on an intensity knob at 10 is 0.3133 of CUTOFF's half range |
| Octaves a volt of the chip | **R**: a vintage MS-20's low-pass singing from stop to stop, 13 Hz .. 15.3 kHz (Kick.S); D adjustment: 500 Hz at 5 | +-5.27 octaves about 500 Hz, squeezed at the top (f / (1 + f / 75 kHz)); so 1.65 octaves a volt (Korg's sheet: "2 oct / V") |
| C14, C32 33 uF after each amplifier | D (1) | 2.7 Hz and 1.4 Hz high-passes |

Not in the engine: C27 / C30 1000 p across the 5.6 k (a lead above 28 kHz), the amplifier's own bandwidth, the chip's
drift with temperature, and the later MS-20s' filter board (KLM-307, LM13600s) altogether.

## Envelopes and VCA

| What | Source | In the engine |
| --- | --- | --- |
| Trigger inputs: R193 220 k up, D31, D27, R187 100 k / R186 33 k into Q22 | D (1) | on while the input is under 2.2 V; open = off. TRIG OUT: +5 V, ground while a key is down |
| EG1: C38 3.3 uF, +10 V at rest (R159 1 k / R160 2 k), ATTACK VR28 and RELEASE VR29 2 M A, 4007 switches | D (1) | plain RCs both ways, up to 6.6 s; 400 ohms for a switch (**A**) |
| EG1's outputs: to the VCOs -5 .. 0 V; OUT (R19 1 k, R18 2 k to +15 V) 0 .. +5 V; REV OUT +5 .. 0 V; to the modulation VCA 0 .. +5 V | D (2); the panel's legend (**R**: read off an MS-20 mini). The spec sheet's text has OUT as -5 .. 0 V | as the diagram and the panel |
| DELAY: VR27 2 M A, C39 6.8 uF, to a CMOS threshold | D (1) | 0.69 RC: 9.4 s at 10 |
| EG2: C40 6.8 uF; ATTACK VR33 2 M A from R180 470 / R179 680 (8.87 V) until 5.07 V (R181 43 k, R176 150 k, Q21); DECAY VR32 1 M A + R178 1 k to SUSTAIN; RELEASE 1 M A | D (1) | the same |
| SUSTAIN: VR31 10 k B with R168 2.7 k across it, under R169 4.3 k | D (1) (the scan reads "43 K"; 4.3 k is what gives the specified 0 .. 5 V) | 0 .. 4.96 V |
| **EG2 to the filters and REV OUT: IC20, a difference amplifier (R177, R173, R171, R172 100 k) against SUSTAIN's wiper** | D (1) | the filters get EG2 - SUSTAIN; REV OUT is SUSTAIN - EG2. With SUSTAIN up, CUTOFF is the held note's cutoff, and the filter is below it before and after |
| HOLD: VR34 2 M A, C42 10 uF, CMOS threshold; after TRIG IN, before EG2 only | D (1) | EG2's trigger lasts 0.69 RC longer: 13.9 s at 10 |
| VCA: R123 6.2 k / R121 220, Q19 (2SC945) in series with no supply, C35 10 uF, IC11 with R118 180 k and C34 100 p | D (1) | I = bR Ib (1 - exp(-v / VT)) into 180 k: lopsided for anything but the smallest signal; 8.8 kHz roll-off. bR 5, Is 2e-14 A (**A**) |
| Its base: EG2 through R125 100 k, R122 1 M to ground, R124 1 M; INITIAL GAIN through D22 | D (1) | shut below about 0.4 V of EG2; INITIAL GAIN is whichever is higher, not a sum |
| C33 1 uF, R119 1 k, VOLUME; the headphone amplifier R41 27 k / R42 4.7 k, inverting | D (1), (2) | 14.5 Hz high-pass; PHONES = -5.74 x SIGNAL OUT (the feedback patch's loop has three inversions) |
| "A" pots' curve | **A**: 15 % at the middle, the usual. **R**: with it, EG2's DECAY at 1.6 is 0.17 s, and the Flat Beat notes' amplitude follows the recording within 2 dB from 20 to 250 ms (3 dB at 300) | exponential taper |

## Modulation generator, noise, sample & hold, modulation VCA

| What | Source | In the engine |
| --- | --- | --- |
| MG: integrator C22 0.1 uF, Schmitt trigger R149 20 k / R150 100 k; FREQUENCY VR25 10 k B between R147 2.2 k and R148 48; WAVE FORM VR26 1 M B through R154 8.2 k, switched by Q17 / Q18 | D (1) | +-2.7 V; 0.096 .. 20.2 Hz, in proportion to the knob; the shape does not move the rate |
| Rectangle: R145 4.3 k / R146 2.7 k, D14 | D (1) | 0 / +5.2 V, high while the triangle falls |
| White noise 5 V p-p; "pink": R35 6.8 k into IC4 with R28 220 k, C2 0.022 uF | D (2) | "pink" is 6 dB an octave from 33 Hz, not 3 |
| Sample & hold: F1 between IC2 and C1 0.1 uF, on while CLOCK > 1.36 V (R6 10 k / R9 1 k); CLOCK pulled up by R38 220 k | D (2); the same found on hardware (Arturia forum) | follows while the clock is high or unplugged, holds while it is low |
| Modulation VCA: IC3 x -0.75, a photocoupler, IC3; LED by TR1, R26 1 k, R27 33 k; CONTROL wired to EG1 (0 .. +5 V) | D (2) | opened by EG1 unless something is plugged in. The cell's law (current^0.75) and times (3 ms on, 40 ms off): **A** |
| Wheel -5 .. +5 V; momentary switch: a contact to ground | D (2), spec | the switch triggers a TRIG IN; it is no voltage |

## External signal processor

| What | Source | In the engine |
| --- | --- | --- |
| Amplifier: VR7 1 M B with R53 1 M across, over R51 2.2 k; then x 22; OUT through R47 22 k / R46 2.7 k | D (2) | up to 10000 x: for a microphone. A patch-panel signal clips it almost at once |
| LOW CUT: 2 poles, 0.033 uF, 2 k + 100 k C; HIGH CUT: 4 poles, 0.015 uF | D (2) | 47 Hz .. 2.4 kHz; 104 Hz .. 5.3 kHz |
| Envelope follower: D4, R48 1 k, C1 1 uF, R3 22 k, off the amplifier; ENV OUT through R11 / R35 | D (2) | 1 ms up, 18 ms down, 0 .. +6 V |
| TRIG OUT: comparator against VR3 (R20 680, R1 820), hysteresis R19 / R21 | D (2) | +5 V, ground above the threshold |
| F-V: a fixed pulse a cycle, smoothed by 2 poles (0.056 uF, 10 k + LOW CUT's pot); CV ADJUST VR4 10 k A over R38 1 k | D (2) | volts proportional to hertz (it plays a VCO through its CV IN). The pulse's width, 1.5 ms: **A** |

The FM-1 has no audio input: the ESP's SIGNAL IN is a cable from another jack.

## The patch panel's wiring

A cable joins two jacks, of any kind. Each output is its voltage behind the resistance it leaves the board through;
each input, once a plug has opened its switch (breaking its normal), is what its tip sees inside. Every set of jacks
joined together settles at sum(V / R) / sum(1 / R). Nothing else about the patch panel is special-cased: a dummy plug,
the momentary switch, two inputs or two outputs joined, and an output's small loss into the input it drives all follow.

| Output | Behind | | Input | Its tip sees |
| --- | --- | --- | --- | --- |
| KBD CV OUT | 100 Ω (R46) | | TOTAL | 100 k to ground (R72) |
| KBD TRIG OUT | 880 Ω (R82 1.3 k, R81 2.7 k) | | FREQ | 100 k to ground (EG1 / EXT) |
| MG OUT, triangle | 1 k (R144) | | VCO 1+2 CV IN, VCO 2 CV IN | the SCALE ladder, ~400 k to ground, and R207 22 M to +15 V: 0.27 V through 393 k |
| MG OUT, rectangle | 1.66 k (R145 4.3 k, R146 2.7 k) | | EXT SIGNAL IN | 50 k (R90 100 k to ground, R75 100 k to the mixer) |
| EG 1 OUT | 667 Ω (R19 1 k, R18 2 k) | | CUTOFF FREQ (both) | 100 k to ground (EG2 / EXT) |
| EG 1 REV OUT | 1.35 k (R164, R165) | | INITIAL GAIN | 1 M to ground (R122) |
| EG 2 REV OUT | 1 k (R170) | | TRIG IN, EG 1 TRIG IN | 220 k to +15 V (R193, R158): off |
| S&H OUT | 1 k (R7) | | S&H IN | 100 k to ground (R10) |
| modulation VCA OUT | 470 Ω (R23) | | S&H CLOCK | 220 k up, 100 k down (R38, R13): 4.7 V through 69 k |
| WHITE, PINK | 1 k (R37, R30) | | VCA IN | 100 k (R17) |
| wheel | ~2.5 k (its 10 k pot) | | CONTROL INPUT | 110 k to ground (R22, R25) |
| momentary switch | a contact to ground | | ESP SIGNAL IN | ~1 M (R51, SIGNAL LEVEL) |
| SIGNAL OUT, PHONES | ~2 k, 220 Ω | | | |
| ESP outputs | 1.35 .. 2.4 k (their dividers) | | | |

So, as on the instrument: a dummy plug in TRIG IN stops the keys triggering, in CONTROL INPUT shuts the modulation VCA,
in VCO 2 CV IN leaves VCO 2 crawling at about 35 Hz (0.27 V); S&H CLOCK joined to CONTROL INPUT opens the VCA part way
(2.9 V); two outputs joined meet where nothing reads them; the wheel into a VCO's CV IN loses 0.6 %.

## What is not here

Drift and warm-up; the tolerance of any one instrument's parts (a real MS-20's two VCOs do not track each other
perfectly; these do); hum and the true noise floor (a little is added so the filters have something to start
singing from); the key contacts' 7 ms trigger delay; op-amp slew and bandwidth; the later filter board.
