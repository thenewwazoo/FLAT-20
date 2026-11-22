# Building FLAT-20

From a fresh checkout to FLAT-20 on your FM-1. Each step works before you go to the next.

```
firmware/src/flat20.c     <- the instrument: the pages, the screen, the patch panel, presets, MIDI, the panel link
firmware/src/ms20.h       <- the MS-20 engine (docs/MS20-CIRCUIT.md)
firmware/src/ms20_link.h  <- the panel link to the Mac app (mac/)
firmware/src/platform.c   <- the platform: boot, USB, MIDI, updates, the audio interrupt, storage (from Dinghy)
firmware/src/*.c, hal/    <- the rest of the platform: Felucca's, as SLOOP / OberVave / Dinghy carry it
```

## 1. Set up once

You need Linux on x86-64 (or macOS / Windows with Docker or WSL), Python 3 with Pillow, the JieLi toolchain
and three files of the JieLi AC79 SDK:

```sh
pip3 install Pillow mido python-rtmidi
tools/get_toolchain.sh                      # JieLi's clang for the chip, to ~/.jieli/toolchain
git clone --depth 1 --branch AC79NN_SDK_V1.2.1_2023-12-13 \
    https://gitee.com/Jieli-Tech/fw-AC79_AIoT_SDK.git ~/fw-AC79_AIoT_SDK
```

On macOS the build runs the toolchain in a `linux/amd64` Docker container by itself (have Docker running).
`JIELI_TOOLCHAIN` and `AC79_SDK` point elsewhere if your copies live somewhere else.

## 2. Hear it without an FM-1

```sh
tests/run_host.sh                           # -> build/host/flat20.wav and screen PNGs
```

Host mode runs the same `flat20.c` on your computer: the sound as a WAV, the screen as images, keys and knobs from a
script (`tests/host.c` lists what a script line can do). `tests/render.c` renders the engine alone from settings on
the command line.

## 3. Onto the FM-1

```sh
./build.sh                                       # -> build/flat20.fwsc (fails on what would brick the FM-1)
python3 tools/fm1_install.py build/flat20.fwsc   # over USB; asks before it writes, restarts into the build
python3 tools/fm1_install.py --info              # what runs on the connected FM-1
```

Back to another firmware, or to the official one, with the [FM-1 Firmware Hub](https://thefirmwarehub.com) in Chrome
or Edge: FLAT-20 answers the hub's updater like every firmware there. Installing firmware is at your own risk.

`./build.sh --release X.Y` makes a release package, `build/flat20-X.Y.fwsc`, identity `FM-1_95Y` (a dev build is
`FM-1_950`). A tag `vX.Y` on GitHub builds and publishes it (`.github/workflows/release.yml`).

## 4. Test

```sh
sh tests/run_tests.sh                        # after ./build.sh: the engine, the link, the Mac app, the update path
```

## 5. When it goes wrong

- **It crashes:** the screen shows where (the PC), then the FM-1 restarts. Twice at boot and it goes to the
  USB rescue by itself.
- **It won't start at all:** hold **OCT-** while switching on: the USB rescue, no sound, only the updater. Install
  a working build (or another firmware from the hub) from there.
- **The build refuses:** it checks for a 64-bit division, a call into the chip ROM, too much RAM, a register touched
  outside `hal/`. [RULES.md](RULES.md) says why each one matters.

## More

- **[API.md](API.md)**: everything the platform gives the app: the panel's ids, the screen calls, the audio contract,
  MIDI, storage, the flash map, timing.
- **[RULES.md](RULES.md)**: the chip's rules (no FPU in the main loop, no libgcc, the audio interrupt's budget) and
  what the build checks.
- **[MS20-CIRCUIT.md](MS20-CIRCUIT.md)**: the circuit behind the engine, part by part.

The platform comes from [Dinghy](https://github.com/zvenson/dinghy) (zvenson), after
[Felucca](https://github.com/hugelton/Felucca) (Leo Kuroshita, Hügelton Instruments) and
[SLOOP](https://github.com/isod89/sloop-fm1) (isod89); credits in [LICENSING.md](../LICENSING.md).
