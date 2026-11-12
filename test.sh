#!/bin/bash
# Runs the parsing checks (plus one live call). Usage: ./test.sh
set -euo pipefail
cd "$(dirname "$0")"
tmp=$(mktemp -d)
sed 's/^@main$//' QuotaBar.swift > "$tmp/QB.swift"
xcrun swiftc -parse-as-library "$tmp/QB.swift" tests.swift -o "$tmp/tests"
"$tmp/tests"
