#!/bin/bash
set -e

echo "=== 1. Compiling Airspace in Release Mode ==="
swift build -c release

APP_NAME="Airspace.app"
CONTENTS_DIR="$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 2. Compile App Icon from source image if it exists
if [ -f "app_icon_base.jpg" ]; then
    echo "=== 2. Compiling AppIcon.icns from app_icon_base.jpg ==="
    mkdir -p AppIcon.iconset
    sips -s format png -z 16 16 app_icon_base.jpg --out AppIcon.iconset/icon_16x16.png > /dev/null 2>&1
    sips -s format png -z 32 32 app_icon_base.jpg --out AppIcon.iconset/icon_16x16@2x.png > /dev/null 2>&1
    sips -s format png -z 32 32 app_icon_base.jpg --out AppIcon.iconset/icon_32x32.png > /dev/null 2>&1
    sips -s format png -z 64 64 app_icon_base.jpg --out AppIcon.iconset/icon_32x32@2x.png > /dev/null 2>&1
    sips -s format png -z 128 128 app_icon_base.jpg --out AppIcon.iconset/icon_128x128.png > /dev/null 2>&1
    sips -s format png -z 256 256 app_icon_base.jpg --out AppIcon.iconset/icon_128x128@2x.png > /dev/null 2>&1
    sips -s format png -z 256 256 app_icon_base.jpg --out AppIcon.iconset/icon_256x256.png > /dev/null 2>&1
    sips -s format png -z 512 512 app_icon_base.jpg --out AppIcon.iconset/icon_256x256@2x.png > /dev/null 2>&1
    sips -s format png -z 512 512 app_icon_base.jpg --out AppIcon.iconset/icon_512x512.png > /dev/null 2>&1
    sips -s format png -z 1024 1024 app_icon_base.jpg --out AppIcon.iconset/icon_512x512@2x.png > /dev/null 2>&1
    iconutil -c icns AppIcon.iconset
    rm -rf AppIcon.iconset
fi


echo "=== 3. Creating macOS App Bundle Directory Structure ==="
# Delete the old app bundle first to reset modification dates in Finder
rm -rf "$APP_NAME"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "=== 4. Copying Binary and Icon to Bundle ==="
cp ".build/release/Airspace" "$MACOS_DIR/"
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES_DIR/"
    rm -f "AppIcon.icns"
fi

echo "=== 5. Creating Info.plist ==="
cat <<EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Airspace</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.airspace.Airspace</string>
    <key>CFBundleName</key>
    <string>Airspace</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <string>1</string>
    <key>NSCameraUsageDescription</key>
    <string>Airspace requires FaceTime camera access to track and translate hand gestures into system inputs.</string>
</dict>
</plist>
EOF

echo "=== 6. Finalizing App Bundle ==="
chmod +x "$MACOS_DIR/Airspace"

echo "=== 7. Performing Ad-hoc Codesigning ==="
codesign --force --deep --sign - "$APP_NAME"

echo "Success! Native macOS bundle created at: $(pwd)/$APP_NAME"
echo "You can now double-click it in Finder or drag it to your Applications folder!"
