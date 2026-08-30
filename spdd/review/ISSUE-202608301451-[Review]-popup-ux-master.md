# SPDD Code Review: Popup UX Master (P0–P5)

## Review Context

- **Prompt**: `spdd/prompt/ISSUE-202608301438-[Feat]-popup-ux-master.md`
- **Code Scope**: Uncommitted `git diff HEAD` on `Sources/translate` + listed files (16 files, +963/−175). `Tests/translateTests/translateTests.swift` unchanged. `LanguageDetector.swift`, `ActionRowSection.swift`, `PopoverLayoutMath.swift` unchanged.
- **Review Date**: 2026-08-30 15:10 ICT
- **Method**: Full prompt read; CodeGraph + fff; complete read of listed sources; git diff vs HEAD.

Prompt is a valid REASONS-Canvas master (R/E/A/S/O/N/S). Contract is wave-isolated P0→P5; working tree implements all waves in one change.

## Review Summary (Start Here)

| Dimension      | Status     | Findings | Priority |
| -------------- | ---------- | -------- | -------- |
| Requirements   | ⚠️ Partial Drift | 3 | High |
| Entities       | ⚠️ Partial Drift | 2 | Medium |
| Approach       | ⚠️ Partial Drift | 2 | High |
| Structure      | ✅ Aligned | 0 | - |
| Operations     | ⚠️ Partial Drift | 6 | High |
| Norms          | ✅ Aligned | 0 | - |
| Safeguards     | ❌ Critical Violations | 2 | High |
| Intent Drift   | ⚠️ Partial Drift | 5 | High |
| Scope Boundary | ⚠️ Minor Boundary Crossing | 1 | Medium |

**Overall Assessment**: ❌ Needs Rework

High-risk is **not** clear: **2 🔴**. P0 stream can drop UTF-8 (Vietnamese) from both live text and the committed result. Sub-translate unclosed JSON is shown as a normal success, not raw+error.

## 🔴 Must Review (Critical)

- **C-1 SSE UTF-8 chunk drop loses tokens (and the final result)** — `Sources/translate/Translator.swift:683-705`  
  Prompt P0: parse every `data:` line, accumulate `delta.content`, complete with that text / `translationResult`.  
  Code decodes **each TCP chunk** with `String(data: data, encoding: .utf8)` and `return`s if that chunk is not valid UTF-8 by itself. A multi-byte character split across packets (common for Vietnamese) drops the whole chunk from `lineRemainder` / `accumulated`. `buffer` still has the bytes, but when `sawSSE` is true completion uses `accumulated` only (`:290-297`) — so the committed translation is truncated, not repaired.  
  **Fix**: keep an undecoded `Data` remainder; decode only complete UTF-8; on complete, if `sawSSE`, either reparse `buffer` or merge remainder before finishing.

- **C-2 Sub-translate unclosed JSON treated as success** — `Sources/translate/PopoverController+Subtranslate.swift:380-383`  
  Prompt Approach §1 / P0: if translate JSON cannot close, keep raw + `ResultStyle.error` — do not invent a translation. Main path does this (`PopoverController+Translate.swift:300-303`, `style: .error`).  
  Sub path calls `setSubResultText(section, lastStreamedSub)` with no error style. `setSubResultText` then uses `resultStyle(for:)` (`:150-162`); raw `{...` / ` ``` ` is `.normal`, so incomplete JSON is markdown-rendered as a finished result.  
  **Fix**: `setSubResultText(..., streaming: false)` plus an error style (or pass `ResultStyle.error` through), matching main `finishTextTranslation`.

## 🟡 Should Review (Important)

- **I-1 Wave isolation / one-shot dump** — working tree vs prompt Requirements + Safeguard 12  
  Prompt: implement P0→P5 as independent PRs; do not ship everything in one PR; do not start later waves until confirmed. Diff covers stream/Stop/overlay (P0), setup/Retry/Test connection (P1), focus/contrast/VO (P2), tooltips/pin/ISO (P3), hint/menubar/menu (P4), Settings tabs (P5) together.  
  **Fix**: split PRs per wave, or record user authorization of a combined drop in the prompt.

- **I-2 Empty-from-hotkey omits real hotkey** — `PopoverController+Translate.swift:77` + `PopoverController+Menu.swift:653`  
  P1/P4: empty success uses `emptySelectionGuidance(hotkey: config.hotkey.displayString)`. Menu-open path does (`+Menu.swift:248`). `beginAtCursor` no-selection calls `showEmptySelectionPanel()` which defaults to the static string without `displayString`.  
  **Fix**: `showEmptySelectionPanel(message: PopoverFeedback.emptySelectionGuidance(hotkey: config.hotkey.displayString))`.

- **I-3 Status overlay shares the language-control slot** — `PopoverController+Layout.swift:135-154`  
  P0: status overlays the header, no height jump (`statusHeight: 0` is correct). Status frame starts at `titleLabel.maxX + 8` and spans to the chrome icons — the same band as source/swap/target. Language buttons are added later, so they paint on top. Status is often unreadable (VoiceOver still announces).  
  **Fix**: overlay title (or a reserved strip above languages), or hide/shrink language controls while status is visible — still without `reflowLayout()` on hide/show.

- **I-4 QA failure has no in-pane Retry** — `PopoverController+QA.swift:229-235`  
  P1: failure in `+Translate` / `+Actions` / `+QA` shows error text **and** visible Retry. QA marks `failed: true` (red) only.  
  **Fix**: Retry control on the failed turn (reuse `retryRequest` / a QA-specific retry).

- **I-5 Sub pane still `focusRingType = .none`** — `PopoverController+Subtranslate.swift:30,45`  
  P2: input/result/QA (and their scroll views) use `.default`. Main + QA were updated; sub source/result and scrolls were not.  
  **Fix**: set `.default` on sub text views and scroll views.

- **I-6 Menubar due signal is tooltip-only** — `PopoverController+Menu.swift:119-126`  
  P4: `statusItem.button` **image/tooltip** when `dueCount > 0`; acceptance: due cards visible on the menubar with the panel closed. Code sets tooltip and the in-panel `reviewBadgeLabel`; status-item image stays the generic translate icon (`PopoverController.swift:234-236`).  
  **Fix**: badge or distinct image on `statusItem.button` when `dueCount > 0`; clear when 0.

## 🟢 Informational (Low Risk)

- **N-1** `StreamDelta` (Entities) was not added; `StreamCollector` + `onPartial(String)` implements the same flow. Conservative (no extra wrapper).
- **N-2** `RequestScope` / `inFlightScope` added (not on the entity diagram). Matches Approach “one `inFlightTask`, cancel the right generation.”
- **N-3** After Stop with a partial, `isCopyableResult` without `isStreaming` can treat prose as copyable (`PopoverFeedback.swift:57-68`). Prompt only forbids copy **during** stream.
- **N-4** `finishRequest` may VoiceOver “Translation finished” after Stop if the leftover string looks `.normal` (`+Status.swift:82-84`).
- **N-5** `testConnection` uses `.imageSearch` + `"Reply with the single word OK."` (`Translator.swift:588-591`) — one-shot, no history; mode reuse is implicit.
- **N-6** Learning Progress still opens an NSAlert (`+Menu.swift:152-159`) in addition to the disabled stats line + `Learning Progress…` item. Extra, not a title-suffix regression.
- **N-7** “Check for Updates...” still uses `...` (`+Menu.swift:72`). P4 ellipsis rule named Learning Progress only.
- **N-8** Prompt variable lines are `Variables: {{...}}` (`SettingsWindowController.swift:413`), not a full English sentence. P5 intent is met.
- **N-9** `showLearningStats` alert is extra surface; menu contract (disabled line + action + `…`) is implemented (`+Menu.swift:57-64,130-132`).

## Detailed Analysis

### Requirements Alignment

**Status**: ⚠️ Partial Drift

**Alignment**: Popup stays AppKit / Liquid Glass. Streaming + Stop + overlay status; setup buttons + Retry + Test connection; focus rings (main/QA), 11pt floor, contrast bump, Reduce Transparency, VoiceOver; clean action titles + tooltips; pin persist; ISO pane codes; subtranslate one-shot hint; Settings General/Advanced + hotkey conflict; English UI, no emoji.

**Scope Expansion**: All waves landed in one working tree (prompt: one wave per PR). Extra Learning Progress alert. `RequestScope` / setup buttons as new controller state.

**Scope Contraction**: Hotkey empty state missing `displayString`. QA Retry missing. Sub focus rings unchanged. Menubar due image missing. Stream UTF-8 / sub JSON error (see Critical).

### Entities Alignment

**Status**: ⚠️ Partial Drift

**Matched Entities**: `Translator` (`inFlightTask`, `request(..., onPartial:)`, `cancelInFlight()`); `PopoverController` (`requestGeneration`, `isRequestInFlight`, `qaTargetsSub`, `mainActionRow`, `subSection`, `statusLabel`, `beginRequest` / `finishRequest` / `cancelRequest` / `appendStreamedResult`); `SubtranslateSection.actionRow` + `requestInFlight`; `PopoverFeedback` (`emptySelectionGuidance`, `isCopyableResult`, `userFacingError`); `SetupIssue` (`Kind`: apiKey/url/model/accessibility/load + `Action`); `ActionRowSection` unchanged; `UISettings.rememberPin`; `TranslationHistoryStore.reusableRecord` / `appendIfAbsent` unchanged.

**Entity Drift**:
- `StreamDelta` (generation / accumulated / isFinal): not added; logic lives in `StreamCollector` + caller generation.
- `AppConfig.setupIssues` now returns `[SetupIssue]` (prompt P1); `formatSetupIssues` has both `[SetupIssue]` and `[String]` overloads.

**Unauthorized Entities**: `StreamCollector`, `RequestScope` (justified by cancel-scope). No new `ActionRowSection`. No `List`/`String` wrappers beyond `SetupIssue`.

**Conservative Constraint Violations**: None. `previewLanguagePair`, `dailyReviewLimit`, `isDictionaryTerm` kept. `PopoverLayoutMath` / floating bar not rewritten.

### Approach Alignment

**Status**: ⚠️ Partial Drift

**Followed Strategies**: `"stream": true` default; SSE `data:` + `[DONE]`; translate JSON parsed only at completion via existing `translationResult`; Learn/Proofread/Ask stream as plain then markdown at final; Stop retitles Translate (`stop.circle`); `applyEnabled` still disables Learn/Proofread/Images/Ask; floating / image / speech / `imageSearch` / `testConnection` non-stream; overlay `statusHeight: 0`; no `reflowLayout` in `setStatus`/`clearStatus`; 4s auto-clear; 30s timeout; user cancel mapped to Stopped (not red); generation guards; history written only on final; Test connection does not append records; Reduce Transparency solid fill; pin persist default false; ISO table (Portuguese → PT).

**Approach Drift**:
- Stream decode: expected incremental SSE over a byte-safe buffer → per-chunk UTF-8 (C-1).
- Status overlay: expected visible header overlay → same slot as language controls (I-3).
- Sub JSON fail: expected raw+error → raw as `.normal` (C-2).

**Unauthorized Decisions**: `StreamCollector` as URLSession delegate; `inFlightScope` to serialize main vs sub; Test connection via `.imageSearch` prompt.

### Structure Alignment

**Status**: ✅ Aligned

**Matched Structure**: No new PopoverController base class. `Translator` completion signatures kept; `onPartial` optional default nil. `ResultStyle` not given `.streaming` (`.loading` reused). `PopoverController+Status` owns overlay + announcement. Chrome/Layout own action row + header overflow. Settings Test connection → `Translator` one-shot. `updateButton` visibility from `UpdateManager`. Layers: chrome / feedback / request / persistence. No SwiftUI, no new windows.

**Structure Drift**: None material.

**Layer Violations**: None.

### Operations Alignment

**Status**: ⚠️ Partial Drift

**Operation**: Wave P0 — Translator stream + cancel  
- **Signature**: ✅ Match (`onPartial` optional; `stream` default true; `cancelInFlight`)  
- **Logic Steps**: ⚠️ 6/7 — SSE + `[DONE]` + fallback one-shot + no onPartial after HTTP fail; UTF-8 chunk drop (C-1)  
- **Validation**: ✅ Match (timeout 30s; image/speak/floating non-stream)  
- **Error Handling**: ✅ Match (`httpError` does not dump body; user-facing HTTP map)  
- **Extra Logic**: `replaceInFlight`, dedicated `URLSession` per stream  
- **Missing Logic**: Byte-safe SSE decode  

**Operation**: Wave P0 — PopoverController Stop + stream render  
- **Signature**: ✅ Match (`cancelRequest(scope:)`, `appendStreamedResult`, `beginRequest`/`finishRequest`)  
- **Logic Steps**: ⚠️ 7/8 — generation guards, throttle ~100ms, Stop title/tooltip, copyable=false while streaming; sub JSON fail style wrong (C-2)  
- **Error Handling**: ✅ Cancel → Stopped / keep partial, not red  
- **Extra Logic**: `inFlightScope` cancels the other pane’s task  
- **Missing Logic**: Error style on sub unclosed JSON  

**Operation**: Wave P0 — Status overlay  
- **Signature**: ✅ `splitPrismHeight(..., statusHeight: 0)`; param kept  
- **Logic Steps**: ⚠️ Overlay + no reflow on hide/show; collides with language controls (I-3)  
- **Missing Logic**: Visible overlay that does not sit under language buttons  

**Operation**: Wave P1 — setupIssues / empty / runtime error / Test connection  
- **Signature**: ✅ `[SetupIssue]`, `userFacingError`, `testConnection`  
- **Logic Steps**: ⚠️ 5/6 — user-facing messages, no `Error:` prefix, Open Settings / Grant Accessibility, in-pane Retry on main, Test connection in Settings  
- **Missing Logic**: Hotkey-interpolated empty from `beginAtCursor`; QA Retry  

**Operation**: Wave P2 — focus + VoiceOver + Reduce Transparency  
- **Logic Steps**: ⚠️ Main input/result/QA `.default`; language labels 11pt; review badge 10pt; Palette alphas raised; `applySplitHostChrome` opaque fill + hide `shellGlass`; announcements on status/error/Copied/finish  
- **Missing Logic**: Sub pane focus rings  

**Operation**: Wave P3 — titles/tooltips, header, pin, ISO  
- **Logic Steps**: ✅ Titles are verbs; tooltips match spec (incl. sub Ask + Images without fake hotkey); Stop title/tooltip clean; header shrinks title then language; `updateButton` hidden unless pending; `presentPanel` reads `rememberPin`; drag/toggle persist; ISO table, unknown → `??`  

**Operation**: Wave P4 — discoverability  
- **Logic Steps**: ⚠️ Empty-from-menu has hotkey; Learn/Proofread tooltips describe outcome; one-session subtranslate hint; disabled stats line + `Learning Progress…`; review badge on panel  
- **Missing Logic**: Empty-from-hotkey hotkey string; menubar **image** when due  

**Operation**: Wave P5 — Settings  
- **Logic Steps**: ✅ General = Theme, API Key, languages, length, Daily Reviews, auto-copy, simulate copy, prefetch; Advanced = URLs, model, Test connection, hotkeys, size, history; conflict live + Save blocked; prompt `{{...}}` hints; `dailyReviewLimit` name unchanged  

### Norms Alignment

**Status**: ✅ Aligned

**Followed Norms**: English UI, no emoji, SF Symbols. `swift test` not introduced. MainActor hops on every `onPartial`/completion before view mutation. Generation checks before pane writes. History only after final (`appendIfAbsent` / `upsertRecord`). Frame-based layout; chrome height via `stackedChromeOverhead` / `splitPrismHeight`. Comments only on stream JSON / overlay / ISO. `rememberPin` missing key = false (no user `config.json` rewrite required). Hotkey defaults and `ui.width` 820 unchanged.

**Norm Violations**: None at ≥80 confidence.

### Safeguards Alignment

**Status**: ❌ Critical Violations

**Respected Safeguards**:
- No new window, no SwiftUI, no rewrite of `PopoverLayoutMath` / `ActionRowSection` / floating bar.
- Image, speech, floating Quick Translate do not stream.
- Reflow throttled (~100ms or height change); status hide/show does not change panel height.
- Test connection does not log the API key; HTTP errors use status map, not raw body; `userFacingError` strips `Bearer` / `sk-` / `api_key`.
- Non-SSE endpoint falls back to one-shot `responseContent`; Stop still `task.cancel()`.
- `dailyReviewLimit` / `isDictionaryTerm` / `previewLanguagePair` / `shouldSubtranslate` / history semantics unchanged.
- Cancel is not a red error on main.
- `focusRingType = .none` remains on glass hosts (`PopoverSupport.swift:358-373`).
- Pin missing key = false; hotkey defaults unchanged; width 820 unchanged.
- `onPartial` optional; public completions preserved.
- `closePanel` cancels in-flight, increments both generations, `removeSubSection`.
- P1+ does not revert Stop / stream / overlay.

**Violations**:
- 🔴 **Safeguard 2 (stream correctness) / P0 parse**: UTF-8-split chunks dropped from `accumulated` — `Translator.swift:685`.
- 🔴 **Approach/P0 JSON**: sub unclosed JSON presented as normal result — `PopoverController+Subtranslate.swift:380-383`.
- 🟡 **Safeguard 12 (wave isolation)**: P0–P5 in one tree.

## Intent Drift Analysis

### Positive Drift (Unauthorized Additions)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| D-P1 | 🟡 | working tree | All P0–P5 in one change; prompt forbids one-PR dump |
| D-P2 | 🟢 | `+Menu.swift:152` | Learning Progress still opens NSAlert besides the menu lines |
| D-P3 | 🟢 | `Translator.swift:588` | Test connection reuses `.imageSearch` mode |

### Negative Drift (Missing Implementations)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| D-N1 | 🔴 | `Translator.swift:685` | Byte-safe SSE decode |
| D-N2 | 🔴 | `+Subtranslate.swift:380` | Raw+error on unclosed translate JSON (sub) |
| D-N3 | 🟡 | `+Translate.swift:77` | Empty state interpolates hotkey |
| D-N4 | 🟡 | `+QA.swift:229` | In-pane Retry on QA failure |
| D-N5 | 🟡 | `+Subtranslate.swift:30` | Sub focus rings `.default` |
| D-N6 | 🟡 | `+Menu.swift:119` | Menubar due **image** |

### Direction Drift (Divergent Approaches)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| D-D1 | 🟡 | `+Layout.swift:135` | Status overlay vs reserved header slot — same band as language controls |
| D-D2 | 🟢 | `Translator.swift:669` | `StreamCollector` instead of `StreamDelta` |

## Implicit Decisions (AI Judgment Points)

The following decisions were made without explicit guidance in the prompt.
These require human validation:

| Decision | Category | Location | AI's Choice | Risk |
|----------|----------|----------|-------------|------|
| SSE via URLSession delegate | Algorithm | `Translator.swift:261-306` | New session + `StreamCollector` per request | Medium (C-1) |
| One task, `inFlightScope` | Concurrency | `+Status.swift:64-114` | Main and sub cancel each other | Low |
| Test connection prompt | Config | `Translator.swift:588` | `.imageSearch` + “OK” | Low |
| Status vs languages | Layout | `+Layout.swift:135` | Same x-range, languages on top | Medium (I-3) |
| ISO table coverage | Data | `+Chrome.swift:299-352` | Fixed map; unknown `??` | Low |
| After-Stop copy | Product | `PopoverFeedback.swift:57` | Partial may be copyable | Low |
| Combined wave drop | Process | git diff | All waves at once | Medium (I-1) |

## Scope Boundary Check

**Status**: ⚠️ Minor Boundary Crossing

**In-Scope Components**: 16 modified files under `Sources/translate` (Translator, PopoverController* , PopoverFeedback, PopoverSupport, AppConfig, Settings, QA/Sub sections). Unchanged in-scope: `ActionRowSection`, `PopoverLayoutMath`, `LanguageDetector`, tests.

**Boundary Crossings**:
- Process: P0–P5 shipped together — prompt Scope/Safeguard 12. Risk: harder revert; P1+ cannot be reviewed as isolated PRs. Not an out-of-folder edit.
- No History/Review window rewrites. No `windows-app` touch.

## Recommended Actions

1. **Fix C-1 (code)**: UTF-8-safe SSE remainder (or reparse `buffer` when `sawSSE`) before any further wave polish.
2. **Fix C-2 (code)**: Sub JSON parse failure → raw + error style, same as `finishTextTranslation`.
3. **Fix I-2 (code)**: Pass `emptySelectionGuidance(hotkey:)` into `showEmptySelectionPanel` from `beginAtCursor`.
4. **Fix I-3 (code)**: Move status overlay off the language-control frames without calling `reflowLayout` on hide/show.
5. **Fix I-4 / I-5 / I-6 (code)**: QA Retry; sub focus rings; menubar due image.
6. **Prompt (`/spdd-prompt-update`)**: If a combined P0–P5 drop was intended, record that authorization and drop Safeguard 12 / “one PR per wave” for this issue; otherwise split remaining work into `ISSUE-…-popup-ux-pN-…` prompts.
7. **Do not `/spdd-sync`** until C-1 and C-2 are fixed — those are contract defects, not accepted drift.

## Context Integrity

- Prompt file read in full (Requirements through Safeguard 12).
- Listed sources read (CodeGraph + file reads). Git diff vs HEAD for `Sources/translate` and Tests.
- `translateTests.swift` not in the diff.
- `swift test` not run (repo rule).
- Code and prompt were not modified.
