#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(cat "$ROOT_DIR/VERSION")"
APP_DIR="$ROOT_DIR/.build/MacBastionMenu.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
BUILD_DIR="$ROOT_DIR/.build/manual"
MODULE_DIR="$BUILD_DIR/modules"

cd "$ROOT_DIR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$FRAMEWORKS_DIR" "$MODULE_DIR"

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
  -Xlinker @executable_path/../Frameworks \
  Sources/MacBastionMenu/main.swift \
  -o "$MACOS_DIR/MacBastionMenu"

cp "$BUILD_DIR/libMacBastionCore.dylib" "$FRAMEWORKS_DIR/libMacBastionCore.dylib"

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
