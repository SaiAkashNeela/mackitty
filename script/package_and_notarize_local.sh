#!/usr/bin/env bash
set -euo pipefail
set +x

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f .env ]; then
  echo "Error: .env file not found."
  exit 1
fi

# Silently source .env without printing secrets
set -a
source .env
set +a

APP_NAME="MacKitty"
SIGNING_IDENTITY="Developer ID Application: Sai Akash Neela (8GG7J6LQZL)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
VER=$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "1.0.0")
VER=$(echo "$VER" | tr -d '[:space:]')

echo "=== Building MacKitty Release Binary ($VER) ==="
swift build -c release
BIN_PATH="$(swift build -c release --show-bin-path)"

echo "=== Assembling App Bundle ==="
rm -rf "$DIST_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

if [ -d "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/Contents/Resources/"
fi
if [ -f "Sources/MoleMate/AppIcon.icns" ]; then
  cp "Sources/MoleMate/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi
if [ -f "Sources/MoleMate/logo.png" ]; then
  cp "Sources/MoleMate/logo.png" "$APP_BUNDLE/Contents/Resources/logo.png"
fi
if [ -f "Sources/MoleMate/tray_icon.png" ]; then
  cp "Sources/MoleMate/tray_icon.png" "$APP_BUNDLE/Contents/Resources/tray_icon.png"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>com.mackitty.app</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleShortVersionString</key>
  <string>$VER</string>
  <key>CFBundleVersion</key>
  <string>$VER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <false/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

echo "=== Code Signing App Bundle with Hardened Runtime ==="
codesign --deep --force --verify --verbose \
  --sign "$SIGNING_IDENTITY" \
  --options runtime \
  --timestamp \
  "$APP_BUNDLE"

codesign -dv --verbose=2 "$APP_BUNDLE"

echo "=== Creating DMG Installer ==="
DMG_STAGING="$DIST_DIR/dmg_staging"
rm -rf "$DMG_STAGING" "$DMG_PATH"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"
rm -rf "$DMG_STAGING"

echo "=== Signing DMG ==="
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"

echo "=== Submitting DMG to Apple Notary Service ==="
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait

echo "=== Stapling Notarization Ticket ==="
xcrun stapler staple "$DMG_PATH"

echo "=== Verifying Gatekeeper Assessment ==="
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH" || true

echo "=== Notarization Complete: $DMG_PATH is ready for distribution! ==="
