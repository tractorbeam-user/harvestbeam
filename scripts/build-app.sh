#!/usr/bin/env bash
# Builds "Harvest Bar.app" with SwiftPM and wraps it in an app bundle.
#   scripts/build-app.sh            → build/Harvest Bar.app
#   scripts/build-app.sh --install  → also copies it to /Applications and opens it
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Harvest Bar"
BUNDLE_ID="com.tractorbeam.harvestbar"
VERSION="1.0.0"
APP="build/${APP_NAME}.app"

# With only the Command Line Tools installed, the newest macOS SDK expects
# SwiftUI macro plugins that ship with Xcode. Fall back to the newest SDK that
# doesn't, unless the caller already chose one.
if [[ -z "${SDKROOT:-}" ]] && ! xcode-select -p | grep -q Xcode.app; then
  for sdk in /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk; do
    if [[ -d "$sdk" ]]; then export SDKROOT="$sdk"; break; fi
  done
fi

swift build -c release --product HarvestBar
BIN="$(swift build -c release --product HarvestBar --show-bin-path)/HarvestBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HarvestBar"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key><string>HarvestBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>Unofficial client for the Harvest API.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x HarvestBar 2>/dev/null || true
  rm -rf "/Applications/${APP_NAME}.app"
  cp -R "$APP" /Applications/
  open "/Applications/${APP_NAME}.app"
  echo "Installed to /Applications/${APP_NAME}.app"
fi
