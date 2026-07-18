#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
BUILD="$ROOT/build/checks"
mkdir -p "$BUILD/ModuleCache"

swiftc -O \
  -parse-as-library \
  -emit-library -static \
  -emit-module -module-name SidetrackCore \
  -module-cache-path "$BUILD/ModuleCache" \
  "$ROOT"/Sources/SidetrackCore/*.swift \
  -o "$BUILD/libSidetrackCore.a"

swiftc -O \
  -I "$BUILD" -L "$BUILD" -lSidetrackCore \
  -module-cache-path "$BUILD/ModuleCache" \
  "$ROOT/Tests/SidetrackCoreTests/main.swift" \
  -o "$BUILD/SidetrackChecks"

cd "$ROOT"
"$BUILD/SidetrackChecks"
