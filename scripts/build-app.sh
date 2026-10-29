#!/bin/bash
# Builds dist/SVGroom.app (Apple silicon, release). Build products live outside OneDrive.
set -euo pipefail
cd "$(dirname "$0")/.."
SCRATCH="${SVGROOM_BUILD_DIR:-$HOME/Library/Caches/SVGroom-build}"

swift build -c release --arch arm64 --scratch-path "$SCRATCH"
BIN="$(swift build -c release --arch arm64 --scratch-path "$SCRATCH" --show-bin-path)/SVGroom"

APP="dist/SVGroom.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SVGroom"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Built $APP"
