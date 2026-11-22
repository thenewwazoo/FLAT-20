#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Build and ad-hoc sign FLAT-20 Panel.app into mac/build/FLAT-20 Panel.app.
set -e
cd "$(dirname "$0")"
python3 ../tools/gen_link_swift.py --check >/dev/null || { echo "build.sh: Generated.swift is out of date: run tools/gen_link_swift.py"; exit 1; }
swift build -c release --product FLAT20Panel
APP="build/FLAT-20 Panel.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/FLAT20Panel" "$APP/Contents/MacOS/FLAT-20 Panel"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>FLAT-20 Panel</string>
  <key>CFBundleDisplayName</key><string>FLAT-20 Panel</string>
  <key>CFBundleIdentifier</key><string>local.flat20.panel</string>
  <key>CFBundleExecutable</key><string>FLAT-20 Panel</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built: mac/$APP"
