#!/bin/bash
# Runs on: this Mac.
# Builds ClipHistory.app (Release), signs it with your Apple Development
# certificate so macOS keeps the Accessibility permission across rebuilds,
# installs it to ~/Applications and (re)starts it.
#   SIGN_ID="Apple Development: …"  scripts/build.sh   to pick a certificate
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet
xcodebuild -project ClipHistory.xcodeproj -scheme ClipHistory -configuration Release \
  -derivedDataPath build/DerivedData build -quiet

APP=build/DerivedData/Build/Products/Release/ClipHistory.app
ID="${SIGN_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [ -n "$ID" ]; then
  codesign --force --sign "$ID" "$APP"
else
  echo "No Apple Development certificate found; signing ad-hoc."
  echo "macOS will ask for Accessibility again after every rebuild."
  codesign --force --sign - "$APP"
fi

pkill -x ClipHistory 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/ClipHistory.app"
cp -R "$APP" "$HOME/Applications/"
open "$HOME/Applications/ClipHistory.app"
echo "Installed and started: $HOME/Applications/ClipHistory.app"
