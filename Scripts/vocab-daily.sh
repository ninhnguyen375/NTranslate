#!/usr/bin/env bash
# Generates the next slice of the vocabulary pack, then folds everything into Resources.
#
# The whole list costs about an hour and a chunk of quota in one sitting, so this runs a bounded
# slice instead. Every finished word is already on disk, so stopping and resuming loses nothing.
#
#   ./Scripts/vocab-daily.sh          # 500 words
#   ./Scripts/vocab-daily.sh 200      # fewer
#
# Cards from the previous prompt version stay in the pack until the day their word is regenerated,
# so coverage never dips while the upgrade is in progress.
set -euo pipefail
cd "$(dirname "$0")/.."

LIMIT="${1:-500}"
BIN=".build/vocab/build-vocab-pack"
SOURCES=(
  Sources/translate/Translator.swift Sources/translate/AppConfig.swift
  Sources/translate/AppConfigPrompts.swift Sources/translate/LanguageDetector.swift
  Sources/translate/AppTheme.swift Sources/translate/APIKeyStore.swift
  Sources/translate/NativeSpeechEngine.swift
  Scripts/VocabWork.swift Scripts/build-vocab-pack.swift
)

mkdir -p .build/vocab
needs_build=0
[ -x "$BIN" ] || needs_build=1
if [ "$needs_build" = 0 ]; then
  for src in "${SOURCES[@]}"; do
    [ "$src" -nt "$BIN" ] && needs_build=1 && break
  done
fi
if [ "$needs_build" = 1 ]; then
  echo "Building generator…"
  swiftc -parse-as-library "${SOURCES[@]}" -o "$BIN"
fi

"$BIN" --limit "$LIMIT" --skip-failed
"$BIN" --pack
echo
echo "Run ./install-app.sh when you want the app bundle to pick up the new pack."
