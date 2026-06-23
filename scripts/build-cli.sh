#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/manual"
ARCHS=("arm64" "x86_64")
DEPLOY_TARGET="12.0"

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR"

# Build the core library and CLI once per architecture, then lipo the slices
# into universal binaries so the release runs on both Apple Silicon and Intel.
core_slices=()
cli_slices=()
for arch in "${ARCHS[@]}"; do
  arch_dir="$BUILD_DIR/$arch"
  mkdir -p "$arch_dir"

  swiftc \
    -target "$arch-apple-macosx$DEPLOY_TARGET" \
    -parse-as-library \
    -emit-module \
    -emit-library \
    -module-name MacBastionCore \
    Sources/MacBastionCore/*.swift \
    -emit-module-path "$arch_dir/MacBastionCore.swiftmodule" \
    -Xlinker -install_name \
    -Xlinker @rpath/libMacBastionCore.dylib \
    -o "$arch_dir/libMacBastionCore.dylib"

  swiftc \
    -target "$arch-apple-macosx$DEPLOY_TARGET" \
    -parse-as-library \
    -I "$arch_dir" \
    -L "$arch_dir" \
    -lMacBastionCore \
    -Xlinker -rpath \
    -Xlinker @executable_path \
    Sources/mbastion/main.swift \
    -o "$arch_dir/mbastion"

  core_slices+=("$arch_dir/libMacBastionCore.dylib")
  cli_slices+=("$arch_dir/mbastion")
done

lipo -create "${core_slices[@]}" -output "$BUILD_DIR/libMacBastionCore.dylib"
lipo -create "${cli_slices[@]}" -output "$BUILD_DIR/mbastion"

codesign --force --sign - "$BUILD_DIR/libMacBastionCore.dylib"
codesign --force --sign - "$BUILD_DIR/mbastion"

echo "$BUILD_DIR/mbastion"
