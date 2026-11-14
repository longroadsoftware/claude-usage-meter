#!/bin/bash
# Build "Claude Usage Meter.app". Usage: ./build.sh [--install]   (--install copies it to ~/Applications and launches it)
set -euo pipefail
cd "$(dirname "$0")"
NAME="Claude Usage Meter"
BUNDLE_ID="${BUNDLE_ID:-com.longroadsoftware.claudeusagemeter}"
SIGN_ID="${SIGN_ID:--}"          # "-" = ad-hoc. Set SIGN_ID="Developer ID Application: …" to sign for distribution.
VERSION="$(cat VERSION 2>/dev/null || echo 1.0.0)"
OUT="build/$NAME.app"

rm -rf build && mkdir -p build/AppIcon.iconset "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
for arch in arm64 x86_64; do
  swiftc -O -o build/ClaudeUsageMeter-$arch Sources/*.swift -framework AppKit -framework SwiftUI \
    -target "$arch-apple-macos14.0"
done
lipo -create -output build/ClaudeUsageMeter build/ClaudeUsageMeter-arm64 build/ClaudeUsageMeter-x86_64
build/ClaudeUsageMeter --icon build/AppIcon.iconset 72
iconutil -c icns build/AppIcon.iconset -o "$OUT/Contents/Resources/AppIcon.icns"
cp build/ClaudeUsageMeter "$OUT/Contents/MacOS/ClaudeUsageMeter"
cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>ClaudeUsageMeter</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp=none -s "$SIGN_ID" "$OUT" 2>/dev/null || codesign --force --options runtime -s "$SIGN_ID" "$OUT"
echo "built $OUT ($VERSION)"

if [ "${1:-}" = "--install" ]; then
  pkill -f "ClaudeUsageMeter$" 2>/dev/null || true; sleep 1
  rm -rf "$HOME/Applications/$NAME.app"; mkdir -p "$HOME/Applications"
  cp -R "$OUT" "$HOME/Applications/"
  open "$HOME/Applications/$NAME.app"
  echo "installed ~/Applications/$NAME.app"
fi
