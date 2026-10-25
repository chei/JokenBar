#!/usr/bin/env bash
# JokenBar installer / updater.
# Downloads the latest release from GitHub, copies it to Applications and launches it.
set -euo pipefail

REPO="${JOKENBAR_REPO:-chei/JokenBar}"
URL="https://github.com/$REPO/releases/latest/download/JokenBar.zip"
APP_NAME="JokenBar.app"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "JokenBar runs on macOS only." >&2
  exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
  echo "JokenBar requires macOS 14 (Sonoma) or later." >&2
  exit 1
fi

# /Applications if writable (admin user), otherwise ~/Applications.
APP_DIR="/Applications"
if [[ ! -w "$APP_DIR" ]]; then
  APP_DIR="$HOME/Applications"
  mkdir -p "$APP_DIR"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading $URL"
curl -fsSL "$URL" -o "$tmp/app.zip"
ditto -x -k "$tmp/app.zip" "$tmp"

pkill -x JokenBar 2>/dev/null || true
rm -rf "${APP_DIR:?}/$APP_NAME"
ditto "$tmp/$APP_NAME" "$APP_DIR/$APP_NAME"
xattr -dr com.apple.quarantine "$APP_DIR/$APP_NAME" 2>/dev/null || true

open "$APP_DIR/$APP_NAME"
echo "Installed $APP_DIR/$APP_NAME – the JokenBar icon is now in your menu bar."
