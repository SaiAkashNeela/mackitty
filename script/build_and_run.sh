#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="MacKitty"
BUNDLE_ID="com.mackitty.app"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SCRATCH_DIR="${TMPDIR:-/private/tmp}/mackitty-swiftpm"
SWIFT_MODULE_CACHE="${TMPDIR:-/private/tmp}/mackitty-swiftmodulecache"
CLANG_MODULE_CACHE="${TMPDIR:-/private/tmp}/mackitty-clangmodulecache"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

mkdir -p "$SCRATCH_DIR" "$SWIFT_MODULE_CACHE" "$CLANG_MODULE_CACHE"
SWIFT_MODULECACHE_PATH="$SWIFT_MODULE_CACHE" \
CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE" \
swift build --scratch-path "$SCRATCH_DIR"
BUILD_DIR="$(SWIFT_MODULECACHE_PATH="$SWIFT_MODULE_CACHE" CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE" swift build --scratch-path "$SCRATCH_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_CONTENTS/Resources"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_CONTENTS/Resources/"
fi

if [ -f "$ROOT_DIR/Sources/MoleMate/AppIcon.icns" ]; then
  cp "$ROOT_DIR/Sources/MoleMate/AppIcon.icns" "$APP_CONTENTS/Resources/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
