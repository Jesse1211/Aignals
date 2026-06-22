#!/usr/bin/env bash
set -euo pipefail
VERSION="${1:-0.1.0}"

PROJ="App/Aignals/Aignals.xcodeproj"
SCHEME="Aignals"
DERIVED="./build"
APP="$DERIVED/Build/Products/Release/Aignals.app"

rm -rf "$DERIVED" dist
# The .xcodeproj is a gitignored XcodeGen artifact; regenerate it so this
# script works on a fresh clone (and picks up any project.yml changes).
(cd App/Aignals && xcodegen generate)
xcodebuild -project "$PROJ" -scheme "$SCHEME" -configuration Release -derivedDataPath "$DERIVED" build
test -x "$APP/Contents/Resources/aignals-hook"

# Self-sign
codesign --force --deep --sign - "$APP"

mkdir -p dist
ZIP="dist/Aignals-$VERSION.zip"
DMG="dist/Aignals-$VERSION.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

if command -v create-dmg >/dev/null; then
  create-dmg \
    --volname "Aignals $VERSION" \
    --window-size 540 320 \
    --icon-size 96 \
    --icon "Aignals.app" 140 160 \
    --app-drop-link 400 160 \
    "$DMG" \
    "$APP"
else
  hdiutil create -volname "Aignals $VERSION" -srcfolder "$APP" -ov -format UDZO "$DMG"
fi

shasum -a 256 "$ZIP" "$DMG" > "dist/SHA256SUMS-$VERSION.txt"
ls -lh dist/
