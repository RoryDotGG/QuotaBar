#!/bin/bash
# Builds QuotaBar.app next to this script. Usage: ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

APP=QuotaBar.app
if [[ -e "$APP.tmp" ]]; then trash "$APP.tmp"; fi
mkdir -p "$APP.tmp/Contents/MacOS"

xcrun swiftc -O -parse-as-library -target arm64-apple-macos14 \
  QuotaBar.swift -o "$APP.tmp/Contents/MacOS/QuotaBar"

cat > "$APP.tmp/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.quotabar</string>
  <key>CFBundleName</key><string>QuotaBar</string>
  <key>CFBundleExecutable</key><string>QuotaBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP.tmp"
if [[ -e "$APP" ]]; then trash "$APP"; fi
mv "$APP.tmp" "$APP"
echo "Built $(pwd)/$APP"
