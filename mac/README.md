# FLAT-20 Panel

A Mac window showing the FM-1's MS-20 as a panel: every knob where the FM-1 has it, the patch cables between their
jacks, the patch panel's diagram, the key that sounds, the wheel, the momentary switch and the lamps. And you can patch
it with the mouse:

- click a jack, then another: a cable between them. Any two jacks: an output and an input as usual, or two inputs, or
  two outputs, which the FM-1 wires as the panel would be wired (docs/MS20-CIRCUIT.md, "The patch panel's wiring");
- the first click on a jack that has a cable pulls that cable out, and the second click plugs the new one in;
- the second click on a jack that has a cable pulls that one out first;
- click a cable: it comes out at both ends;
- Option-click a jack: a dummy plug, a cable to nothing, which breaks the jack's internal connection and leaves the
  input at its own pull-up or pull-down (a dummy in TRIG IN: the keys stop triggering). Option-click a plugged jack:
  its cable comes out;
- the same jack twice, a click on the bare panel, or Esc: the loose cable is put down (one pulled by the first click
  stays out). One plug a jack, as on the MS-20.

The cables are the only thing the app sends; the knobs stay the FM-1's. Patching needs FLAT-20 firmware that says it
takes cables (0.2's later builds); with older firmware the panel only shows.

```sh
mac/build.sh                         # -> mac/build/FLAT-20 Panel.app (signed for this Mac only)
open "mac/build/FLAT-20 Panel.app"
```

Plug the FM-1 in over USB (with FLAT-20 0.2 or later on it). The panel fills in within a second, and dims when nothing
has been heard for 2.5 s. A keyboard on the FM-1's MIDI IN, or passed through the Mac, changes nothing: the FM-1
reports what it is doing, whoever is playing it.

## How it knows

The firmware sends its state as SysEx over USB MIDI (`firmware/src/ms20_link.h`): a STATE message (all 36 knobs and
switches, the 8 cables, the preset, HOLD, the octave) when anything changes and once a second, and a LIVE message
(the key, the wheel, the switch, the lamps) when that changes. The app listens to every MIDI source and takes what
carries FLAT-20's header. Firmware built with other lists of knobs or jacks says so on screen instead of being drawn
wrong. Patching sends a CABLES message with the whole patch panel to the destination beside the FM-1's source; the
FM-1 checks it (every jack real, one cable an input), applies it as if patched on its own panel, and its next STATE
shows it (5 ms, measured).

## Without an FM-1

```sh
python3 tools/fake_fm1.py            # the firmware runs on the Mac and sends through a virtual port: a tour of the presets
python3 tools/fake_fm1.py --loop
cd mac && swift run panel-render out.png LOG [MS]     # the panel as a PNG, from build/host/dinghy's output
FLAT20_SNAPSHOT=/tmp/p "mac/build/FLAT-20 Panel.app/Contents/MacOS/FLAT-20 Panel"   # the running app saves itself every 2 s
FLAT20_CLICKS="out:white in:shIn cable:0 din:trig" ...                                # clicks on jacks / cable slots (din:, dout: Option-clicks)
```

## Layout

`Sources/FlatPanelUI/Layout.swift`: the knob section measured on a frontal photograph of an original MS-20 (its camera's keystone undone, which puts each VCO's knobs in one column, as on the instrument), the patch panel on one of an MS-20 mini's. The patch panel's arrows
show the circuit's own connections (what an input carries with nothing plugged in, where it goes), checked against
photographs of an original MS-20 and a full-size reissue. The drawing is this program's own, and the maker's name and
logo are not on it. VCO 1 OUT and VCO 2 OUT, which an MS-20 does not have, sit in the strip below the panel.

`Sources/FlatLink/Generated.swift` is written by `tools/gen_link_swift.py` from `ms20.h`; `tests/run_tests.sh` fails if
it is out of date.
