#!/bin/bash
set -e

APP_NAME="VTE"
BUNDLE_ID="com.local.vte"
VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$SCRIPT_DIR"

echo "Building $APP_NAME..."

# ── Clean ────────────────────────────────────────────────────────────────────
rm -rf "$APP_NAME.app"

# ── Directory structure ───────────────────────────────────────────────────────
mkdir -p "$APP_NAME.app/Contents/MacOS"
mkdir -p "$APP_NAME.app/Contents/Resources"

# ── Compile ──────────────────────────────────────────────────────────────────
swiftc main.swift \
    -o "$APP_NAME.app/Contents/MacOS/$APP_NAME" \
    -framework Cocoa \
    -O

echo "Compiled."

# ── Info.plist ────────────────────────────────────────────────────────────────
cat > "$APP_NAME.app/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>Plain Text</string>
            <key>CFBundleTypeExtensions</key>
            <array>
                <string>txt</string>
                <string>text</string>
                <string>md</string>
                <string>log</string>
                <string>sh</string>
                <string>swift</string>
                <string>py</string>
                <string>js</string>
                <string>ts</string>
                <string>css</string>
                <string>html</string>
                <string>json</string>
                <string>yaml</string>
                <string>yml</string>
                <string>toml</string>
                <string>conf</string>
                <string>ini</string>
                <string>csv</string>
            </array>
            <key>CFBundleTypeRole</key>
            <string>Editor</string>
            <key>NSDocumentClass</key>
            <string>NSDocument</string>
        </dict>
    </array>
</dict>
</plist>
EOF

echo "Info.plist written."

# ── Icon ─────────────────────────────────────────────────────────────────────
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$APP_NAME.app/Contents/Resources/AppIcon.icns"
    echo "Copied pre-built AppIcon.icns."
elif command -v convert &>/dev/null && command -v iconutil &>/dev/null; then
    echo "Building icon from icon.svg..."
    ICONSET="AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        convert -background none "icon.svg" -resize "${size}x${size}" "$ICONSET/icon_${size}x${size}.png"
        double=$((size * 2))
        convert -background none "icon.svg" -resize "${double}x${double}" "$ICONSET/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns "$ICONSET" -o "$APP_NAME.app/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
    echo "Icon built."
elif command -v rsvg-convert &>/dev/null && command -v iconutil &>/dev/null; then
    echo "Building icon from icon.svg (rsvg-convert)..."
    ICONSET="AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 64 128 256 512; do
        rsvg-convert -w $size  -h $size  "icon.svg" -o "$ICONSET/icon_${size}x${size}.png"
        double=$((size * 2))
        rsvg-convert -w $double -h $double "icon.svg" -o "$ICONSET/icon_${size}x${size}@2x.png"
    done
    iconutil -c icns "$ICONSET" -o "$APP_NAME.app/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
    echo "Icon built."
else
    echo "Warning: No icon converter found (need imagemagick or librsvg). App will have no icon."
    echo "  Install with: brew install imagemagick  OR  brew install librsvg"
fi

# ── Code-sign (ad-hoc) ────────────────────────────────────────────────────────
codesign --force --deep --sign - "$APP_NAME.app"
echo "Code-signed (ad-hoc)."

echo ""
echo "✓  Built: $SCRIPT_DIR/$APP_NAME.app"
echo ""
echo "Run with:  open $APP_NAME.app"
echo "Or move to /Applications for permanent install."
