#!/usr/bin/env bash
# Wraps build/Harvestbeam.app in a branded disk image: orange window, the app
# on the left, Applications on the right, a dotted beam between them.
#   scripts/make-dmg.sh [output.dmg]   → build/Harvestbeam.dmg by default
#   APP_NAME="Harvestbeam Beta" scripts/make-dmg.sh …   → the beta's
# Build the app first (scripts/build-app.sh). Uses dmgbuild, installed into
# build/.dmgbuild the first time, so Finder never has to be scripted.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="${APP_NAME:-Harvestbeam}"
APP="build/${APP_NAME}.app"
DMG="${1:-build/Harvestbeam.dmg}"
[[ -d "$APP" ]] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }

VENV="build/.dmgbuild"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet dmgbuild
fi

swift scripts/make-dmg-background.swift build/dmg "$APP_NAME" >/dev/null
rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py \
  -D app="$APP" -D background=build/dmg/background.png \
  "$APP_NAME" "$DMG"
echo "Built $DMG"
