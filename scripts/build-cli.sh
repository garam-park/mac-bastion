#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"
MODULE_DIR="$BUILD_DIR/modules"

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR" "$MODULE_DIR"

swiftc \
  -parse-as-library \
  -emit-module \
  -emit-library \
  -module-name MacBastionCore \
  Sources/MacBastionCore/*.swift \
  -emit-module-path "$MODULE_DIR/MacBastionCore.swiftmodule" \
  -Xlinker -install_name \
  -Xlinker @rpath/libMacBastionCore.dylib \
  -o "$BUILD_DIR/libMacBastionCore.dylib"

swiftc \
  -parse-as-library \
  -I "$MODULE_DIR" \
  -L "$BUILD_DIR" \
  -lMacBastionCore \
  -Xlinker -rpath \
  -Xlinker @executable_path \
  Sources/mbastion/main.swift \
  -o "$BUILD_DIR/mbastion"

codesign --force --sign - "$BUILD_DIR/libMacBastionCore.dylib"
codesign --force --sign - "$BUILD_DIR/mbastion"

echo "$BUILD_DIR/mbastion"
