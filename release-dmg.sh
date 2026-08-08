#!/bin/zsh
# Package NTranslate.app into a UDZO .dmg and (optionally) upload to GitHub Releases.
#
# Usage:
#   ./release-dmg.sh
#   VERSION_BUMP=minor ./release-dmg.sh
#   SKIP_INSTALL=1 ./release-dmg.sh          # reuse existing /Applications/NTranslate.app
#   SKIP_UPLOAD=1 ./release-dmg.sh           # build DMG only (no gh release)
#   DRAFT=1 ./release-dmg.sh                 # create a draft GitHub Release
#   NOTES_FILE=notes.md ./release-dmg.sh     # custom release notes
#
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DST="/Applications/NTranslate.app"
DIST_DIR="$PROJECT_DIR/dist"
STAGE="$DIST_DIR/dmg-stage"
REPO_SLUG="ninhnguyen375/NTranslate"

cd "$PROJECT_DIR"

if [ "${SKIP_INSTALL:-0}" != "1" ]; then
  echo "==> Building + installing via ./install-app.sh"
  VERSION_BUMP="${VERSION_BUMP:-patch}" ./install-app.sh
else
  echo "==> SKIP_INSTALL=1 — using existing $APP_DST"
fi

if [ ! -d "$APP_DST" ]; then
  echo "Error: missing $APP_DST. Run without SKIP_INSTALL, or install first." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DST/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DST/Contents/Info.plist")"
ARCH_RAW="$(file -b "$APP_DST/Contents/MacOS/NTranslate")"
case "$ARCH_RAW" in
  *arm64*x86_64*|*x86_64*arm64*) ARCH="universal" ;;
  *arm64*) ARCH="arm64" ;;
  *x86_64*) ARCH="x86_64" ;;
  *) ARCH="unknown" ;;
esac

TAG="macos-v${VERSION}"
DMG_NAME="NTranslate-${VERSION}-${ARCH}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

echo "==> Packaging $TAG (build $BUILD, $ARCH)"
codesign -vv "$APP_DST"

rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP_DST" "$STAGE/NTranslate.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "NTranslate $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
rm -rf "$STAGE"

ls -lh "$DMG_PATH"
echo "DMG: $DMG_PATH"

# Keep README "Latest:" line in sync when present.
README="$PROJECT_DIR/README.md"
if [ -f "$README" ]; then
  perl -0pi -e "s|Latest: \\*\\*\\[(?:macos-)?v[0-9.]+\\]\\(https://github.com/${REPO_SLUG}/releases/tag/(?:macos-)?v[0-9.]+\\)\\*\\* — download \`NTranslate-[0-9.]+-[^\\\`]+\\.dmg\`|Latest: **[${TAG}](https://github.com/${REPO_SLUG}/releases/tag/${TAG})** — download \`${DMG_NAME}\`|s" "$README" || true
fi

if [ "${SKIP_UPLOAD:-0}" = "1" ]; then
  echo "==> SKIP_UPLOAD=1 — DMG ready locally (not uploaded)"
  echo "Version: $VERSION (build $BUILD)"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Error: gh CLI not found. Install GitHub CLI or re-run with SKIP_UPLOAD=1." >&2
  exit 1
fi

if gh release view "$TAG" --repo "$REPO_SLUG" >/dev/null 2>&1; then
  echo "Error: release $TAG already exists on GitHub. Bump version (VERSION_BUMP=minor) or delete the old release/tag." >&2
  exit 1
fi

NOTES_TMP="$(mktemp)"
cleanup() { rm -f "$NOTES_TMP"; }
trap cleanup EXIT

if [ -n "${NOTES_FILE:-}" ]; then
  cat "$NOTES_FILE" > "$NOTES_TMP"
else
  cat > "$NOTES_TMP" <<EOF
## NTranslate $VERSION

Prebuilt macOS app ($ARCH).

### Install
1. Download \`$DMG_NAME\`
2. Open the DMG and drag **NTranslate** into **Applications**
3. First launch: if Gatekeeper blocks it, Right-click the app → **Open** → confirm
4. Grant **Accessibility** in System Settings → Privacy & Security
5. Install and run [9router](https://github.com/decolua/9router), then set your API key in:
   \`~/Library/Application Support/NTranslate/config.json\`
   (copy from [\`config.json.example\`](https://github.com/${REPO_SLUG}/blob/main/config.json.example) if missing)

### Notes
- Signed with Apple Development identity (not Developer ID / notarized). macOS may show an unidentified-developer warning on first open.
- Requires macOS 26+ and a running OpenAI-compatible API (9router recommended at \`http://localhost:20128/v1\`).
- Build number: $BUILD
EOF
fi

GH_ARGS=(release create "$TAG" "$DMG_PATH" --repo "$REPO_SLUG" --title "NTranslate $VERSION" --notes-file "$NOTES_TMP")
if [ "${DRAFT:-0}" = "1" ]; then
  GH_ARGS+=(--draft)
fi

echo "==> Uploading GitHub Release $TAG"
gh "${GH_ARGS[@]}"

echo "Release: https://github.com/${REPO_SLUG}/releases/tag/${TAG}"
echo "Version: $VERSION (build $BUILD)"
