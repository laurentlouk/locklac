#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="lockLac"
BUNDLE_ID="com.locklac.app"
VERSION=$(grep 'public static let version' "$PROJECT_DIR/Sources/LockLacCore/LockLacCore.swift" | sed 's/.*"\(.*\)".*/\1/')
BUILD_DIR="$PROJECT_DIR/.build/release"
APP_DIR="$PROJECT_DIR/$APP_NAME.app"
ZIP_NAME="lockLac-${VERSION}.zip"

echo "==> Building $APP_NAME v$VERSION (release)..."
cd "$PROJECT_DIR"
swift build -c release

echo "==> Assembling $APP_NAME.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/locklac" "$APP_DIR/Contents/MacOS/locklac"

# Copy Info.plist
cp "$PROJECT_DIR/Sources/locklac/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy app icon
ICON_SRC="$BUILD_DIR/locklac_locklac.bundle/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
elif [ -f "$PROJECT_DIR/Sources/locklac/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Sources/locklac/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Creating $ZIP_NAME..."
cd "$PROJECT_DIR"
rm -f "$ZIP_NAME"
ditto -c -k --keepParent "$APP_DIR" "$ZIP_NAME"

SHA256=$(shasum -a 256 "$ZIP_NAME" | awk '{print $1}')

echo ""
echo "==> Done!"
echo "    App:  $APP_DIR"
echo "    Zip:  $PROJECT_DIR/$ZIP_NAME"
echo "    SHA256: $SHA256"
echo ""
echo "To install manually:"
echo "    cp -R $APP_DIR /Applications/"
