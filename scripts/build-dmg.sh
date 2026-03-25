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

# Copy themes
if [ -d "Resources/themes" ]; then
    cp -R Resources/themes "${STAGING}/${APP_NAME}.app/Contents/Resources/themes"
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

DMG_SIZE=$(wc -c < "${DMG_PATH}" | tr -d ' ')
echo ""
echo "Done: ${DMG_PATH} created ($(du -h "${DMG_PATH}" | cut -f1))"

# ── Auto-sign for Sparkle and show appcast snippet ──
SIGN_TOOL=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ -x "${SIGN_TOOL}" ]; then
    echo ""
    echo "Signing for Sparkle..."
    SIGN_OUTPUT=$("${SIGN_TOOL}" "${DMG_PATH}" 2>&1)
    ED_SIG=$(echo "${SIGN_OUTPUT}" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
    SIGN_LEN=$(echo "${SIGN_OUTPUT}" | grep -o 'length="[^"]*"' | cut -d'"' -f2)

    if [ -n "${ED_SIG}" ]; then
        # Get correct day of week
        DOW=$(date -jf "%Y-%m-%d" "$(date +%Y-%m-%d)" "+%a")
        PUB_DATE=$(date -u "+${DOW}, %d %b %Y %H:%M:%S +0000")

        echo ""
        echo "=== APPCAST SNIPPET (paste as first <item>) ==="
        echo "    <item>"
        echo "      <title>Version ${VERSION}</title>"
        echo "      <sparkle:version>${VERSION}</sparkle:version>"
        echo "      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>"
        echo "      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"
        echo "      <pubDate>${PUB_DATE}</pubDate>"
        echo "      <enclosure"
        echo "        url=\"https://github.com/arcimun/ember/releases/download/v${VERSION}/${APP_NAME}-${VERSION}.dmg\""
        echo "        type=\"application/octet-stream\""
        echo "        sparkle:edSignature=\"${ED_SIG}\""
        echo "        length=\"${SIGN_LEN}\""
        echo "      />"
        echo "    </item>"
        echo "=== END SNIPPET ==="
    fi
fi

# ── Verify version consistency ──
echo ""
echo "Version consistency check:"
PLIST_VER=$(grep -A1 CFBundleVersion Resources/Info.plist | tail -1 | sed 's/.*<string>//' | sed 's/<.*//')
FILE_VER=$(cat VERSION 2>/dev/null | tr -d '[:space:]')
echo "  VERSION file:  ${FILE_VER:-MISSING}"
echo "  Info.plist:    ${PLIST_VER} (template, replaced with ${VERSION} at build)"
echo "  Build version: ${VERSION}"
if [ "${FILE_VER}" != "${VERSION}" ]; then
    echo "  ⚠️  WARNING: VERSION file (${FILE_VER}) != build version (${VERSION})"
fi
