#!/usr/bin/env bash
# Runs the tests with only the Command Line Tools installed: the same SDK as
# build-app.sh, plus the swift-testing macro plugin, which isn't on the
# compiler's default search path there.
set -euo pipefail
cd "$(dirname "$0")/.."
CLT=/Library/Developer/CommandLineTools
if [[ -z "${SDKROOT:-}" ]] && ! xcode-select -p | grep -q Xcode.app; then
  for sdk in "$CLT/SDKs/MacOSX26.5.sdk" "$CLT/SDKs/MacOSX26.sdk"; do
    if [[ -d "$sdk" ]]; then export SDKROOT="$sdk"; break; fi
  done
fi
PLUGINS="$CLT/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
  swift test "$@"
fi
