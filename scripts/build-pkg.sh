#!/bin/bash
# Build Ember.pkg — macOS installer package
# PKG installers run postinstall scripts that auto-remove quarantine
# so users don't need to run xattr -cr manually
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(cat VERSION 2>/dev/null | tr -d '[:space:]')}"
VERSION="${VERSION:-1.0.0}"
APP_NAME="Ember"
BUNDLE_ID="com.arcimun.ember"
STAGING="/tmp/ember-pkg-staging"
PKG_ROOT="/tmp/ember-pkg-root"
SCRIPTS_DIR="/tmp/ember-pkg-scripts"
PKG_PATH="dist/${APP_NAME}-${VERSION}.pkg"

echo "=== Building ${APP_NAME} v${VERSION} installer ==="

# ── Step 1: Build release ──
echo "Building release..."
swift build -c release

# ── Step 2: Assemble .app ──
echo "Assembling ${APP_NAME}.app..."
rm -rf "${STAGING}" "${PKG_ROOT}" "${SCRIPTS_DIR}"
mkdir -p "${STAGING}/${APP_NAME}.app/Contents/MacOS"
mkdir -p "${STAGING}/${APP_NAME}.app/Contents/Resources"
mkdir -p "${PKG_ROOT}/Applications"
mkdir -p "${SCRIPTS_DIR}"
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

# Info.plist with version
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "${STAGING}/${APP_NAME}.app/Contents/Info.plist"

# Fix rpath
install_name_tool -add_rpath "@executable_path/../Frameworks" "${STAGING}/${APP_NAME}.app/Contents/MacOS/${APP_NAME}" 2>/dev/null || true

# Sign the app
echo "Signing app..."
codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${STAGING}/${APP_NAME}.app"

# Move app into pkg root (install destination: /Applications)
cp -R "${STAGING}/${APP_NAME}.app" "${PKG_ROOT}/Applications/${APP_NAME}.app"

# ── Step 3: Create postinstall script ──
# This is the key — runs after installation, removes quarantine automatically
cat > "${SCRIPTS_DIR}/postinstall" << 'POSTINSTALL'
#!/bin/bash
# Remove quarantine flag so Gatekeeper doesn't block the app
xattr -cr /Applications/Ember.app 2>/dev/null || true

# Kill any old running instances
pkill -x Ember 2>/dev/null || true

exit 0
POSTINSTALL
chmod +x "${SCRIPTS_DIR}/postinstall"

# ── Step 4: Build component .pkg ──
echo "Building installer package..."
COMPONENT_PKG="/tmp/ember-component.pkg"
pkgbuild \
    --root "${PKG_ROOT}" \
    --scripts "${SCRIPTS_DIR}" \
    --identifier "${BUNDLE_ID}" \
    --version "${VERSION}" \
    --install-location "/" \
    "${COMPONENT_PKG}"

# ── Step 5: Build product .pkg with welcome/license ──
# Create distribution XML for a nicer installer UI
cat > "/tmp/ember-distribution.xml" << DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>${APP_NAME} ${VERSION}</title>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <options customize="never" require-scripts="false" hostArchitectures="arm64,x86_64"/>
    <choices-outline>
        <line choice="default">
            <line choice="${BUNDLE_ID}"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="${BUNDLE_ID}" visible="false">
        <pkg-ref id="${BUNDLE_ID}"/>
    </choice>
    <pkg-ref id="${BUNDLE_ID}" version="${VERSION}" onConclusion="none">#${APP_NAME}-component.pkg</pkg-ref>
</installer-gui-script>
DIST

# Create welcome HTML
mkdir -p "/tmp/ember-pkg-resources"
cat > "/tmp/ember-pkg-resources/welcome.html" << 'WELCOME'
<!DOCTYPE html>
<html>
<head><style>
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; color: #333; }
h1 { font-size: 24px; margin-bottom: 8px; }
.tagline { color: #666; font-size: 16px; margin-bottom: 20px; }
.feature { margin: 8px 0; font-size: 14px; }
.note { margin-top: 20px; padding: 12px; background: #f5f5f5; border-radius: 8px; font-size: 13px; color: #555; }
</style></head>
<body>
<h1>Ember</h1>
<p class="tagline">Speak. It types.</p>
<p class="feature">Press your hotkey, speak, release — text appears wherever your cursor is.</p>
<p class="feature">Powered by Groq Whisper — under 1 second transcription in 50+ languages.</p>
<div class="note">
After installation, Ember will appear in your menu bar. You'll need to grant Microphone and Accessibility permissions when prompted.
</div>
</body>
</html>
WELCOME

# Create conclusion HTML
cat > "/tmp/ember-pkg-resources/conclusion.html" << 'CONCLUSION'
<!DOCTYPE html>
<html>
<head><style>
body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 20px; color: #333; }
h1 { font-size: 22px; color: #28a745; }
.step { margin: 10px 0; font-size: 14px; }
code { background: #f0f0f0; padding: 2px 6px; border-radius: 4px; font-size: 13px; }
</style></head>
<body>
<h1>Ember is installed!</h1>
<p class="step">1. Open <strong>Ember</strong> from Applications (or Spotlight)</p>
<p class="step">2. Grant <strong>Microphone</strong> permission when prompted</p>
<p class="step">3. Grant <strong>Accessibility</strong> for auto-paste (optional)</p>
<p class="step">4. Hold <code>`</code> (backtick), speak, release — text appears!</p>
</body>
</html>
CONCLUSION

# Build the final product package
productbuild \
    --distribution "/tmp/ember-distribution.xml" \
    --resources "/tmp/ember-pkg-resources" \
    --package-path "/tmp" \
    "${PKG_PATH}"

# ── Cleanup ──
rm -rf "${STAGING}" "${PKG_ROOT}" "${SCRIPTS_DIR}" "${COMPONENT_PKG}"
rm -rf "/tmp/ember-distribution.xml" "/tmp/ember-pkg-resources"

PKG_SIZE=$(du -h "${PKG_PATH}" | cut -f1)
echo ""
echo "=== Done: ${PKG_PATH} (${PKG_SIZE}) ==="
echo ""
echo "Users: double-click the .pkg → follow installer → done."
echo "Quarantine is removed automatically by the postinstall script."

# ── Sign for Sparkle ──
SIGN_TOOL=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if [ -x "${SIGN_TOOL}" ]; then
    echo ""
    echo "Sparkle signature:"
    "${SIGN_TOOL}" "${PKG_PATH}" 2>&1
fi
