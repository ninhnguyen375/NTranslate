# SPDD Code Review: Popup UX (Round 2)

## Review Context

- **Prompt**: `spdd/prompt/ISSUE-202608252035-[Feat]-popup-ux-cache-history-vocab-config.md`
- **Prior report**: `spdd/review/ISSUE-202608252035-[Review]-popup-ux-round1.md`
- **Code Scope**: Uncommitted `git diff HEAD -- Sources/` on `feat/popup-ux-cache-history-vocab-config`
- **Files re-read in full**:
  - `Sources/translate/AppConfig.swift`
  - `Sources/translate/HistoryWindowController.swift`
  - `Sources/translate/PopoverController+Chrome.swift`
  - `Sources/translate/PopoverController+Layout.swift`
  - `Sources/translate/PopoverController+Speech.swift`
  - `Sources/translate/PopoverController+Subtranslate.swift`
  - `Sources/translate/PopoverController.swift`
  - `Sources/translate/PopoverLayoutMath.swift`
  - `Sources/translate/ReviewWindowController.swift`
  - `Sources/translate/SettingsWindowController.swift`
  - `Sources/translate/SubtranslateSection.swift`
- **Review Date**: 2026-08-25 22:17 ICT
- **Focus**: Verify RC-1…RC-4 against live code; hunt new Criticals in `currentPopoverHeight` / `reflowLayout` / `subSectionPanes` / `layoutSubSection` / ratio clamp. Important/Informational from round 1 are re-confirmed only, not re-litigated.

## Review Summary (Start Here)

| Dimension      | Status | Findings | Priority |
| -------------- | ------ | -------- | -------- |
| Requirements   | ⚠️ Partial Drift | 2 | Medium |
| Entities       | ⚠️ Partial Drift | 2 | Medium |
| Approach       | ⚠️ Partial Drift | 2 | Medium |
| Structure      | ⚠️ Partial Drift | 1 | Low |
| Operations     | ⚠️ Partial Drift | 3 | Medium |
| Norms          | ✅ Aligned | 0 | - |
| Safeguards     | ⚠️ Partial Violations | 1 | Medium |
| Intent Drift   | ⚠️ Partial Drift | 2 | Medium |
| Scope Boundary | ✅ Within Scope | 0 | - |
| RC-1…RC-4      | ✅ All Fixed | 0 remaining | - |
| New Critical   | ❌ 1 introduced | 1 | High |

**Overall Assessment**: ⚠️ Needs Attention

RC-1…RC-4 are fixed in the live tree. The RC-1 shrink-persist change over-corrects: panel height is now *only* `config.ui.height`, so a default 320pt popup cannot fit two stacked min panes and the subtranslate section overlaps chrome. That is the one remaining merge blocker.

## RC-1…RC-4 Verification

| ID | Round-1 claim | Status | Evidence |
|----|---------------|--------|----------|
| **RC-1** | `currentPopoverHeight` = `max(preferredPopoverHeight(), config.ui.height)` undoes user shrink on mouse-up | ✅ **Fixed** | `currentPopoverHeight()` is now `min(max(CGFloat(config.ui.height), 220), maxPopoverHeight())` — `PopoverController+Layout.swift:483-485`. `reflowLayout()` uses that height (`:47-49`). `finishLiveResize` writes `config.ui.height` from `panel.frame` then calls `reflowLayout()` (`:582-596`). Shrink no longer loses to content-measured preferred height. |
| **RC-2** | `mode == .learn → 0.33` ran *before* `config.ui.subSectionWidth`, so Learn ignored persisted split | ✅ **Fixed** | Order is now live ratio → saved width → Learn `0.33` → `0.5` — `PopoverController+Layout.swift:495-508`. Cold layout after a saved width uses the persisted split in Learn too. |
| **RC-3** | `layoutSubSection` shadowed its `panes` argument and recomputed | ✅ **Fixed** | `layoutSubSection` uses the `panes` parameter for `sourceCard` / divider / `resultCard` / chrome — `PopoverController+Subtranslate.swift:86-125`. No inner `let panes = subSectionPanes(...)`. Caller still computes once and passes — `PopoverController+Layout.swift:181`. |
| **RC-4** | Drag clamped `[0.2, 0.8]`, math clamped `[0.15, 0.85]` | ✅ **Fixed** | Shared `PopoverLayoutMath.splitPaneMinRatio = 0.15` / `splitPaneMaxRatio = 0.85` — `PopoverLayoutMath.swift:42-49`. Both `applyLiveMainSplitDelta` and `applyLiveSubSplitDelta` clamp with those constants — `PopoverController+Layout.swift:559-578`. |

## 🔴 Must Review (Critical)

- **NEW-C1 Panel height floor does not account for stacked sub/QA (RC-1 over-fix)**: `currentPopoverHeight()` never consults `preferredPopoverHeight()` or a stacked chrome floor. Default `config.ui.height` is 320. With a sub-section, `layoutSplitPrism` has ~204pt of body (`320 − chrome`), but `stackedMinPaneHeight * 2 + sectionGap` is `120+120+10 = 250`. `multiStackedSectionHeights` then raises `usable` to `max(minPaneHeight * count, available − gaps)` = 240 and returns two 120pt panes into a 204pt hole — sub + primary overlap the header. Opening a floating-bar subtranslate on an unresized popup is broken. — `PopoverController+Layout.swift:40-49`, `76-83`, `180-185`, `378-386`, `483-485`; `PopoverLayoutMath.swift:83-85`

## 🟡 Should Review (Important) — round 1 carry-forward

Confirmed **still present** unless noted. No re-analysis.

- **E-1** Still present — `SpeechPlaybackState.action(for:)` remains identity-only; speed is `PopoverController.activeSpeechRate`. — `PopoverController.swift:137-138`, `PopoverController+Speech.swift:34-40`
- **E-2** Still present — no `qaSectionHeight` / `learnModeCompactSource` on `AppConfig.UI`. Learn compact is still hardcoded `0.33` when no saved width. — `AppConfig.swift:30-36`, `PopoverController+Layout.swift:503-504`
- **O-1** Still present — `showReview` uses `sessionRecords`; `startReviewAll` → `startPracticeReview` loads every saved card. — `ReviewWindowController.swift:82-108`, `530-548`
- **O-2** Still present — `finishLiveResize` still `AppConfig.write(config)`, not `saveSettings()`. — `PopoverController+Layout.swift:591-595`
- **O-3** Still present in code, **runtime impact gone** — `preferredPopoverHeight()` still measures at default 0.5 split (`:452-456`) and **is no longer called** by `currentPopoverHeight()`. Dead path, not a live height bug.
- **S-1** Still present — live drag still runs full `layoutSplitPrism` per pixel (text measure skipped via `isLiveResizing`). — `PopoverController+Layout.swift:551-556`, `337-347`
- **H-1** Still present — `HistoryRowView.isSelected` `didSet`; `interiorBackgroundStyle = .normal` still the real white-on-white guard. — `HistoryWindowController.swift:19-59`

### New Important (from RC-1…RC-4)

- **NEW-I1 `preferredPopoverHeight` is orphaned**: Defined at `PopoverController+Layout.swift:452-470`, zero call sites. Prompt Operations still describe it as the persist/read path. Either wire a *stacked chrome floor* (not text-measured preferred) into `currentPopoverHeight`, or delete it and update the prompt.
- **NEW-I2 Any `finishLiveResize` writes `subSectionWidth`**: Corner-handle panel resize also persists `section.sourceCard.frame.width` (`:587-589`). A Learn session at 0.33, then a panel-only drag, locks 0.33 into Translate forever via RC-2’s “saved wins” rule. Acceptable if intended; not specified.

## 🟢 Informational (Low Risk) — round 1 carry-forward

All still true:

- Type is `AppConfig.UI`, not prompt name `UISettings`.
- `DragHandleView` is file-level in `PopoverController+Layout.swift:4`.
- Floating-bar `updateSpeechButton(..., baseLabel: "phrase")` omits `speed`/`idleSymbol` (defaults) — `PopoverController+Subtranslate.swift:531`.
- `TranslationHistoryStore.dueReviews` / `computeStats` unchanged (not in this round’s file list; still no store diff expected).
- `splitPaneWidth(ratio: = 0.5)` keeps the even-split test valid; clamp now uses named constants.
- `ChromeLayout` max heights 720/520; `panelMinWidth`/`panelMaxWidth` present.
- Extra in-memory short-circuit in `runSubRequest` — `PopoverController+Subtranslate.swift:187-200`.

## Detailed Analysis

### Requirements Alignment

**Status**: ⚠️ Partial Drift

**Alignment**: Dual speak buttons, history row chrome, daily-new-word Settings field, floating bar → `runSubRequest`, Q&A height 0 when hidden, drag+persist of panel size (shrink now sticks).

**Scope Expansion**: Unchanged from round 1 (`liveMainSplitRatio`, in-memory cache gate).

**Scope Contraction**: `learnModeCompactSource` / `qaSectionHeight` still missing. **New**: content/sub-section no longer grows the panel; stacked body can overflow (NEW-C1).

### Entities Alignment

**Status**: ⚠️ Partial Drift

**Matched Entities**: Slow buttons, `LearningSettings`, `subSectionWidth/Height`, `HistoryRowView`, `sessionRecords` on daily review.

**Entity Drift**: E-1, E-2 unchanged.

**Unauthorized Entities**: `DragHandleView` — unchanged.

**Conservative Constraint Violations**: none.

### Approach Alignment

**Status**: ⚠️ Partial Drift

**Followed Strategies**: Cache via `reusableRecord`; history `.none` highlight; speech per-click speed; Codable defaults; **one** ratio clamp; saved split wins over Learn default.

**Approach Drift**: Persist still `AppConfig.write` not `saveSettings`. Speech state still on the controller. Live resize still full `layoutSplitPrism`. Height persist now ignores content measure entirely (Approach 3 said saved size *overrides* measured size in min-max — not that measured size is deleted).

**Unauthorized Decisions**: Unchanged plus orphaned `preferredPopoverHeight`.

### Structure Alignment

**Status**: ⚠️ Partial Drift

**Matched Structure**: History row view, Settings field, slow buttons, `splitPaneWidth` additive parameter, shared ratio constants.

**Structure Drift**: `SpeechPlaybackState` still not the speed owner. `layoutSubSection` now has a single panes source of truth (RC-3 fixed).

**Layer Violations**: none.

### Operations Alignment

**Status**: ⚠️ Partial Drift (was ❌ in round 1)

**Operation**: Cache floating bar — ✅ still aligned (`:543-551`, retry `:284-286` in Subtranslate).

**Operation**: History white-on-white — ⚠️ unchanged (H-1).

**Operation**: Resize + persist — ⚠️ RC-1 shrink persist **fixed**; NEW-C1 stacked floor missing. `saveSettings()` still not used.

**Operation**: Learn 1/3 pane — ✅ saved width now wins; `0.33` only when unset.

**Operation**: Q&A hide — ✅ `visibleQAInputHeight` (`:491-493`).

**Operation**: Daily new words — ⚠️ `showReview` ok; `startReviewAll` still practice-all (O-1).

**Operation**: Dual speak — ✅ unchanged and aligned.

### Norms Alignment

**Status**: ✅ Aligned

RC-4’s duplicate clamp literals are gone; drag and math share `splitPaneMinRatio` / `splitPaneMaxRatio`.

### Safeguards Alignment

**Status**: ⚠️ Partial Violations

**Respected**: retry bypass, no text in UISettings, Codable defaults, AppKit-only drag, `Int?` geometry, `splitPaneWidth` default, `speed: Float = 1.0`, single `AVAudioPlayer`, tortoise styling.

**Violations**:
- 🟡 Safeguard 2 (S-1) still: `layoutSplitPrism` on every drag pixel.
- 🟡 Safeguard 6 (O-2) still: resize errors via `setStatus`, not `saveSettings`.

NEW-C1 is a functional regression, not a listed safeguard text, but it breaks the stacked-pane layout the feature depends on.

## Intent Drift Analysis

### Positive Drift (Unauthorized Additions)

Unchanged from round 1 (main split drag, in-memory cache gate, `DragHandleView`, panel min/max width, `interiorBackgroundStyle`).

### Negative Drift (Missing Implementations)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| ND-1 RC-1 | — | — | **Cleared** (shrink persist works) |
| ND-2 RC-2 | — | — | **Cleared** (saved width used in Learn) |
| E-2 / qaSectionHeight / learnModeCompactSource | 🟡 | `AppConfig.swift:30-36` | Still missing |
| E-1 SpeechPlaybackState speed | 🟡 | `SpeechPlaybackState.swift` | Still missing |
| O-1 startReviewAll | 🟡 | `ReviewWindowController.swift:530-546` | Still missing |
| NEW-C1 stacked floor | 🔴 | `PopoverController+Layout.swift:483-485` | Panel does not grow/floor for sub/QA |

### Direction Drift (Divergent Approaches)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| DD-1 RC-3 panes shadow | — | — | **Cleared** |
| DD-2 auto-height vs persist | 🟡 | `PopoverController+Layout.swift:483-485` | Persist won completely; content/stacked floor discarded (over-fix) |
| DD-3 clamp mismatch | — | — | **Cleared** |
| DD-4 SpeechPlaybackState | 🟡 | `PopoverController.swift:137-138` | Unchanged |

## Implicit Decisions

Round 1 table still applies. New from this fix:

| Decision | Category | Location | AI's Choice | Risk |
|----------|----------|----------|-------------|------|
| When is height user-owned? | Algorithm | `PopoverController+Layout.swift:483-485` | Always `config.ui.height` (including factory 320), never content/stacked floor | High |
| Learn 0.33 vs saved | Algorithm | `PopoverController+Layout.swift:499-504` | Saved width always wins (round-1 recommended rule) | Medium |
| Persist sub width on any drag end | Persistence | `PopoverController+Layout.swift:587-589` | Yes, even panel-corner-only | Medium |

## Scope Boundary Check

**Status**: ✅ Within Scope

RC fixes stayed in `PopoverController+Layout.swift`, `PopoverLayoutMath.swift`, `PopoverController+Subtranslate.swift`. No new files. Settings / speech / history / review / AppConfig unchanged vs round 1.

## Race-Condition Artifacts

Round-1 Critical mix (RC-1…RC-4) is gone. Remaining mix-adjacent leftovers:

- Orphaned `preferredPopoverHeight` (Agent B’s auto-size path disconnected, not deleted) — NEW-I1
- `multiStackedSectionHeights` still *inflates* `usable` above `available` (`PopoverLayoutMath.swift:83-85`) — safe when the panel grew with content; unsafe now that the panel does not (NEW-C1)

No new duplicate declarations or signature mismatches.

## Recommended Actions

1. **Fix NEW-C1 (code)**: Keep RC-1’s “do not `max` with text-measured preferred” rule, but add a **chrome/stacked floor** to `currentPopoverHeight()`: at least `220`, and when `subSection`/`qaSection` exist, at least the padding+header+footer plus `stackedMinPaneHeight * n + sectionGap * (n-1)`. Do not bring back `max(..., preferredPopoverHeight())` — that reopens RC-1.
2. **Optional**: Stop `multiStackedSectionHeights` from returning a sum larger than `available` (`PopoverLayoutMath.swift:83-85`).
3. **NEW-I1**: Call a floor helper from `currentPopoverHeight`, or delete `preferredPopoverHeight` and `/spdd-prompt-update` Operations § resize.
4. **NEW-I2 / E-2 / O-1 / O-2 / E-1 / H-1 / S-1**: Unchanged human calls from round 1; none are merge-blocking if NEW-C1 is fixed.
5. Re-run `/spdd-code-review` after the stacked-floor patch (round 3).
