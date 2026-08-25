# SPDD Code Review: Popup UX, Cache, History Selection, Vocab Config

## Review Context

- **Prompt**: `spdd/prompt/ISSUE-202608252035-[Feat]-popup-ux-cache-history-vocab-config.md`
- **Code Scope**: Uncommitted `git diff HEAD -- Sources/` on `feat/popup-ux-cache-history-vocab-config`, plus a full read of `TranslationHistoryStore.swift` (listed in review scope; **no uncommitted changes**)
- **Files reviewed in full**:
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
  - `Sources/translate/TranslationHistoryStore.swift`
- **Review Date**: 2026-08-25 22:06 ICT
- **Special lens**: Working tree is the product of two concurrent generate runs (race). Critical severity is applied to contradictory dual implementations, discarded parameters, and persist/layout paths that fight each other.

## Review Summary (Start Here)

| Dimension      | Status | Findings | Priority |
| -------------- | ------ | -------- | -------- |
| Requirements   | ⚠️ Partial Drift | 3 | High |
| Entities       | ⚠️ Partial Drift | 3 | High |
| Approach       | ⚠️ Partial Drift | 4 | High |
| Structure      | ⚠️ Partial Drift | 2 | Medium |
| Operations     | ❌ Significant Drift | 6 | High |
| Norms          | ✅ Aligned | 1 | Low |
| Safeguards     | ⚠️ Partial Violations | 3 | High |
| Intent Drift   | ❌ Significant Drift | 8 | High |
| Scope Boundary | ✅ Within Scope | 0 | - |
| Race Artifacts | ❌ Critical mix | 6 | High |

**Overall Assessment**: ❌ Needs Rework

The speech-button swap, history selection chrome, daily-new-word Settings field, and floating-bar cache gateway are largely present. Resize persist and Learn-mode split are implemented twice with incompatible rules; those two paths will not survive a human QA pass.

## 🔴 Must Review (Critical)

- **RC-1 Panel height persist is undone on mouse-up**: Live drag can shrink the panel, but `finishLiveResize` then calls `reflowLayout()` → `currentPopoverHeight()` which takes `max(preferredPopoverHeight(), config.ui.height)`. Shrink never sticks; the panel snaps back to content-measured height. — `PopoverController+Layout.swift:40-45`, `479-480`, `570-584`
- **RC-2 Learn compact ratio vs saved sub-split are mutually exclusive**: `subSectionPanes` prefers `mode == .learn → 0.33` *before* `config.ui.subSectionWidth`. A Learn-pane drag is written to config, then ignored on the next cold layout. — `PopoverController+Layout.swift:491-504`
- **RC-3 Dual sub-pane layout implementations**: `layoutSplitPrism` computes `subSectionPanes(...)` and passes it into `layoutSubSection`, which immediately shadows the parameter and recomputes. Smoking-gun race leftover. — `PopoverController+Layout.swift:176-177` vs `PopoverController+Subtranslate.swift:86-95`
- **RC-4 Live-drag clamp vs math clamp disagree**: Drag clamps ratio to `[0.2, 0.8]`; `splitPaneWidth` clamps to `[0.15, 0.85]`. Same quantity, two contracts. — `PopoverController+Layout.swift:555-558`, `562-566` vs `PopoverLayoutMath.swift:44-48`

## 🟡 Should Review (Important)

- **E-1 `SpeechPlaybackState` was not extended with speed**: Prompt entity `action(for:identity, speed)` does not exist. Speed lives as a parallel `activeSpeechRate` on `PopoverController`, while `speechState.action(for:)` remains identity-only. — `PopoverController.swift:137-138`, `PopoverController+Speech.swift:34-40`; `SpeechPlaybackState.swift:91-101` (unmodified)
- **E-2 Missing `UISettings.qaSectionHeight` and `learnModeCompactSource`**: Entities diagram lists both; code never added them. Compact Learn is hardcoded `0.33`. Q&A height is derived from `qaInputField.isHidden`, not persisted. — prompt Entities vs `AppConfig.swift:30-36`, `PopoverController+Layout.swift:487-504`
- **O-1 `startReviewAll` ignores `dailyNewWordLimit`**: Daily session (`showReview`) is filtered; "Review All Saved Cards" still loads every saved card. Prompt Operations name `startReviewAll` explicitly. (Safeguard 5 also says do not cap saved-word practice — human must pick.) — `ReviewWindowController.swift:82-108`, `530-548`
- **O-2 Persist path bypasses `saveSettings()`**: Prompt Structure/Operations say call existing `saveSettings()` (`PopoverController+Menu.swift:180`). Resize writes via `AppConfig.write(config)` and does not reload translator/settings window. Error *is* surfaced via `setStatus`. — `PopoverController+Layout.swift:579-583`
- **O-3 `preferredPopoverHeight` ignores live/saved main split**: Height is measured at default 0.5 split while on-screen layout uses `liveMainSplitRatio`. — `PopoverController+Layout.swift:448-465` vs `51-58`
- **S-1 Safeguard 2 only half-honored**: Drag avoids `reflowLayout()` and skips *text* measure via `isLiveResizing`, but still runs full `layoutSplitPrism` (chrome, buttons, stacked allocation) on every pixel. — `PopoverController+Layout.swift:547-553`, `333-345`
- **H-1 `HistoryRowView.isSelected` `didSet` may not fire**: AppKit often sets selection without going through an overridden stored property. Text-color fix via `interiorBackgroundStyle = .normal` is the real white-on-white guard; accent border may never update. — `HistoryWindowController.swift:19-59`

## 🟢 Informational (Low Risk)

- Existing type is `AppConfig.UI`, not prompt name `UISettings` — conservative reuse, correct.
- `DragHandleView` is a file-level AppKit view in `PopoverController+Layout.swift:4` rather than a nested type.
- Floating-bar `updateSpeechButton` call omits new `speed`/`idleSymbol` args and relies on defaults — `PopoverController+Subtranslate.swift:532`.
- `TranslationHistoryStore.dueReviews` / `computeStats` unchanged, matching Approach 5.
- `splitPaneWidth` gained `ratio: CGFloat = 0.5`; existing test `splitPaneWidthDividesEvenlyWithOddRemainderToRight` still valid.
- `ChromeLayout.splitMaxPaneHeight` 420→720, `splitMaxStackedPaneHeight` 300→520, plus new `panelMinWidth`/`panelMaxWidth`.
- Extra in-memory short-circuit in `runSubRequest` (same pane + same text) sits *in front of* `reusableRecord` — helpful, not specified.

## Detailed Analysis

### Requirements Alignment

**Status**: ⚠️ Partial Drift

**Alignment**:
- Floating bar Translate/Learn go through `runSubRequest(..., bypassCache: false)` and `reusableSubRecord` → `historyStore.reusableRecord`. Retry still uses `bypassCache: true`.
- History row uses custom `HistoryRowView` with highlight style `.none`, forced `.labelColor`, and `interiorBackgroundStyle = .normal`.
- Dual speak buttons (1.0x / 0.5x, tortoise symbol) on main pane and sub-section; global `speechRatePopUp` removed.
- `LearningSettings.dailyNewWordLimit` (default 12) + Settings "Daily New Words" field; daily review session filters new cards.
- Q&A input height is `0` when `qaInputField.isHidden`.
- Panel + split drag handles exist; max pane heights increased.

**Scope Expansion**:
- Main-pane split is also user-draggable (`liveMainSplitRatio`) — prompt only required panel corner handle + sub `splitDivider`.
- In-memory same-request short-circuit in `runSubRequest` beyond `reusableRecord`.

**Scope Contraction**:
- User-owned panel *shrink* does not persist (RC-1).
- Saved sub-split is ignored in Learn mode (RC-2).
- No `learnModeCompactSource` / `qaSectionHeight` config flags.

### Entities Alignment

**Status**: ⚠️ Partial Drift

**Matched Entities**:
- `SubtranslateSection` slow buttons, `generation`, `mode`, `recordID`.
- `PopoverController` slow buttons, `subGeneration`, `runSubRequest`, `playSpeech(identity, speed)`.
- `AppConfig.learning.dailyNewWordLimit`; `UI.subSectionWidth` / `subSectionHeight` as `Int?`.
- `HistoryRowView` + `tableView(_:rowViewForRow:)`.
- `ReviewWindowController.sessionRecords` applied from `showReview`.

**Entity Drift**:
- `SpeechPlaybackState`: prompt adds `activeIdentity`, `activeSpeechRate`, `action(for:identity, speed)`. Actual struct is still identity-only (`SpeechPlaybackState.swift:29-102`). Speed is a sibling field on the controller.
- `UISettings` named `AppConfig.UI` (pre-existing). Missing `qaSectionHeight`, `learnModeCompactSource`.

**Unauthorized Entities**:
- `DragHandleView` (`PopoverController+Layout.swift:4-37`) — reasonable AppKit helper, not in the diagram.

**Conservative Constraint Violations**: none. Existing `AppConfig.UI` was extended, not replaced.

### Approach Alignment

**Status**: ⚠️ Partial Drift

**Followed Strategies**:
- Cache: reuse `historyStore.reusableRecord`; no new cache store. Floating bar does not call `translator.*` directly.
- History: custom `NSTableRowView`, `selectionHighlightStyle = .none`, labels stay `.labelColor`.
- Speech: copy Review-window pattern (per-click `speed`, stop then replay, cache keyed by `SpeechIdentity`, `AVAudioPlayer.enableRate` / `.rate`, `translator.speak(..., speed: 1.0)`).
- Learning limit applied at session build time, not inside `dueReviews` / `applySRSGrade`.
- Codable defaults via `decodeIfPresent`.

**Approach Drift**:
- Persist: expected `saveSettings()` → actual `AppConfig.write`.
- Speech state: expected extend `SpeechPlaybackState` → actual `activeSpeechRate` on `PopoverController` (mirrors Review controller’s parallel fields, not the prompt entity).
- Learn compact: expected optional config flag + `splitPaneWidth(ratio:)` → actual hardcoded `0.33` that shadows saved width.
- Live resize: expected throttle to frame-only during drag → actual full `layoutSplitPrism` with a text-measure short-circuit.

**Unauthorized Decisions**:
- `liveMainSplitRatio` / `liveSubSplitRatio` session state, never encoded as ratios.
- `DragHandleView` mouseDown/Dragged/Up instead of `NSPanGestureRecognizer` (both allowed by Approach; one was chosen).
- Extra in-memory cache gate in `runSubRequest` (`PopoverController+Subtranslate.swift:188-200`).

### Structure Alignment

**Status**: ⚠️ Partial Drift

**Matched Structure**:
- `HistoryWindowController` gained `tableView(_:rowViewForRow:)`.
- `HistoryRowView: NSTableRowView`.
- `LearningSettings` nested Codable on `AppConfig`.
- Floating bar → `runSubRequest`.
- Settings populate/save `workingConfig.learning.dailyNewWordLimit`.
- `speechRatePopUp` removed from chrome; slow buttons added to main and sub headers.
- `PopoverLayoutMath.splitPaneWidth` additive default parameter.

**Structure Drift**:
- `SpeechPlaybackState` not the owner of speed (Structure item 7: Speech.swift is the only playback logic — true — but entity/state split does not match).
- `DragHandleView` introduced as a shared UI primitive; `SubtranslateSection.splitDivider` type changed `NSView` → `DragHandleView`.

**Layer Violations**: none. Layout math stays in `PopoverLayoutMath`; persistence stays in `AppConfig` / store.

### Operations Alignment

**Status**: ❌ Significant Drift

**Operation**: Sửa lỗi cache floating selection bar
- **Signature**: ✅ `runSubRequest(text:mode:bypassCache:)` unchanged in spirit (`bypassCache: Bool = false`)
- **Logic Steps**: ✅ 2/2 entry points (`floatingTranslateClicked` / `floatingLearnClicked`) call `runSubRequest(..., bypassCache: false)` — `PopoverController+Subtranslate.swift:543-551`
- **Validation**: ✅ `retrySubRequest` still `bypassCache: true` — `:284-286`
- **Error Handling**: ✅ unchanged
- **Extra Logic**: in-memory same-text short-circuit (`:188-200`) plus `reusableSubRecord` (`:222-230`, `:256-282`)
- **Missing Logic**: no Proofread button on the floating bar (prompt mentioned tracing Proofread; chrome never had one)

**Operation**: Sửa lỗi màu trắng khi chọn record lịch sử
- **Signature**: ✅ `HistoryRowView`, `rowViewForRow`
- **Logic Steps**: ⚠️ 3/4 — highlight `.none`, labels `.labelColor`, custom border on select; `isSelected` `didSet` may not run (H-1)
- **Validation**: n/a (needs visual QA light/dark)
- **Error Handling**: n/a

**Operation**: Resize kéo thả + lưu settings
- **Signature**: ✅ `subSectionWidth`/`Height` `Int?` on `AppConfig.UI`
- **Logic Steps**: ❌ 3/5 — handles exist, max heights raised, live drag works; persist of *shrink* lost (RC-1); Learn saved width lost (RC-2); `saveSettings()` not used (O-2)
- **Validation**: ⚠️ clamp exists but two ranges (RC-4)
- **Error Handling**: ✅ `do/catch` + `setStatus("Settings failed: …")`

**Operation**: Learn mode thu hẹp raw text
- **Signature**: ✅ `splitPaneWidth(..., ratio: = 0.5)`
- **Logic Steps**: ⚠️ 1/2 — Learn uses `0.33`; translate/proofread default `0.5` *unless* saved width or live ratio overrides. Saved width is applied to non-Learn only, so Learn never reads persistence.

**Operation**: Thu gọn Q&A khi ẩn
- **Signature**: ✅ `visibleQAInputHeight` → `splitPrismHeight(qaInputHeight:)`
- **Logic Steps**: ✅ `qaInputField.isHidden ? 0 : ChromeLayout.qaInputHeight` — `PopoverController+Layout.swift:64`, `462`, `487-489`

**Operation**: Cấu hình số từ học mỗi ngày
- **Signature**: ✅ `LearningSettings`, Settings field, `sessionRecords`
- **Logic Steps**: ⚠️ 4/5 — `showReview` filtered; `startReviewAll` is practice-all and unfiltered (O-1); `dueReviews`/`applySRSGrade` untouched
- **Validation**: ✅ formatter `minimum: 1`, `max(1, …)` in decoder/init/collect, `validationIssues`
- **Error Handling**: ✅ Settings `present(error)` alert on save

**Operation**: 2 nút speak chậm/mặc định
- **Signature**: ✅ `playSpeech` / `loadAndPlaySpeech` / `startPlayback` take `speed: Float = 1.0`
- **Logic Steps**: ✅ 7/8 call sites (main + sub × source/result × normal/slow). Floating bar remains 1.0x only (not in the 4-position verify list).
- **Extra Logic**: `idleSymbol` parameter on `updateSpeechButton`
- **Missing Logic**: `SpeechPlaybackState.action(for:identity, speed)` never added; comparison is `abs(activeSpeechRate - speed) < 0.01` outside the state machine

### Norms Alignment

**Status**: ✅ Aligned

**Followed Norms**:
- New drag handles set `accessibilityName` / `setAccessibilityLabel` (`DragHandleView.viewDidMoveToWindow`, `configureResizeHandles`).
- No new singleton; `config` / `historyStore` injection unchanged.
- Config write wrapped in `do/catch` with `setStatus`.
- `dailyNewWordLimit >= 1`; UI English; no emoji.
- No new SPM dependency.
- Speech selectors use `configureIconButton` + tortoise / speaker.wave.2.

**Norm Violations**:
- **Clamp constants duplicated** rather than shared with `ChromeLayout` / `PopoverLayoutMath` — `PopoverController+Layout.swift:558` vs `PopoverLayoutMath.swift:46`. Stylistic until it causes RC-4.

### Safeguards Alignment

**Status**: ⚠️ Partial Violations

**Respected Safeguards**:
1. Retry still `bypassCache: true`.
3. `UISettings` stores geometry ints + learning int only — no translation text.
4. Old JSON: `decodeIfPresent` for `subSectionWidth/Height`, whole `learning` object, `dailyNewWordLimit`.
5. History list / `isSaved` counts are not capped; only `showReview` session new-cards are.
7. AppKit-only drag (`NSEvent` mouse tracking on `NSView`).
8. `Int?` pixel fields.
9. `splitPaneWidth` default `ratio: 0.5` — existing test still compiles conceptually.
10. `speed: Float = 1.0` defaults on play/load/start.
11. `stopCurrentSpeech()` / `audioPlayer?.stop(); audioPlayer = nil` before a new player — `PopoverController+Speech.swift:170-173`, `207-216`.
12. Slow buttons share `configureIconButton` styling; tortoise vs speaker.wave.2.

**Violations**:
- 🟡 **Safeguard 2**: Live resize still executes full `layoutSplitPrism` per mouse-drag event, not frame-only. Text measure is skipped, chrome layout is not. — `PopoverController+Layout.swift:547-567`
- 🟡 **Safeguard 6**: Resize errors use `setStatus`, not the `saveSettings()` path (which also rolls back API key). Disk-full on resize will not refresh Settings UI. Message exists, so not silent-fail — partial.
- 🟡 **Safeguard 5 / Operations clash**: `startReviewAll` loads all saved cards (`ReviewWindowController.swift:538-546`). If the prompt’s naming is taken literally this is a miss; if Safeguard 5 (“do not limit saved words”) is taken literally this is correct. Needs a human call.

## Intent Drift Analysis

### Positive Drift (Unauthorized Additions)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| PD-1 | 🟡 | `PopoverController.swift:140-141`, `PopoverController+Layout.swift:555-560` | Main-pane split is user-resizable via `liveMainSplitRatio`; not persisted to `AppConfig.UI`. |
| PD-2 | 🟢 | `PopoverController+Subtranslate.swift:188-200` | In-memory “already showing this phrase” gate in front of `reusableRecord`. |
| PD-3 | 🟢 | `PopoverController+Layout.swift:4-37` | New `DragHandleView` helper class. |
| PD-4 | 🟢 | `PopoverController.swift:38-40` | New `panelMinWidth` 480 / `panelMaxWidth` 1280 / `resizeHandleSize` 14. |
| PD-5 | 🟢 | `HistoryWindowController.swift:24` | `interiorBackgroundStyle = .normal` (not in prompt; actually the strongest white-on-white fix). |

### Negative Drift (Missing Implementations)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| ND-1 | 🔴 | `PopoverController+Layout.swift:479-480` | User shrink of panel height is not the stored truth after mouse-up. |
| ND-2 | 🔴 | `PopoverController+Layout.swift:497-500` | Persisted `subSectionWidth` unused when `mode == .learn`. |
| ND-3 | 🟡 | prompt Entities / `AppConfig.swift:30-36` | No `qaSectionHeight`, no `learnModeCompactSource`. |
| ND-4 | 🟡 | `SpeechPlaybackState.swift:91-101` | No `action(for:identity, speed)`; speed not part of playback state struct. |
| ND-5 | 🟡 | `ReviewWindowController.swift:530-546` | `startReviewAll` not passed through `sessionRecords`. |
| ND-6 | 🟡 | `PopoverController+Layout.swift:579-580` vs Menu.swift:180 | Resize does not call `saveSettings()`. |

### Direction Drift (Divergent Approaches)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| DD-1 | 🔴 | `PopoverController+Layout.swift:176-177` + `PopoverController+Subtranslate.swift:95` | Two layout authors: caller computes panes, callee throws them away. |
| DD-2 | 🔴 | `PopoverController+Layout.swift:40-45` vs `547-584` | Auto-height (`max(preferred, saved)`) vs user-owned live frame. |
| DD-3 | 🟡 | `PopoverController+Layout.swift:558` vs `PopoverLayoutMath.swift:46` | Ratio clamp `[0.2,0.8]` vs `[0.15,0.85]`. |
| DD-4 | 🟡 | `PopoverController.swift:137-138` vs prompt entity | Speed tracked on the controller, not `SpeechPlaybackState`. |

## Implicit Decisions (AI Judgment Points)

The following decisions were made without explicit guidance in the prompt. These require human validation:

| Decision | Category | Location | AI's Choice | Risk |
|----------|----------|----------|-------------|------|
| New-card ordering | Algorithm | `ReviewWindowController.swift:106-107` | `due.filter(isNew)` then `prefix(limit)` — store order, not timestamp/due | Medium |
| `isNew` predicate | Algorithm | `ReviewWindowController.swift:100-101` | `dueDate == nil \|\| interval == 0` | Low (`applySRSGrade` always sets interval ≥ 1) |
| Panel resize cursor | UI | `PopoverController+Layout.swift:508` | `.crosshair` (split uses `.resizeLeftRight`) | Low |
| Live ratio floor/ceiling | Config | `PopoverController+Layout.swift:558` | 0.2…0.8, not the math layer’s 0.15…0.85 | Medium |
| Persist via `AppConfig.write` | Persistence | `PopoverController+Layout.swift:580` | Skip `saveSettings` reload/keychain dance | Medium |
| Learn ratio constant | Config | `PopoverController+Layout.swift:498` | Hardcoded `0.33` instead of settings flag | High (fights persist) |
| `currentPopoverHeight` still `max(preferred, saved)` | Algorithm | `PopoverController+Layout.swift:479-480` | Content auto-size wins over user shrink | High |
| `DragHandleView` tracking | Algorithm | `PopoverController+Layout.swift:23-36` | `mouseDown/Dragged/Up` + screen deltas, not a tracking loop | Low (AppKit delivers dragged/up to the mouse-down view) |
| Prefetch/API speak speed | API | `PopoverController+Speech.swift:117`, `:181` | Always `translator.speak(..., speed: 1.0)` — matches prompt | Low |
| History selection chrome | UI | `HistoryWindowController.swift:50-53` | 1.5pt accent border + 8% fill; text colors unchanged | Low |

## Scope Boundary Check

**Status**: ✅ Within Scope

**In-Scope Components**: 12 files read; 11 files changed under `Sources/translate/` (430 insertions / 106 deletions). `TranslationHistoryStore.swift` read in full, **zero diff** — matches Approach 5 (“do not change dueReviews/computeStats scheduling”).

**Boundary Crossings**: none in `Sources/`. Unrelated dirty tree (`NTranslate.app` binary/Info.plist) is outside this review’s Sources scope.

Related but unmodified, correctly so:
- `SpeechPlaybackState.swift` — should have been touched per Entities; omission is drift, not an out-of-scope edit.
- `PopoverController+Menu.swift` `saveSettings` — not called from resize.
- `Tests/translateTests/translateTests.swift` — `splitPaneWidth` default keeps the even-split test valid.

## Race-Condition Artifacts

This section is the extra pass requested for the dual-generate working tree. No duplicate *property* declarations or uncompilable signature mismatches were found — the two runs appear to have merged at the file level rather than leaving `<<<<<<` markers. The damage is **semantic overlap**: two complete solutions for the same operation left stacked.

| ID | Severity | Evidence | Why this looks like a mix |
|----|----------|----------|---------------------------|
| RC-1 | 🔴 | `currentPopoverHeight` = `max(preferredPopoverHeight(), config.ui.height)` after `finishLiveResize` writes the dragged size and immediately `reflowLayout()` | Agent A: user-owned `panel.frame` + persist. Agent B: keep pre-existing content-driven height. Both survived. |
| RC-2 | 🔴 | `if live { } else if mode == .learn { 0.33 } else if saved width { }` | Agent A: persist `subSectionWidth`. Agent B: Learn 1/3 compact. Combined with `if/else` so compact always wins. |
| RC-3 | 🔴 | `layoutSubSection(..., panes: subSectionPanes(...))` then `let panes = subSectionPanes(...)` shadows the argument | Agent A added a panes parameter to the signature. Agent B kept internal computation. Both copies remain. |
| RC-4 | 🔴 | Drag `clamp(..., 0.2, 0.8)` vs `splitPaneWidth` `clamp(..., 0.15, 0.85)` | Two independent clamp literals for one ratio. |
| RC-5 | 🟡 | `updateSpeakButtons` passes `speed`/`idleSymbol`; `updateFloatingSelectionBar` still calls `updateSpeechButton(..., baseLabel: "phrase")` only | Speech signature update applied to the primary path, not the floating-bar refresh path (defaults save compile). — `PopoverController+Speech.swift:6-16` vs `PopoverController+Subtranslate.swift:532` |
| RC-6 | 🟡 | `SpeechPlaybackState` untouched; `activeSpeechRate` added next to `speechState` on `PopoverController` | Agent A followed ReviewWindowController’s parallel fields. Prompt asked to extend the shared state type. Both models coexist. |

**Not found** (explicitly checked):
- Duplicate `func playSpeech` / `func runSubRequest` / `var speakSourceSlowButton`
- Leftover `speechRatePopUp` / `speechRateChanged` / `speechRate` computed property (removed cleanly from `PopoverController.swift`)
- Call sites still reading a removed `speechRate` global
- `bypassCache` default flipped to `true`

## Recommended Actions

1. **Fix RC-1 (code)**: Decide whether panel size is user-owned or content-owned. If user-owned after a drag, `currentPopoverHeight()` / `reflowLayout()` must use the saved frame (clamped) and **not** `max` with a freshly measured preferred height. Clear `isLiveResizing` then layout from `config.ui.width/height` only.
2. **Fix RC-2 (code + prompt)**: Encode a single rule, e.g. “saved ratio wins; Learn default `0.33` only when `subSectionWidth == nil`”, *or* persist a dedicated `learnModeCompactSource` flag as the Entities section specified.
3. **Fix RC-3 (code)**: Delete the inner `let panes = subSectionPanes(...)` in `layoutSubSection` and honor the caller’s `panes` argument (or stop passing it). One function, one source of truth.
4. **Fix RC-4 (code)**: One clamp helper (or pass already-clamped ratios into `splitPaneWidth` without a second clamp).
5. **Human call on `startReviewAll`**: Either run it through `sessionRecords` (Operations) or document practice-all as exempt (Safeguard 5) and update the prompt via `/spdd-prompt-update`.
6. **Human call on `SpeechPlaybackState`**: Extend it with speed (prompt) or accept controller-level `activeSpeechRate` and sync the prompt via `/spdd-sync`.
7. **Optional prompt update**: Drop `qaSectionHeight` / `learnModeCompactSource` if the hardcoded Q&A hide + Learn 0.33 behavior is accepted; otherwise implement the fields.
8. **Do not merge** until RC-1…RC-3 are resolved — resize/Learn split is a user-visible contract failure, not a polish item.

## File-level inventory (what landed)

| File | Role in this change |
|------|---------------------|
| `AppConfig.swift` | `UI.subSectionWidth/Height`, `LearningSettings`, decoder defaults, validation |
| `HistoryWindowController.swift` | `HistoryRowView`, `rowViewForRow`, forced label colors |
| `PopoverController.swift` | Slow buttons, `activeSpeechRate`, live-resize state, `DragHandleView` divider, raised max heights, `speechRatePopUp` removed |
| `PopoverController+Chrome.swift` | Slow button configure/add, resize handle added to chrome |
| `PopoverController+Layout.swift` | `DragHandleView`, live resize, `visibleQAInputHeight`, `subSectionPanes`, persist |
| `PopoverController+Speech.swift` | Per-call `speed`, dual-button UI, stop-then-play |
| `PopoverController+Subtranslate.swift` | Slow buttons, cache short-circuit, floating bar → `runSubRequest`, panes shadow |
| `PopoverLayoutMath.swift` | `splitPaneWidth` `ratio` parameter |
| `ReviewWindowController.swift` | `sessionRecords` on `showReview` only |
| `SettingsWindowController.swift` | Daily New Words field populate/save |
| `SubtranslateSection.swift` | Slow buttons, `splitDivider: DragHandleView` |
| `TranslationHistoryStore.swift` | Unchanged (as specified) |
