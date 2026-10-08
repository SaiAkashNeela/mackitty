#!/usr/bin/env bash
# Builds the sandboxed Mac App Store variant of MacKitty and packages it as a
# signed .pkg ready for upload to App Store Connect.
#
# Requirements (one-time, see docs/app-store-submission.md):
#   - "Apple Distribution" certificate in the login keychain
#   - "Mac Installer Distribution" certificate in the login keychain
#     (shows up as "3rd Party Mac Developer Installer: ...")
#   - A "Mac App Store Connect" provisioning profile for com.mackitty.app
#
# Usage:
#   MAS_PROVISIONING_PROFILE=path/to/MacKitty_AppStore.provisionprofile \
#     ./script/build_appstore.sh [build-number]
#
# Optional upload (App Store Connect API key):
#   ASC_KEY_ID=... ASC_ISSUER_ID=... ./script/build_appstore.sh 42 --upload
set -euo pipefail

APP_NAME="MacKitty"
BUNDLE_ID="com.mackitty.app"
TEAM_NAME="Sai Akash Neela (8GG7J6LQZL)"
APP_IDENTITY="${MAS_APP_IDENTITY:-Apple Distribution: $TEAM_NAME}"
INSTALLER_IDENTITY="${MAS_INSTALLER_IDENTITY:-3rd Party Mac Developer Installer: $TEAM_NAME}"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist/appstore"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
PKG_PATH="$DIST_DIR/$APP_NAME.pkg"
ENTITLEMENTS="$ROOT_DIR/AppStore/MacKitty.entitlements"

VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
BUILD_NUMBER="${1:-$(date +%Y%m%d%H%M)}"
UPLOAD="${2:-}"

: "${MAS_PROVISIONING_PROFILE:?Set MAS_PROVISIONING_PROFILE to the Mac App Store provisioning profile path}"
[ -f "$MAS_PROVISIONING_PROFILE" ] || { echo "Profile not found: $MAS_PROVISIONING_PROFILE" >&2; exit 1; }

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER) for the Mac App Store"

# Universal release build with the APPSTORE flag, which compiles out the
# self-updater, the Mole CLI integration, Terminal automation and the
# move-to-Applications prompt (none are allowed in the App Store sandbox).
swift build -c release \
  --arch arm64 --arch x86_64 \
  -Xswiftc -DAPPSTORE \
  --scratch-path "$ROOT_DIR/.build-appstore"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 -Xswiftc -DAPPSTORE --scratch-path "$ROOT_DIR/.build-appstore" --show-bin-path)"

rm -rf "$DIST_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"
if [ -d "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
  cp -R "$BIN_DIR/${APP_NAME}_${APP_NAME}.bundle" "$CONTENTS/Resources/"
fi
cp "$ROOT_DIR/Sources/MoleMate/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
cp "$ROOT_DIR/AppStore/PrivacyInfo.xcprivacy" "$CONTENTS/Resources/PrivacyInfo.xcprivacy"
cp "$MAS_PROVISIONING_PROFILE" "$CONTENTS/embedded.provisionprofile"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Sai Akash Neela</string>
  <key>ITSAppUsesNonExemptEncryption</key><false/>
</dict>
</plist>
PLIST

# Sign inside-out: resource bundle first, then the app with sandbox entitlements.
if [ -d "$CONTENTS/Resources/${APP_NAME}_${APP_NAME}.bundle" ]; then
  codesign --force --timestamp --sign "$APP_IDENTITY" "$CONTENTS/Resources/${APP_NAME}_${APP_NAME}.bundle"
fi
codesign --force --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$APP_IDENTITY" \
  "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_BUNDLE"
codesign -d --entitlements - "$APP_BUNDLE" | grep -q "com.apple.security.app-sandbox" \
  || { echo "App Sandbox entitlement missing from signature" >&2; exit 1; }

productbuild --component "$APP_BUNDLE" /Applications --sign "$INSTALLER_IDENTITY" "$PKG_PATH"
pkgutil --check-signature "$PKG_PATH"
echo "Package ready: $PKG_PATH"

if [ "$UPLOAD" = "--upload" ]; then
  : "${ASC_KEY_ID:?Set ASC_KEY_ID}" "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
  # The API key file must be at ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8
  xcrun altool --validate-app -f "$PKG_PATH" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  xcrun altool --upload-app -f "$PKG_PATH" -t macos --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
fi
