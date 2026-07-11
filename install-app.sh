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
SIGN_IDENTITY="Apple Development: ninhnguyen375@gmail.com (7GMHS3RDUF)"

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

CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || echo 0)
NEXT_BUILD=$(( ${CURRENT_BUILD:-0} + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PLIST"

# Semver-ish display version (MAJOR.MINOR.PATCH). Patch bumps on every build by default;
# pass VERSION_BUMP=minor or VERSION_BUMP=major when a change is big enough to warrant it,
# e.g. `VERSION_BUMP=minor ./install-app.sh`.
CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || echo "1.0.2")
IFS='.' read -r VMAJOR VMINOR VPATCH <<< "$CURRENT_VERSION"
VMAJOR=${VMAJOR:-1}
VMINOR=${VMINOR:-0}
VPATCH=${VPATCH:-0}
case "${VERSION_BUMP:-patch}" in
  major) VMAJOR=$((VMAJOR + 1)); VMINOR=0; VPATCH=0 ;;
  minor) VMINOR=$((VMINOR + 1)); VPATCH=0 ;;
  *) VPATCH=$((VPATCH + 1)) ;;
esac
NEXT_VERSION="$VMAJOR.$VMINOR.$VPATCH"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT_VERSION" "$PLIST"
echo "Version: $NEXT_VERSION (build $NEXT_BUILD)"

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
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DST"
codesign -vv "$APP_DST"
codesign -dv --verbose=4 "$APP_DST" 2>&1 | grep -E 'Identifier=|Authority=|TeamIdentifier=' || true
touch "$APP_DST"

# Seed runtime config into Application Support (app only reads this path; no hardcoded repo path).
CONFIG_SUPPORT_DIR="${HOME}/Library/Application Support/NTranslate"
CONFIG_DST="$CONFIG_SUPPORT_DIR/config.json"
CONFIG_SRC=""
if [ -f "$PROJECT_DIR/config.json" ]; then
  CONFIG_SRC="$PROJECT_DIR/config.json"
elif [ -f "$PROJECT_DIR/config.json.example" ]; then
  CONFIG_SRC="$PROJECT_DIR/config.json.example"
fi
mkdir -p "$CONFIG_SUPPORT_DIR"
if [ -z "$CONFIG_SRC" ]; then
  echo "Warning: no config.json or config.json.example in project; skipped seeding $CONFIG_DST" >&2
elif [ -f "$CONFIG_DST" ] && [ "${FORCE_CONFIG:-0}" != "1" ]; then
  echo "Config exists (leave as-is): $CONFIG_DST"
  echo "  Tip: FORCE_CONFIG=1 ./install-app.sh to overwrite from $CONFIG_SRC"
else
  cp "$CONFIG_SRC" "$CONFIG_DST"
  echo "Config seeded: $CONFIG_SRC -> $CONFIG_DST"
fi

open "$APP_DST"

echo "Installed: $APP_DST"
