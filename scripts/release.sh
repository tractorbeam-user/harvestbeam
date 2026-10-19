#!/usr/bin/env bash
# Builds Harvestbeam, wraps it in a disk image, publishes a GitHub Release and
# adds it to appcast.xml so installed copies update themselves.
#   scripts/release.sh 1.1.0 ["What's new, in light Markdown"]
# Needs a clean, pushed main branch, the GitHub CLI (gh) signed in, and the
# Sparkle private key in the login Keychain (see "Releasing" in the README).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/release.sh <version> [release notes], e.g. 1.1.0}"
# Shown in the app's update window and at the top of the GitHub release.
RELEASE_NOTES="${2:-}"
TAG="v${VERSION}"
DMG="build/Harvestbeam-${VERSION}.dmg"
REPO="tractorbeam-user/harvestbeam"
URL="https://github.com/${REPO}/releases/download/${TAG}/Harvestbeam-${VERSION}.dmg"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi
git push origin HEAD

VERSION="$VERSION" scripts/build-app.sh
scripts/make-dmg.sh "$DMG"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" build/Harvestbeam.app/Contents/Info.plist)"

# Sign the disk image with the EdDSA key. Prints: sparkle:edSignature="…" length="…"
# SPARKLE_KEY_FILE uses a key exported to a file instead of the Keychain.
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
SIGNATURE="$("$SIGN_UPDATE" ${SPARKLE_KEY_FILE:+--ed-key-file "$SPARKLE_KEY_FILE"} "$DMG")"

git tag -a "$TAG" -m "Harvestbeam ${VERSION}"
git push origin "$TAG"

NOTES="**Install:** download Harvestbeam-${VERSION}.dmg, open it and drag **Harvestbeam** into Applications.
**The first time you open it,** macOS says it can't verify Harvestbeam, because it isn't signed with an Apple Developer ID. Click **Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Harvestbeam, and confirm with your password. You only do this once; updates open normally.
Then sign in with a Harvest personal access token from https://id.getharvest.com/developers.
Already installed? Harvestbeam offers this update itself, or choose **Check for Updates…** in Preferences."
[[ -n "$RELEASE_NOTES" ]] && NOTES="${RELEASE_NOTES}

${NOTES}"
gh release create "$TAG" "$DMG" --title "Harvestbeam ${VERSION}" --notes "$NOTES" --generate-notes

# Newest first, so the item goes above the others. Sparkle compares
# sparkle:version (the build number) to decide what's newer.
ITEM="    <item>
      <title>Harvestbeam ${VERSION}</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
${RELEASE_NOTES:+      <description sparkle:format=\"markdown\"><![CDATA[${RELEASE_NOTES}]]></description>
}      <sparkle:fullReleaseNotesLink>https://github.com/${REPO}/releases/tag/${TAG}</sparkle:fullReleaseNotesLink>
      <enclosure url=\"${URL}\" type=\"application/octet-stream\" ${SIGNATURE} />
    </item>" python3 - <<'PY'
import os, re
path = "appcast.xml"
xml = open(path).read()
item = os.environ["ITEM"] + "\n"
m = re.search(r"^\s*<item>", xml, re.M) or re.search(r"^\s*</channel>", xml, re.M)
open(path, "w").write(xml[:m.start()] + item + xml[m.start():])
PY

git add appcast.xml
git commit -m "release: Harvestbeam ${VERSION} in the appcast"
git push origin HEAD
echo "Released ${TAG}"
