#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Generate mac/Tests/FlatLinkTests/Fixtures/host.log from a scripted run of the host firmware build.
set -e
cd "$(dirname "$0")/.."
F=mac/Tests/FlatLinkTests/Fixtures
mkdir -p build/host "$F"
cc -O2 -Wall -Wno-unused-function -Wno-initializer-overrides -DDINGHY_HOST -DAPP_VER='"dev"' -Ifirmware/hal -Ifirmware/src -Ifirmware/gen -o build/host/flat20 firmware/src/flat20.c
cat > "$F/host-script.txt" <<'S'
# boot (FLAT BEAT), a key, the wheel, a knob, then S&H RANDOM
200 keys 1
600 keys 0
800 enc 1 3
1000 enc 2 -3
1400 midi 0xC0 6 0
2600 end
S
build/host/flat20 build/host/fixture "$F/host-script.txt" > "$F/host.log"
grep -c "SysEx out" "$F/host.log"
