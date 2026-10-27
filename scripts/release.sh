#!/usr/bin/env bash
# Builds Harvestbeam, wraps it in a disk image, publishes a GitHub Release and
# adds it to appcast.xml so installed copies update themselves.
#   scripts/release.sh 1.1.0 ["What's new, in light Markdown"]
#   CHANNEL=beta scripts/release.sh 1.4.0-beta.3 ["…"]   → a beta: its own
#     app, Harvestbeam Beta, as a GitHub pre-release, in appcast-beta.xml
# Needs a clean checkout of main (or a branch that fast-forwards it, as in a
# worktree), the GitHub CLI (gh) signed in, and the Sparkle private key in the
# login Keychain (see "Releasing" in the README). Everything is pushed to main,
# where installed copies read the appcast.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/release.sh <version> [release notes], e.g. 1.1.0}"
# Shown in the app's update window and at the top of the GitHub release.
RELEASE_NOTES="${2:-}"
TAG="v${VERSION}"
CHANNEL="${CHANNEL:-}"
APP_NAME="Harvestbeam"
FEED="appcast.xml"
if [[ "$CHANNEL" == "beta" ]]; then
  APP_NAME="Harvestbeam Beta"
  FEED="appcast-beta.xml"
fi
# Harvestbeam-1.3.1.dmg, Harvestbeam-Beta-1.4.0-beta.3.dmg
DMG_NAME="${APP_NAME// /-}-${VERSION}.dmg"
DMG="build/${DMG_NAME}"
REPO="tractorbeam-user/harvestbeam"
URL="https://github.com/${REPO}/releases/download/${TAG}/${DMG_NAME}"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi
git push origin HEAD:main

VERSION="$VERSION" CHANNEL="$CHANNEL" scripts/build-app.sh
APP_NAME="$APP_NAME" scripts/make-dmg.sh "$DMG"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "build/${APP_NAME}.app/Contents/Info.plist")"

# Sign the disk image with the EdDSA key. Prints: sparkle:edSignature="…" length="…"
# SPARKLE_KEY_FILE uses a key exported to a file instead of the Keychain.
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"
SIGNATURE="$("$SIGN_UPDATE" ${SPARKLE_KEY_FILE:+--ed-key-file "$SPARKLE_KEY_FILE"} "$DMG")"

git tag -a "$TAG" -m "${APP_NAME} ${VERSION}"
git push origin "$TAG"

NOTES="**Install:** download ${DMG_NAME}, open it and drag **${APP_NAME}** into Applications.
**The first time you open it,** macOS says it can't verify ${APP_NAME}, because it isn't signed with an Apple Developer ID. Click **Done**, then open **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to ${APP_NAME}, and confirm with your password. You only do this once; updates open normally.
Then sign in with a Harvest personal access token from https://id.getharvest.com/developers.
Already installed? ${APP_NAME} offers this update itself, or choose **Check for Updates…** in Preferences."
[[ -n "$RELEASE_NOTES" ]] && NOTES="${RELEASE_NOTES}

${NOTES}"
if [[ "$CHANNEL" == "beta" ]]; then
  NOTES="**Beta.** Harvestbeam Beta is its own app with features still being tried out (see the Beta section of the website). It installs next to Harvestbeam, uses the same sign-in, and updates to newer betas. Quit Harvestbeam while you use it, so only one is in the menu bar.

${NOTES}"
  # A pre-release, so the website's "latest" download stays the regular one.
  gh release create "$TAG" "$DMG" --title "${APP_NAME} ${VERSION}" --notes "$NOTES" --generate-notes --prerelease
else
  gh release create "$TAG" "$DMG" --title "${APP_NAME} ${VERSION}" --notes "$NOTES" --generate-notes
fi

# Newest first, so the item goes above the others. Sparkle compares
# sparkle:version (the build number) to decide what's newer. Betas go in
# their own feed, which only Harvestbeam Beta reads.
ITEM="    <item>
      <title>${APP_NAME} ${VERSION}</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>${BUILD}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
${RELEASE_NOTES:+      <description sparkle:format=\"markdown\"><![CDATA[${RELEASE_NOTES}]]></description>
}      <sparkle:fullReleaseNotesLink>https://github.com/${REPO}/releases/tag/${TAG}</sparkle:fullReleaseNotesLink>
      <enclosure url=\"${URL}\" type=\"application/octet-stream\" ${SIGNATURE} />
    </item>" FEED="$FEED" python3 - <<'PY'
import os, re
path = os.environ["FEED"]
xml = open(path).read()
item = os.environ["ITEM"] + "\n"
m = re.search(r"^\s*<item>", xml, re.M) or re.search(r"^\s*</channel>", xml, re.M)
open(path, "w").write(xml[:m.start()] + item + xml[m.start():])
PY

git add "$FEED"
git commit -m "release: ${APP_NAME} ${VERSION} in ${FEED}"
git push origin HEAD:main
echo "Released ${TAG}"
