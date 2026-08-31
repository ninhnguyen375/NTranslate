#!/usr/bin/env bash
# Builds and runs the debug binary signed like the installed app, so the Keychain sees the same
# designated requirement and stops asking for the login password on every run. Unsigned SwiftPM
# output is a brand-new identity after each build, which no "Always Allow" can remember.
set -euo pipefail
cd "$(dirname "$0")/.."

SIGN_IDENTITY="${SIGN_IDENTITY:-NTranslate Local Development}"
BUNDLE_ID="local.ninh.ntranslate"

swift build
BIN="$(swift build --show-bin-path)/translate"
codesign --force -i "$BUNDLE_ID" --options runtime --sign "$SIGN_IDENTITY" "$BIN"
exec "$BIN" "$@"
