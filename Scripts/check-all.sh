#!/bin/bash
# Builds and runs every standalone self-check in Scripts/.
#
# `swift test` is unusable here (the target needs swift-testing, which this toolchain does not
# ship), so each piece of non-trivial logic has a check compiled straight with swiftc. This script
# is the single place that records what each one needs to compile, so the list cannot rot in a
# comment somewhere.
#
#   ./Scripts/check-all.sh          run everything
#   ./Scripts/check-all.sh learn    run only checks whose name contains "learn"
#
# SKIP_UI=1 skips double-click-selection-check, which posts synthetic clicks and needs the running
# terminal to hold Accessibility permission.
set -uo pipefail
cd "$(dirname "$0")/.."

S=Sources/translate
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
filter=${1:-}
pass=0
fail=0
failed=()

# name : source files the check needs, in compile order
checks=(
  "speech-trim|$S/SpeechTrim.swift"
  "speech-gain|$S/SpeechGain.swift"
  "tagged-response|"
  "plural|$S/Plural.swift"
  "markdown-display|$S/MarkdownDisplay.swift"
  "text-zoom|$S/TextZoom.swift"
  "stream-session|$S/StreamSession.swift"
  "square-tool-button|$S/SquareToolButton.swift"
  "bubble-width|$S/ReadingBubbleWidth.swift"
  "reading-dialogue|$S/ReadingDialogue.swift"
  "reading-underline|$S/ReadingHighlight.swift"
  "weave-cache|$S/WeaveCache.swift"
  "weave-scenario|$S/WeaveCache.swift"
  "saved-passages-screen|$S/WeaveCache.swift $S/CustomDialogueDialog.swift"
  "layout-measure-cache|$S/PopoverLayoutMath.swift"
  "vocab-pack|$S/VocabPack.swift Scripts/VocabWork.swift"
  "vocab-discovery|$S/VocabPack.swift $S/WeaveCache.swift $S/VocabDiscovery.swift"
  "learn-card|$S/LearnCard.swift"
  "learn-badge|$S/VocabPack.swift $S/WeaveCache.swift $S/VocabDiscovery.swift $S/LearnBadgeView.swift"
  "review-planner|$S/LearnCard.swift $S/ReviewPlanner.swift"
  "learn-cache-key|$S/TranslationHistoryStore.swift $S/ReviewPlanner.swift $S/LearnCard.swift"
  "session-regrade|$S/TranslationHistoryStore.swift $S/ReviewPlanner.swift $S/LearnCard.swift"
  "history-write-queue|$S/TranslationHistoryStore.swift $S/ReviewPlanner.swift $S/LearnCard.swift"
  "deck-stats|$S/TranslationHistoryStore.swift $S/ReviewPlanner.swift $S/LearnCard.swift $S/DeckStats.swift"
  "learn-card-display|$S/LearnCard.swift $S/TextZoom.swift $S/VocabPack.swift $S/WeaveCache.swift $S/VocabDiscovery.swift $S/LearnBadgeView.swift $S/LayerAppearance.swift $S/SquareToolButton.swift $S/ReviewControls.swift $S/LearnStructuredCardView.swift $S/LearnRelatedImage.swift"
  "study-window-size|$S/TranslationHistoryStore.swift $S/ReviewPlanner.swift $S/LearnCard.swift $S/DeckStats.swift $S/Plural.swift $S/LayerAppearance.swift $S/SquareToolButton.swift $S/ReviewControls.swift $S/ReviewHomeView.swift"
  "double-click-selection|"
)

for entry in "${checks[@]}"; do
  name=${entry%%|*}
  deps=${entry#*|}
  [ -n "$filter" ] && [[ $name != *"$filter"* ]] && continue
  if [ "$name" = "double-click-selection" ] && [ "${SKIP_UI:-0}" = "1" ]; then
    echo "SKIP $name (SKIP_UI=1)"
    continue
  fi
  script="Scripts/$name-check.swift"
  if [ ! -f "$script" ]; then
    echo "FAIL $name (no $script)"
    fail=$((fail + 1)); failed+=("$name"); continue
  fi
  # shellcheck disable=SC2086
  if ! swiftc -parse-as-library $deps "$script" -o "$OUT/$name" > "$OUT/$name.build" 2>&1; then
    echo "FAIL $name (build)"
    grep "error:" "$OUT/$name.build" | sed 's/^/     /' | sort -u | head -5
    fail=$((fail + 1)); failed+=("$name"); continue
  fi
  if "$OUT/$name" > "$OUT/$name.run" 2>&1; then
    echo "ok   $name"
    pass=$((pass + 1))
  else
    echo "FAIL $name (run)"
    tail -5 "$OUT/$name.run" | sed 's/^/     /'
    fail=$((fail + 1)); failed+=("$name")
  fi
done

echo
echo "$pass passed, $fail failed"
if [ "$fail" -gt 0 ]; then
  echo "failed: ${failed[*]}"
  exit 1
fi
