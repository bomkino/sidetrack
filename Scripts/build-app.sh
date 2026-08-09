#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build/release"
APP="$ROOT/build/Sidetrack.app"
ARCHIVE="$ROOT/build/Sidetrack.app.zip"
ICONSET="$BUILD/Sidetrack.iconset"
DEPLOYMENT_TARGET="13.0"
ARCHITECTURES=(arm64 x86_64)

rm -rf "$APP" "$ICONSET" "$BUILD/arm64" "$BUILD/x86_64"
rm -f \
  "$ARCHIVE" \
  "$BUILD/Sidetrack" \
  "$BUILD/libSidetrackCore.a" \
  "$BUILD/SidetrackCore.abi.json" \
  "$BUILD/SidetrackCore.swiftdoc" \
  "$BUILD/SidetrackCore.swiftmodule" \
  "$BUILD/SidetrackCore.swiftsourceinfo"
mkdir -p "$ICONSET"

for arch in "${ARCHITECTURES[@]}"; do
  target="${arch}-apple-macosx${DEPLOYMENT_TARGET}"
  arch_build="$BUILD/$arch"
  mkdir -p "$arch_build/ModuleCache"

  swiftc -O -target "$target" \
    -parse-as-library \
    -emit-library -static \
    -emit-module -module-name SidetrackCore \
    -emit-module-path "$arch_build/SidetrackCore.swiftmodule" \
    -module-cache-path "$arch_build/ModuleCache" \
    "$ROOT"/Sources/SidetrackCore/*.swift \
    -o "$arch_build/libSidetrackCore.a"

  swiftc -O -target "$target" \
    -I "$arch_build" -L "$arch_build" -lSidetrackCore \
    -framework AppKit -framework QuartzCore \
    -module-cache-path "$arch_build/ModuleCache" \
    "$ROOT"/Sources/Sidetrack/*.swift \
    -o "$arch_build/Sidetrack"
done

lipo -create \
  "$BUILD/arm64/Sidetrack" \
  "$BUILD/x86_64/Sidetrack" \
  -output "$BUILD/Sidetrack"

built_architectures="$(lipo "$BUILD/Sidetrack" -archs)"
for arch in "${ARCHITECTURES[@]}"; do
  if [[ " $built_architectures " != *" $arch "* ]]; then
    echo "Missing required architecture: $arch" >&2
    exit 1
  fi

  built_target="$(vtool -arch "$arch" -show-build "$BUILD/Sidetrack" | awk '$1 == "minos" { print $2; exit }')"
  if [[ "$built_target" != "$DEPLOYMENT_TARGET" ]]; then
    echo "Unexpected deployment target for $arch: $built_target" >&2
    exit 1
  fi
done

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
find "$APP" -name $'Icon\r' -type f -delete
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ARCHIVE"

echo "$APP"
echo "$ARCHIVE"
