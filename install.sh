#!/bin/bash
# One-line install:  curl -fsSL https://raw.githubusercontent.com/longroadsoftware/claude-usage-meter/main/install.sh | bash
# Downloads the latest signed + notarized release, puts it in ~/Applications and starts it. No building, no admin password.
set -euo pipefail
REPO="longroadsoftware/claude-usage-meter"
NAME="Claude Usage Meter"
DEST="$HOME/Applications"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

echo "Finding the latest release…"
URL="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
[ -n "$URL" ] || { echo "Couldn't find a release to download."; exit 1; }

echo "Downloading $(basename "$URL")…"
curl -fsSL "$URL" -o "$TMP/app.zip"
ditto -x -k "$TMP/app.zip" "$TMP"
spctl -a -t exec "$TMP/$NAME.app" 2>/dev/null || { echo "The download didn't pass Apple's notarization check; not installing."; exit 1; }

pkill -f "$NAME.app/Contents/MacOS/" 2>/dev/null || true
mkdir -p "$DEST"; rm -rf "$DEST/$NAME.app"
ditto "$TMP/$NAME.app" "$DEST/$NAME.app"
open "$DEST/$NAME.app"
echo "Installed to $DEST/$NAME.app. Look for it at the top right of your screen."
