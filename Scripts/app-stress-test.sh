#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build/app-stress-checks"
mkdir -p "$BUILD/ModuleCache"

swiftc -O \
  -parse-as-library \
  -emit-library -static \
  -emit-module -module-name SidetrackCore \
  -module-cache-path "$BUILD/ModuleCache" \
  "$ROOT"/Sources/SidetrackCore/*.swift \
  -o "$BUILD/libSidetrackCore.a"

app_sources=("$ROOT"/Sources/Sidetrack/*.swift)
app_sources=("${app_sources[@]:#*/main.swift}")

swiftc -O \
  -I "$BUILD" -L "$BUILD" -lSidetrackCore \
  -framework AppKit -framework QuartzCore \
  -module-cache-path "$BUILD/ModuleCache" \
  "${app_sources[@]}" \
  "$ROOT/Tests/SidetrackAppStressTests/main.swift" \
  -o "$BUILD/SidetrackAppStressChecks"

cd "$ROOT"
"$BUILD/SidetrackAppStressChecks"
