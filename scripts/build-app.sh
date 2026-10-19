#!/usr/bin/env bash
# Builds "Harvestbeam.app" with SwiftPM and wraps it in an app bundle.
#   scripts/build-app.sh            → build/Harvestbeam.app
#   scripts/build-app.sh --install  → also copies it to /Applications and opens it
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Harvestbeam"
BUNDLE_ID="com.tractorbeam.harvestbar"
# scripts/release.sh passes VERSION; local builds keep the default.
VERSION="${VERSION:-1.0.0}"
# Sparkle compares this build number to the appcast's, so it only goes up.
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/${APP_NAME}.app"
# Sparkle reads updates from appcast.xml on main (scripts/release.sh adds to it)
# and only installs ones signed with the private half of this key.
FEED_URL="${FEED_URL:-https://raw.githubusercontent.com/tractorbeam-user/harvest-bar/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="y+DGD90Za+tNzS/KyDmBkCKFUwzGBoHzC25Q1U1ozac="

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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/HarvestBar"
# SwiftPM leaves Sparkle.framework next to the binary; apps load it from
# Contents/Frameworks. ditto keeps the framework's symlinks.
ditto "$(dirname "$BIN")/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/HarvestBar"
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
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHumanReadableCopyright</key><string>Unofficial client for the Harvest API.</string>
  <key>SUFeedURL</key><string>${FEED_URL}</string>
  <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
</dict>
</plist>
PLIST

# Ad hoc, with no Developer ID: --deep re-signs Sparkle's helpers to match.
codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x HarvestBar 2>/dev/null || true
  rm -rf "/Applications/${APP_NAME}.app"
  rm -rf "/Applications/Harvest Bar.app" # the app's old name
  cp -R "$APP" /Applications/
  open "/Applications/${APP_NAME}.app"
  echo "Installed to /Applications/${APP_NAME}.app"
fi
