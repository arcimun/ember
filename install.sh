#!/bin/bash
# Build and install Dictation Service v7
set -euo pipefail
cd "$(dirname "$0")"

APP="/Applications/DictationService.app"

echo "Building..."
swift build -c release 2>&1

echo "Installing to $APP..."
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DictationService "$APP/Contents/MacOS/DictationService"

cat > "$APP/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DictationService</string>
    <key>CFBundleIdentifier</key>
    <string>com.arcimun.dictation-service</string>
    <key>CFBundleName</key>
    <string>Dictation Service</string>
    <key>CFBundleDisplayName</key>
    <string>Dictation Service</string>
    <key>CFBundleVersion</key>
    <string>7</string>
    <key>CFBundleShortVersionString</key>
    <string>7.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Dictation Service needs microphone access for speech transcription.</string>
</dict>
</plist>
EOF

echo "Signing..."
codesign --force --sign - --identifier com.arcimun.dictation-service "$APP" 2>&1

echo "Stopping old instances..."
pkill -f DictationService 2>/dev/null || true
pkill -f dictation-service 2>/dev/null || true
sleep 1

echo ""
echo "✅ Installed! Launch with:"
echo "   open /Applications/DictationService.app"
echo ""
echo "First time: add DictationService.app to Accessibility in System Settings"
