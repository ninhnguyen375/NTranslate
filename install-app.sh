#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="NTranslate.app"
APP_SRC="$PROJECT_DIR/$APP_NAME"
APP_DST="/Applications/$APP_NAME"
BUILD_BIN="$PROJECT_DIR/.build/release/translate"
SRC_BIN="$APP_SRC/Contents/MacOS/NTranslate"
DST_BIN="$APP_DST/Contents/MacOS/NTranslate"
PLIST="$APP_SRC/Contents/Info.plist"
ICON_SRC="$PROJECT_DIR/icon.jpg"
ICONSET_DIR="$PROJECT_DIR/NTranslate.iconset"
ICON_ICNS="$PROJECT_DIR/NTranslate.icns"
APP_ICON_DST="$APP_SRC/Contents/Resources/NTranslate.icns"

cd "$PROJECT_DIR"
swift build -c release

mkdir -p "$APP_SRC/Contents/MacOS" "$APP_SRC/Contents/Resources"
cp "$BUILD_BIN" "$SRC_BIN"
chmod +x "$SRC_BIN"

if [ -f "$ICON_SRC" ]; then
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" -s format png --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SRC" -s format png --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"
  cp "$ICON_ICNS" "$APP_ICON_DST"
fi

if [ ! -f "$PLIST" ]; then
  cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>NTranslate</string>
    <key>CFBundleExecutable</key>
    <string>NTranslate</string>
    <key>CFBundleIdentifier</key>
    <string>local.ninh.ntranslate</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NTranslate</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Translate selected text from other apps.</string>
    <key>NSAccessibilityUsageDescription</key>
    <string>Read selected text from other apps for translation.</string>
</dict>
</plist>
PLIST
fi

/usr/libexec/PlistBuddy -c 'Set :CFBundleName NTranslate' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName NTranslate' "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string NTranslate' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable NTranslate' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.ninh.ntranslate' "$PLIST"
if [ -f "$APP_ICON_DST" ]; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIconFile NTranslate' "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string NTranslate' "$PLIST"
fi
/usr/bin/plutil -lint "$PLIST" >/dev/null

pkill -x NTranslate || true
pkill -x translate || true
sleep 1
mkdir -p /Applications
mkdir -p "$APP_DST/Contents/MacOS" "$APP_DST/Contents/Resources"
cp "$SRC_BIN" "$DST_BIN"
chmod +x "$DST_BIN"
cp "$PLIST" "$APP_DST/Contents/Info.plist"
if [ -f "$APP_ICON_DST" ]; then
  cp "$APP_ICON_DST" "$APP_DST/Contents/Resources/NTranslate.icns"
fi
touch "$APP_DST"
open "$APP_DST"

echo "Installed: $APP_DST"
