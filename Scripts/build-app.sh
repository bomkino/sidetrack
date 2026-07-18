#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build/release"
APP="$ROOT/build/Sidetrack.app"
ICONSET="$BUILD/Sidetrack.iconset"

rm -rf "$APP" "$ICONSET"
mkdir -p "$BUILD/ModuleCache" "$ICONSET"

swiftc -O \
  -parse-as-library \
  -emit-library -static \
  -emit-module -module-name SidetrackCore \
  -module-cache-path "$BUILD/ModuleCache" \
  "$ROOT"/Sources/SidetrackCore/*.swift \
  -o "$BUILD/libSidetrackCore.a"

swiftc -O \
  -I "$BUILD" -L "$BUILD" -lSidetrackCore \
  -framework AppKit -framework QuartzCore \
  -module-cache-path "$BUILD/ModuleCache" \
  "$ROOT"/Sources/Sidetrack/*.swift \
  -o "$BUILD/Sidetrack"

for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  size="${spec%% *}"
  name="${spec#* }"
  sips -z "$size" "$size" "$ROOT/Assets/Sidetrack-icon-source.png" --out "$ICONSET/$name" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$BUILD/Sidetrack.icns"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Sidetrack" "$APP/Contents/MacOS/Sidetrack"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BUILD/Sidetrack.icns" "$APP/Contents/Resources/Sidetrack.icns"
cp "$ROOT/Resources/Fonts/Newsreader.ttf" "$APP/Contents/Resources/Newsreader.ttf"
cp "$ROOT/Resources/Fonts/Newsreader-Italic.ttf" "$APP/Contents/Resources/Newsreader-Italic.ttf"
cp "$ROOT/Resources/Fonts/OFL.txt" "$APP/Contents/Resources/Newsreader-OFL.txt"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

echo "$APP"
