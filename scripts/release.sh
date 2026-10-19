#!/usr/bin/env bash
# Builds Harvestbeam, wraps it in a disk image and publishes a GitHub Release.
#   scripts/release.sh 1.1.0
# Needs a clean, pushed main branch and the GitHub CLI (gh) signed in.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?Usage: scripts/release.sh <version>, e.g. 1.1.0}"
TAG="v${VERSION}"
DMG="build/Harvestbeam-${VERSION}.dmg"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi
git push origin HEAD

VERSION="$VERSION" scripts/build-app.sh
scripts/make-dmg.sh "$DMG"

git tag -a "$TAG" -m "Harvestbeam ${VERSION}"
git push origin "$TAG"

NOTES="**Install:** download Harvestbeam-${VERSION}.dmg, open it and drag **Harvestbeam** into Applications.
The first time, right-click it and choose **Open**. It isn't signed with an Apple Developer ID, so macOS asks once.
Then sign in with a Harvest personal access token from https://id.getharvest.com/developers."
gh release create "$TAG" "$DMG" --title "Harvestbeam ${VERSION}" --notes "$NOTES" --generate-notes
echo "Released ${TAG}"
