#!/bin/bash
# Maintainers: build a signed, notarized, universal zip for GitHub Releases.
# Needs a "Developer ID Application" certificate and a notarytool keychain profile.
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="profile" ./release.sh
set -euo pipefail
cd "$(dirname "$0")"
: "${SIGN_ID:?set SIGN_ID}"; : "${NOTARY_PROFILE:?set NOTARY_PROFILE}"
NAME="Claude Usage Meter"; VERSION="$(cat VERSION)"
./build.sh
codesign --force --options runtime --timestamp -s "$SIGN_ID" "build/$NAME.app"
ZIP="build/ClaudeUsageMeter-$VERSION.zip"
ditto -c -k --keepParent "build/$NAME.app" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 15m
xcrun stapler staple "build/$NAME.app"
rm "$ZIP"; ditto -c -k --keepParent "build/$NAME.app" "$ZIP"
spctl -a -vvv -t exec "build/$NAME.app"
shasum -a 256 "$ZIP"
echo "ready: $ZIP"
