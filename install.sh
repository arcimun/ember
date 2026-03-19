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
cp Resources/overlay.html "$APP/Contents/Resources/" 2>/dev/null || true
cp Resources/Ember.icns "$APP/Contents/Resources/" 2>/dev/null || true

# Copy Sparkle framework
if [ -d ".build/release/Sparkle.framework" ]; then
    mkdir -p "$APP/Contents/Frameworks"
    cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/"
fi

VERSION=$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo "1.0.0")
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "Fixing framework paths..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Ember" 2>/dev/null || true

echo "Signing..."
codesign --force --deep --sign - --identifier com.arcimun.ember "$APP" 2>&1

echo "Stopping old instances..."
pkill -f Ember 2>/dev/null || true
pkill -f DictationService 2>/dev/null || true
pkill -f dictation-service 2>/dev/null || true
sleep 1

echo ""
echo "✅ Installed! Launch with:"
echo "   open /Applications/Ember.app"
echo ""
echo "First time: add Ember.app to Accessibility in System Settings"
