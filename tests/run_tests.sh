#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# FLAT-20's host tests (no hardware). Run from the repo root after building:
#   sh build.sh
#   sh tests/run_tests.sh
# The engine, the panel link and the Mac panel app; the FM-1 app on the host (tests/run_host.sh), MIDI (tests/scripts);
# from the platform (Dinghy, after the fm1-to-smk37 kit's reference layer, genkigenki/sloop-fm1): the update path
# (ota.c, the loader, tools/fm1_install.py) and the packages.
set -e
export AC79_SDK="${AC79_SDK:-$HOME/fw-AC79_AIoT_SDK}"   # (fm1pkg_make.py: the SDK files of a package)
cd "$(dirname "$0")/.."
OUT=build/host
mkdir -p "$OUT"
CC="${CC:-cc} -O1 -Wall -Wno-unused-function"
fail=0
run() { echo "== $1"; shift; "$@" || fail=1; }

[ -f build/flat20.fwsc ] || { echo "run ./build.sh first"; exit 1; }

${CC:-cc} -O2 -Wall -Ifirmware/src -o "$OUT/ms20_test" tests/ms20_test.c -lm
run "the engine against the MS-20's circuit (pitch in Hz / V, triggers, filters, envelopes, the patch panel)" "$OUT/ms20_test"
run "the panel link: what the FM-1 tells a computer (STATE, LIVE, rates, echo safety)" ${PYTHON:-python3} tests/link_test.py
run "the panel app's lists of knobs and jacks match ms20.h (mac/Sources/FlatLink/Generated.swift)" ${PYTHON:-python3} tools/gen_link_swift.py --check
if command -v swift >/dev/null 2>&1; then
    run "the panel app (mac/): decoding the firmware's messages, the model, every jack on the panel" sh -c "cd mac && swift test -q"
fi
${CC:-cc} -O2 -Wall -Ifirmware/src -o "$OUT/render" tests/render.c
run "FM-1 app on the host: the default script plays, screens and sound" sh tests/run_host.sh
run "FM-1 MIDI: USB, the TRS jack, a clock, the channel" sh tests/run_host.sh tests/scripts/midi.txt

$CC -o "$OUT/ota_test" tests/ota_test.c
run "M-UPGRADE entry (FM-1)" "$OUT/ota_test" build/flat20.fwsc
head -c 60000 build/flat20.bin > "$OUT/old_app.bin"
python3 tools/fm1pkg_make.py "$OUT/old_app.bin" build/loader/ota.bin "$OUT/old.fwsc" >/dev/null
$CC -o "$OUT/ldr_screen_test" tests/ldr_screen_test.c
run "update loader's screen (from Skiff): UPDATE MODE, WRITING and its bar, UPDATE FAILED" "$OUT/ldr_screen_test" "$OUT"
$CC -o "$OUT/ldr_test" tests/ldr_test.c
run "update loader (FM-1): other app -> this build" "$OUT/ldr_test" "$OUT/old.fwsc" build/flat20.fwsc

run "installer (tools/fm1_install.py): install, and the update-mode resume checks the model" python3 tests/install_test.py

[ "$fail" = 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit "$fail"
