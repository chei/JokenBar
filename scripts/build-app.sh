#!/usr/bin/env bash
# Builds a universal JokenBar.app and a zip into dist/.
# SIGN_IDENTITY: a "Developer ID Application: ..." identity; ad-hoc signing if unset.
set -euo pipefail

VERSION="${VERSION:-0.1.0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCHS=(--arch arm64 --arch x86_64)

swift build -c release "${ARCHS[@]}"
BIN_DIR="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="dist/JokenBar.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/JokenBar" "$APP/Contents/MacOS/"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

ditto -c -k --keepParent "$APP" "dist/JokenBar.zip"
echo "Built dist/JokenBar.zip ($VERSION)"
