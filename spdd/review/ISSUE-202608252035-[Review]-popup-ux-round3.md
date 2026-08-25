# SPDD Code Review: Popup UX (Round 3)

## Review Context

- **Prompt**: `spdd/prompt/ISSUE-202608252035-[Feat]-popup-ux-cache-history-vocab-config.md`
- **Prior reports**: `spdd/review/ISSUE-202608252035-[Review]-popup-ux-round1.md`, `…-round2.md`
- **Code Scope**: Uncommitted `git diff HEAD -- Sources/` on `feat/popup-ux-cache-history-vocab-config`
- **Focus**: Verify NEW-C1 (`stackedLayoutFloorHeight` / `currentPopoverHeight`) without regressing RC-1; scan for new Criticals from that patch. Important/Informational from round 2 are re-confirmed only.
- **Review Date**: 2026-08-25 22:25 ICT

## Review Summary (Start Here)

| Dimension      | Status | Findings | Priority |
| -------------- | ------ | -------- | -------- |
| Requirements   | ⚠️ Partial Drift | 1 | Low |
| Entities       | ⚠️ Partial Drift | 2 | Medium |
| Approach       | ⚠️ Partial Drift | 2 | Medium |
| Structure      | ⚠️ Partial Drift | 1 | Low |
| Operations     | ⚠️ Partial Drift | 3 | Medium |
| Norms          | ✅ Aligned | 0 | - |
| Safeguards     | ⚠️ Partial Violations | 2 | Medium |
| Intent Drift   | ⚠️ Partial Drift | 2 | Medium |
| Scope Boundary | ✅ Within Scope | 0 | - |
| NEW-C1         | ✅ Fixed | 0 | - |
| RC-1           | ✅ Not regressed | 0 | - |
| New Critical   | ✅ None | 0 | - |

**Overall Assessment**: ⚠️ Needs Attention

NEW-C1 is fixed. RC-1 is not regressed (height still does not `max` with content-measured `preferredPopoverHeight()`). No new Critical. Remaining issues are the deferred Important set plus a live-drag min that is still 220 while the post-layout floor is higher.

## NEW-C1 / RC-1 Verification

| ID | Claim | Status | Evidence |
|----|--------|--------|----------|
| **NEW-C1** | Default 320pt panel cannot fit two stacked min panes; subtranslate overlaps header | ✅ **Fixed** | `stackedLayoutFloorHeight()` builds chrome + `stackedMinPaneHeight * paneCount + sectionGap * (n-1)` via the same `splitPrismHeight` formula as the panel (`PopoverController+Layout.swift:483-503`). `currentPopoverHeight()` is `min(max(saved, floor), maxPopoverHeight())` (`:505-508`). With a sub-section, `paneCount = 2` and `stackedMinPaneHeight = 120` → body 250 + chrome ≈ 366 > 320, so `reflowLayout` grows the panel instead of packing 250pt of panes into ~204pt. Floor uses **min pane slots**, not `preferredPopoverHeight()` / text measure. |
| **RC-1** | User shrink must not snap back to content-measured preferred height | ✅ **Not regressed** | `currentPopoverHeight()` still does **not** call `preferredPopoverHeight()` (`:452-470` remains unused). Saved height wins whenever it is ≥ the chrome floor. Example: user saves 500 with a sub-pane → `max(500, ~366) = 500`. Shrink from 600 → 450 stays 450. The round-1 bug (`max(preferredPopoverHeight(), saved)`) is still gone. |

**Arithmetic check (NEW-C1)**: chrome via `splitPrismHeight` = padding 14 + header 26 + headerGap 12 + footerGap 16 + bottomBar 32 + paddingBottom 16 = 116 (status 0, Q&A input 0). Two stacked mins: `120+120+10 = 250`. Floor ≈ 366. `layoutSplitPrism` leftover body at height 366 = 366 − 116 = 250, which equals `stackedBody`, so `multiStackedSectionHeights` is no longer asked to fit 250 into 204.

## 🔴 Must Review (Critical)

None.

## 🟡 Should Review (Important) — carry-forward

Confirmed **still present**. Line numbers updated where the NEW-C1 patch shifted `finishLiveResize`.

- **E-1** Still present — speed on `PopoverController.activeSpeechRate`, not `SpeechPlaybackState.action(for:identity, speed)`. — `PopoverController.swift:137-138`, `PopoverController+Speech.swift:34-40`
- **E-2** Still present — no `qaSectionHeight` / `learnModeCompactSource`. Learn `0.33` only when no saved width. — `AppConfig.swift:30-36`, `PopoverController+Layout.swift:527-528`
- **O-1** Still present — `startReviewAll` → `startPracticeReview` (all saved). — `ReviewWindowController.swift:82-108`, `530-548`
- **O-2** Still present — `AppConfig.write(config)`, not `saveSettings()`. — `PopoverController+Layout.swift:615-619`
- **O-3** Still present as dead code — `preferredPopoverHeight()` still unused (`:452-470`).
- **S-1** Still present — live drag still calls `layoutSplitPrism` per pixel. — `:575-580`
- **H-1** Still present — `HistoryRowView.isSelected` `didSet`. — `HistoryWindowController.swift:19-59`
- **NEW-I1** Still present — `preferredPopoverHeight` orphaned. Floor duty moved to `stackedLayoutFloorHeight`; the old function was not deleted.
- **NEW-I2** Still present — any `finishLiveResize` writes `subSectionWidth`. — `:611-613`

### New Important (from NEW-C1 patch)

- **NEW-I3 Live-drag min is still 220, below the chrome floor**: `applyLivePanelDelta` clamps height with `minV: 220` (`:578`). During a stacked-pane drag the panel can go under `stackedLayoutFloorHeight()` (~366) and overlap until mouse-up, when `reflowLayout` snaps up. `finishLiveResize` also **persists** the undersized `panel.frame.height` (`:609-610`) before reflow displays the floor — config can store 220 while the UI shows ~366 until the next successful drag-end above the floor. Not a reopen of NEW-C1 (steady-state layout is correct). Fix: clamp live min (and persisted height) to `stackedLayoutFloorHeight()`.

## 🟢 Informational (Low Risk) — carry-forward

All still true:

- Type is `AppConfig.UI`, not prompt name `UISettings`.
- `DragHandleView` is file-level — `PopoverController+Layout.swift:4`.
- Floating-bar `updateSpeechButton(..., baseLabel: "phrase")` omits new args — `PopoverController+Subtranslate.swift:531`.
- `dueReviews` / `computeStats` unchanged (no store edit this round).
- `splitPaneWidth(ratio: = 0.5)` + shared `splitPaneMinRatio` / `MaxRatio`.
- `ChromeLayout` max 720/520; `panelMinWidth` / `panelMaxWidth`.
- In-memory short-circuit in `runSubRequest`.

## Detailed Analysis

### Requirements Alignment

**Status**: ⚠️ Partial Drift

**Alignment**: Same as round 2, plus stacked sub/QA no longer overflows a default-height popup. User shrink above the chrome floor still persists.

**Scope Expansion**: Unchanged (`liveMainSplitRatio`, in-memory cache gate).

**Scope Contraction**: E-2 flags still missing. Single-pane shrink cannot go below ~276 (chrome + `splitMinPaneHeight` 160) even though live drag allows 220 — by design of the floor, not a requirements miss.

### Entities Alignment

**Status**: ⚠️ Partial Drift — E-1, E-2 unchanged. `stackedLayoutFloorHeight` is a layout helper, not a new domain entity.

### Approach Alignment

**Status**: ⚠️ Partial Drift

**Followed**: Floor is chrome/min-slots only; comment at `:483-484` explicitly avoids content-measured preferred (RC-1). Persist still `AppConfig.write`. Speech state still on the controller.

### Structure Alignment

**Status**: ⚠️ Partial Drift — `SpeechPlaybackState` still not the speed owner. Height floor lives in the Layout extension, appropriate.

### Operations Alignment

**Status**: ⚠️ Partial Drift

Resize persist: shrink above floor sticks; stacked open grows to floor. Q&A hide, cache, dual speak, Learn saved-width, daily `showReview` — unchanged from round 2.

### Norms Alignment

**Status**: ✅ Aligned — floor reuses `splitPrismHeight` / `stackedMinPaneHeight`; no new singleton or emoji.

### Safeguards Alignment

**Status**: ⚠️ Partial Violations

**Respected**: retry `bypassCache`, no text in UI settings, Codable defaults, AppKit drag, `speed: Float = 1.0`, single player, tortoise styling, RC-1 (no content-preferred max).

**Violations** (unchanged yellow):
- 🟡 Safeguard 2 / **S-1**: `layoutSplitPrism` on every drag pixel — `:575-580`
- 🟡 Safeguard 6 / **O-2**: resize save via `AppConfig.write` + `setStatus` — `:615-619`

## Intent Drift Analysis

### Positive Drift

Unchanged from round 1 (main split drag, in-memory cache, `DragHandleView`, panel min/max, `interiorBackgroundStyle`).

**NEW**: `stackedLayoutFloorHeight()` — authorized by round-2 recommended action, not by the original prompt.

### Negative Drift

NEW-C1 **cleared**. E-2, E-1, O-1 still open.

### Direction Drift

RC-1/RC-2/RC-3/RC-4 remain cleared. Height is user-owned **above** a chrome floor (intended). `preferredPopoverHeight` still disconnected (O-3 / NEW-I1).

## Implicit Decisions

| Decision | Category | Location | AI's Choice | Risk |
|----------|----------|----------|-------------|------|
| Floor for n=1 | Algorithm | `PopoverController+Layout.swift:485-508` | Always chrome + `stackedMinPaneHeight` (160), ≈276, not 220 | Low |
| Live-drag min | Algorithm | `:578` | Left at 220, not the floor | Medium |
| Persist then reflow | Persistence | `:609-620` | Write `panel.frame` even if below floor | Medium |

## Scope Boundary Check

**Status**: ✅ Within Scope

NEW-C1 patch is confined to `PopoverController+Layout.swift` (`stackedLayoutFloorHeight`, `currentPopoverHeight`). `PopoverLayoutMath.multiStackedSectionHeights` still inflates `usable` above `available` (`:83-85`) but is now fed enough `available` in the default stacked case.

## Recommended Actions

1. **Optional (NEW-I3)**: `applyLivePanelDelta` `minV:` and `finishLiveResize` persisted height should use `max(220, stackedLayoutFloorHeight())` so drag and disk match the post-reflow size.
2. **Optional (NEW-I1)**: Delete unused `preferredPopoverHeight()` or `/spdd-prompt-update` Operations that still name it.
3. **Human call, unchanged**: E-1, E-2, O-1 vs Safeguard 5, O-2, H-1, S-1, NEW-I2.
4. **Merge**: Unblocked on Critical. Accept the Important list or schedule a follow-up; `/spdd-sync` if the chrome-floor behavior should be written into the prompt.

## File inventory this round

| File | Delta vs round 2 |
|------|------------------|
| `PopoverController+Layout.swift` | `stackedLayoutFloorHeight()` added; `currentPopoverHeight()` takes `max(saved, floor)` |
| All other round-1/2 Swift files | No NEW-C1-related change; Important items re-confirmed in place |
