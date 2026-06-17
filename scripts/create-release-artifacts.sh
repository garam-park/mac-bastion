#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(cat "$ROOT_DIR/VERSION")}"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$ROOT_DIR/.build/manual"
APP_DIR="$ROOT_DIR/.build/MacBastionMenu.app"

cd "$ROOT_DIR"
mkdir -p "$DIST_DIR"

scripts/build-cli.sh
scripts/package-menu-app.sh

rm -f "$DIST_DIR"/*

CLI_STAGING="$ROOT_DIR/.build/mbastion-$VERSION-macos-arm64"
rm -rf "$CLI_STAGING"
mkdir -p "$CLI_STAGING"
cp "$BUILD_DIR/mbastion" "$CLI_STAGING/mbastion"
cp "$BUILD_DIR/libMacBastionCore.dylib" "$CLI_STAGING/libMacBastionCore.dylib"
cp README.md "$CLI_STAGING/README.md"

tar -czf "$DIST_DIR/mbastion-$VERSION-macos-arm64.tar.gz" -C "$ROOT_DIR/.build" "mbastion-$VERSION-macos-arm64"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/MacBastionMenu-$VERSION-macos-arm64.zip"

cd "$DIST_DIR"
shasum -a 256 "MacBastionMenu-$VERSION-macos-arm64.zip" "mbastion-$VERSION-macos-arm64.tar.gz" > SHA256SUMS.txt

echo "$DIST_DIR"
