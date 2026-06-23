#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_DIR="$ROOT_DIR/.build/MacBastionMenu.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
BUILD_DIR="$ROOT_DIR/.build/manual"
ARCHS=("arm64" "x86_64")
DEPLOY_TARGET="12.0"

cd "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR"

# Build the core library and menu executable once per architecture, then lipo
# the slices into universal binaries (Apple Silicon + Intel).
core_slices=()
menu_slices=()
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
    -Xlinker @executable_path/../Frameworks \
    Sources/MacBastionMenu/main.swift \
    -o "$arch_dir/MacBastionMenu"

  core_slices+=("$arch_dir/libMacBastionCore.dylib")
  menu_slices+=("$arch_dir/MacBastionMenu")
done

lipo -create "${menu_slices[@]}" -output "$MACOS_DIR/MacBastionMenu"
lipo -create "${core_slices[@]}" -output "$FRAMEWORKS_DIR/libMacBastionCore.dylib"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>MacBastionMenu</string>
  <key>CFBundleIdentifier</key>
  <string>local.mac-bastion.menu</string>
  <key>CFBundleName</key>
  <string>Mac Bastion</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>__VERSION__</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

perl -0pi -e "s/__VERSION__/$VERSION/g" "$CONTENTS_DIR/Info.plist"

codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
