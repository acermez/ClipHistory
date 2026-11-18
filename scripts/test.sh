#!/bin/bash
# Runs on: this Mac. Runs the unit tests (history store + clipboard parsing).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project ClipHistory.xcodeproj -scheme ClipHistory -derivedDataPath build/DerivedData test -quiet
echo "All tests passed."
