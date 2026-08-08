#!/bin/zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$PROJECT_DIR/release-dmg.sh"

grep -Fq 'TAG="macos-v${VERSION}"' "$SCRIPT"
! grep -Fq 'TAG="v${VERSION}"' "$SCRIPT"
grep -Fq 'DMG_NAME="NTranslate-${VERSION}-${ARCH}.dmg"' "$SCRIPT"
