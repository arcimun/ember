#!/bin/bash
# Build and install Ember v1.0.0
set -euo pipefail
cd "$(dirname "$0")"

APP="/Applications/Ember.app"

echo "Building..."
swift build -c release 2>&1

echo "Installing to $APP..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Ember "$APP/Contents/MacOS/Ember"
cp Resources/Ember.icns "$APP/Contents/Resources/" 2>/dev/null || true
# Copy themes directory
if [ -d "Resources/themes" ]; then
    rm -rf "$APP/Contents/Resources/themes"
    cp -R Resources/themes "$APP/Contents/Resources/themes"
fi

# Copy all frameworks from build output (generic — handles Sparkle, KeyboardShortcuts, WhisperKit, and future additions)
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
find .build/release -maxdepth 1 -name "*.framework" | while read fw; do
    echo "  Copying framework: $(basename "$fw")"
    cp -R "$fw" "$FRAMEWORKS_DIR/"
done

VERSION=$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo "1.0.0")
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "Fixing framework paths..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Ember" 2>/dev/null || true

echo "Signing..."
codesign --force --deep --sign - --identifier com.arcimun.ember "$APP" 2>&1

# Remove quarantine flag (prevents Gatekeeper blocking locally built apps)
xattr -cr "$APP" 2>/dev/null || true

echo "Stopping old instances..."
pkill -f Ember 2>/dev/null || true
sleep 1

# Reset Accessibility (CDHash changes on each rebuild)
tccutil reset Accessibility com.arcimun.ember 2>/dev/null || true

echo ""
echo "✅ Installed! Launching Ember..."
open "$APP"

# Open Accessibility settings — user just needs to toggle the switch
echo "📋 Opening Accessibility settings — toggle Ember ON for auto-paste"
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
