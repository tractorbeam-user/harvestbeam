#!/usr/bin/env bash
# Builds Harvest Bar, zips it and publishes a GitHub Release with the zip.
#   scripts/release.sh 1.1.0
# Needs a clean, pushed main branch and the GitHub CLI (gh) signed in.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/release.sh <version>, e.g. 1.1.0}"
TAG="v${VERSION}"
ZIP="build/Harvest-Bar-${VERSION}.zip"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi
git push origin HEAD

VERSION="$VERSION" scripts/build-app.sh
rm -f "$ZIP"
# ditto keeps the app bundle's structure and signature intact inside the zip.
ditto -c -k --keepParent "build/Harvest Bar.app" "$ZIP"

git tag -a "$TAG" -m "Harvest Bar ${VERSION}"
git push origin "$TAG"

NOTES="**Install:** download Harvest-Bar-${VERSION}.zip, unzip it and drag **Harvest Bar** to Applications.
The first time, right-click it and choose **Open**. It isn't signed with an Apple Developer ID, so macOS asks once.
Then sign in with a Harvest personal access token from https://id.getharvest.com/developers."
gh release create "$TAG" "$ZIP" --title "Harvest Bar ${VERSION}" --notes "$NOTES" --generate-notes
echo "Released ${TAG}"
