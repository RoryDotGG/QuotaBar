#!/bin/bash
# Renders the icon, logos, screenshots and social preview into assets/, then builds
# assets/AppIcon.icns. Usage: ./branding/render.sh
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
sed 's/^@main$//' QuotaBar.swift > "$tmp/QuotaBar.swift"
xcrun swiftc -parse-as-library "$tmp/QuotaBar.swift" branding/Brand.swift -o "$tmp/render"
mkdir -p assets
"$tmp/render" assets
iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
echo "wrote assets/AppIcon.icns"
