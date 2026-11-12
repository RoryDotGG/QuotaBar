#!/bin/bash
# Builds QuotaBar.app next to this script. Usage: ./build.sh
# Also used by the Homebrew formula, so it must not depend on anything outside Xcode CLT.
set -euo pipefail
cd "$(dirname "$0")"

APP=QuotaBar.app
mkdir -p "$APP/Contents/MacOS"

xcrun swiftc -O -parse-as-library -target "$(uname -m)-apple-macos14" \
  QuotaBar.swift -o "$APP/Contents/MacOS/QuotaBar"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.quotabar</string>
  <key>CFBundleName</key><string>QuotaBar</string>
  <key>CFBundleExecutable</key><string>QuotaBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP"
