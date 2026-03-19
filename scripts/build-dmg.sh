#!/bin/bash
# Build Ember.app and create distributable DMG
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-1.0.0}"
APP_NAME="Ember"
BUNDLE_ID="com.arcimun.ember"
STAGING="/tmp/ember-dmg-staging"
DMG_PATH="dist/${APP_NAME}-${VERSION}.dmg"

echo "Building ${APP_NAME} v${VERSION}..."
swift build -c release

echo "Assembling ${APP_NAME}.app..."
rm -rf "${STAGING}"
mkdir -p "${STAGING}/${APP_NAME}.app/Contents/MacOS"
mkdir -p "${STAGING}/${APP_NAME}.app/Contents/Resources"
mkdir -p "dist"

cp ".build/release/${APP_NAME}" "${STAGING}/${APP_NAME}.app/Contents/MacOS/"

# Copy overlay HTML resources
if [ -f "Resources/overlay.html" ]; then
    cp Resources/overlay.html "${STAGING}/${APP_NAME}.app/Contents/Resources/"
fi
cp Resources/Ember.icns "${STAGING}/${APP_NAME}.app/Contents/Resources/" 2>/dev/null || true

# Copy Sparkle framework
if [ -d ".build/release/Sparkle.framework" ]; then
    mkdir -p "${STAGING}/${APP_NAME}.app/Contents/Frameworks"
    cp -R .build/release/Sparkle.framework "${STAGING}/${APP_NAME}.app/Contents/Frameworks/"
fi

sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "${STAGING}/${APP_NAME}.app/Contents/Info.plist"

echo "Fixing framework paths..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "${STAGING}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

echo "Signing..."
codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${STAGING}/${APP_NAME}.app"

echo "Creating DMG..."
if command -v create-dmg &>/dev/null; then
    create-dmg \
        --volname "${APP_NAME}" \
        --window-size 500 300 \
        --icon-size 100 \
        --app-drop-link 380 150 \
        --icon "${APP_NAME}.app" 120 150 \
        --no-internet-enable \
        "${DMG_PATH}" \
        "${STAGING}/"
else
    # Fallback: simple DMG without custom styling
    hdiutil create -volname "${APP_NAME}" -srcfolder "${STAGING}" -ov -format UDZO "${DMG_PATH}"
fi

rm -rf "${STAGING}"
echo ""
echo "Done: ${DMG_PATH} created ($(du -h "${DMG_PATH}" | cut -f1))"
