# SPDD Code Review: Popup UX Master (P0–P5) — r2

## Review Context

- **Prompt**: `spdd/prompt/ISSUE-202608301438-[Feat]-popup-ux-master.md`
- **Prior review**: `spdd/review/ISSUE-202608301451-[Review]-popup-ux-master.md`
- **Code Scope**: Re-review after two targeted fixes. Full read of `StreamCollector` / `performStream` (`Sources/translate/Translator.swift`) and the sub-translate finish path (`setSubResultText`, `finishSubRequest`, `runSubRequest`). Safeguard scan of cancel / close / non-stream / HTTP / Test connection. Yellow items from r1 re-checked at current lines; not re-litigated as 🔴.
- **Review Date**: 2026-08-30 15:15 ICT
- **Method**: Full prompt re-read; CodeGraph + fff; complete read of StreamCollector and sub finish path; compare to r1 C-1 / C-2.

Prompt is a valid REASONS-Canvas master (R/E/A/S/O/N/S). This is a scoped re-review: verify C-1 and C-2 closed; scan for **new** 🔴 only. I-1 stays 🟡 (user authorized all waves in one generate). Other r1 yellows stay yellow unless they became actually critical — they did not.

## Review Summary (Start Here)

| Dimension      | Status     | Findings | Priority |
| -------------- | ---------- | -------- | -------- |
| Requirements   | ⚠️ Partial Drift | 3 | Medium |
| Entities       | ⚠️ Partial Drift | 2 | Low |
| Approach       | ⚠️ Partial Drift | 1 | Medium |
| Structure      | ✅ Aligned | 0 | - |
| Operations     | ⚠️ Partial Drift | 4 | Medium |
| Norms          | ✅ Aligned | 0 | - |
| Safeguards     | ⚠️ Partial Violations | 1 | Medium |
| Intent Drift   | ⚠️ Partial Drift | 4 | Medium |
| Scope Boundary | ⚠️ Minor Boundary Crossing | 1 | Low |

**Overall Assessment**: ⚠️ Needs Attention

High-risk is **clear**: **0 🔴**. C-1 and C-2 from r1 are closed. Remaining gaps are the same 🟡 items (I-2…I-6 plus authorized I-1).

## Prior 🔴 disposition

| ID | r1 | r2 | Evidence |
| -- | -- | -- | -------- |
| C-1 SSE UTF-8 chunk drop | 🔴 | ✅ Closed | `StreamCollector` keeps `pendingBytes`; decodes a UTF-8 prefix; leaves an incomplete trailing sequence (1…3 bytes). `didComplete` calls `consumePendingBytes(flushIncompleteLine: true)` **before** `onComplete`. `sawSSE` completion still uses `accumulated` (`Translator.swift:290-297`), which is now filled from the flushed decoder. |
| C-2 Sub unclosed JSON as success | 🔴 | ✅ Closed | `setSubResultText` accepts `style:` (`+Subtranslate.swift:150-168`). Incomplete JSON on the sub failure path: `setSubResultText(section, lastStreamedSub, style: .error)` (`:385-388`). `.error` is red + `markdown: false`, matching main `finishTextTranslation` (`+Translate.swift:300-303`). Failure path does not write history. |

## 🔴 Must Review (Critical)

None.

## 🟡 Should Review (Important)

Unchanged from r1 except I-1 noted as authorized (do not split / do not treat as 🔴).

- **I-1 Wave isolation / one-shot dump** — working tree vs prompt Requirements + Safeguard 12  
  Prompt still says independent PRs / confirm wave before later waves. User authorized all waves in one generate. Remains 🟡 process drift; not a functional defect.

- **I-2 Empty-from-hotkey omits real hotkey** — `PopoverController+Translate.swift:77` + `PopoverController+Menu.swift:653`  
  `beginAtCursor` no-selection still calls `showEmptySelectionPanel()` (static string). Menu-open path interpolates `displayString`. P1/P4 empty-success contract.

- **I-3 Status overlay shares the language-control slot** — `PopoverController+Layout.swift:135-154`  
  `statusHeight: 0` is correct; status frame still occupies the same x-band as source/swap/target. Languages paint on top. Overlay does not jump panel height.

- **I-4 QA failure has no in-pane Retry** — `PopoverController+QA.swift:229-235`  
  Failure sets `failed: true` only. P1 asked Retry on `+QA` as well as Translate/Actions.

- **I-5 Sub pane still `focusRingType = .none`** — `PopoverController+Subtranslate.swift:30,45`  
  Main + QA were updated; sub source/result and scrolls were not. P2.

- **I-6 Menubar due signal is tooltip-only** — `PopoverController+Menu.swift:119-126`  
  Tooltip + in-panel badge; `statusItem.button` image stays the generic icon. P4 asked image/tooltip when `dueCount > 0`.

## 🟢 Informational (Low Risk)

- **N-1…N-9** from r1 still apply (StreamCollector vs StreamDelta; `RequestScope`; after-Stop copy; finishRequest VO after Stop; testConnection `.imageSearch`; Learning Progress alert; Updates `...`; prompt `Variables:` line).
- **N-10** UTF-8 remainder algorithm drops at most 3 trailing bytes (`Translator.swift:705`). That is the correct max for a 4-byte scalar split across TCP chunks. Mid-stream *invalid* UTF-8 (not a trailing incomplete sequence) can stall `pendingBytes` because only the last 1…3 bytes are stripped — not a production SSE case; not a C-1 reopen.
- **N-11** `translationResult` still skips JSON decode when `requestedSource != autoDetect` (`Translator.swift:466-469`). Unclosed JSON in that mode is success-as-raw on **both** main and sub. Prompt says use existing `translationResult`. Not a C-2 reopen.

## Fix verification (C-1 / C-2)

### C-1 — StreamCollector UTF-8 remainder

`Sources/translate/Translator.swift:668-740` (collector) and `:262-306` (completion).

1. `didReceive` appends to both `buffer` (raw fallback) and `pendingBytes` (decode window), then `consumePendingBytes(flushIncompleteLine: false)`.
2. Decode: whole `pendingBytes` if valid UTF-8; else try `dropLast(1…min(3, count))` until a valid prefix exists; leftover 1…3 bytes stay in `pendingBytes`.
3. Incomplete chunk with only a trailing multi-byte fragment: prefix is prior complete text (or empty); early-return when `decoded` is empty and not flushing — fragment waits for the next packet.
4. `didComplete` (`:690-692`) flushes the last SSE line **then** invokes `onComplete`.
5. `sawSSE` completion (`:290-296`) uses `collector.accumulated` after that flush — the r1 hole (chunk dropped from `accumulated` while `buffer` still held bytes) is gone.

Vietnamese / other multi-byte splits across TCP chunks no longer drop from live `onPartial` or the committed result.

### C-2 — Sub unclosed JSON

`Sources/translate/PopoverController+Subtranslate.swift:150-168` and `:379-391`.

1. `setSubResultText(..., style:)` — explicit style wins over `resultStyle(for:)`.
2. `.error` → `.systemRed`, `markdown: false` (no markdown of raw `{...`).
3. Failure branch: Stop keeps partial / “Stopped”; else if `lastStreamedSub` looks like JSON/fence **and** `error is Translator.ResponseError` → `setSubResultText(section, lastStreamedSub, style: .error)`; else user-facing message.
4. `translationResult` throws `ResponseError.invalidSchema` / `.emptyContent` on unclosed `{` / unclosed fence when auto-detect (`Translator.swift:473-495`). `translate` maps that through `Result.flatMap` (`:521-529`). Sub `handler` is `result.map(\.text)` (`:305`) so the failure type is preserved.
5. History is only written on `.success` (`:358-377`).

Matches main `finishTextTranslation` (`+Translate.swift:300-303`) and Approach §1 / P0 (“keep raw + `ResultStyle.error` — do not invent a translation”).

## Detailed Analysis

### Requirements Alignment

**Status**: ⚠️ Partial Drift

**Alignment**: AppKit / Liquid Glass only. Stream + Stop + overlay; setup buttons + Retry (main) + Test connection; focus rings (main/QA), 11pt floor, contrast, Reduce Transparency, VoiceOver; verb titles + tooltips; pin persist; ISO codes; subtranslate hint; Settings General/Advanced + hotkey conflict. English UI, no emoji. Stream UTF-8 and sub JSON error now match the P0 contract.

**Scope Expansion**: Combined P0–P5 drop (I-1, authorized). Extra Learning Progress alert.

**Scope Contraction**: Hotkey empty from `beginAtCursor`; QA Retry; sub focus rings; menubar due **image**. No longer: UTF-8 drop / sub JSON-as-success.

### Entities Alignment

**Status**: ⚠️ Partial Drift

**Matched Entities**: Same as r1. `Translator` stream + cancel; `PopoverController` generation / Stop / overlay; `SetupIssue`; `UISettings.rememberPin`; history cache APIs unchanged.

**Entity Drift**: `StreamDelta` not added (conservative). `setupIssues` returns `[SetupIssue]`.

**Unauthorized Entities**: `StreamCollector`, `RequestScope` — justified.

**Conservative Constraint Violations**: None.

### Approach Alignment

**Status**: ⚠️ Partial Drift

**Followed Strategies**: `"stream": true`; SSE `data:` + `[DONE]`; translate JSON only at completion via existing `translationResult`; prose streams plain then markdown at final; Stop retitles Translate; floating / image / speech / `imageSearch` / `testConnection` non-stream; overlay `statusHeight: 0`; no reflow on status hide/show; 30s timeout; cancel → Stopped not red; generation guards; history on final only. **UTF-8 remainder and sub raw+error now match Approach §1.**

**Approach Drift**:
- Status overlay still shares the language-control band (I-3).

**Unauthorized Decisions**: `StreamCollector` + `inFlightScope`; Test connection via `.imageSearch` (unchanged).

### Structure Alignment

**Status**: ✅ Aligned

No new base class. Completions preserved; `onPartial` optional. `ResultStyle` has no `.streaming`. Layers unchanged. No SwiftUI, no new windows.

### Operations Alignment

**Status**: ⚠️ Partial Drift

**Operation**: Wave P0 — Translator stream + cancel  
- **Signature**: ✅ Match  
- **Logic Steps**: ✅ 7/7 — SSE + `[DONE]` + fallback one-shot + byte-safe decode + flush before complete  
- **Validation**: ✅ image/speak/floating non-stream; timeout 30s  
- **Error Handling**: ✅ HTTP map, no body dump  
- **Missing Logic**: None for this operation  

**Operation**: Wave P0 — PopoverController Stop + stream render  
- **Signature**: ✅ Match  
- **Logic Steps**: ✅ generation guards, throttle ~100ms, Stop title/tooltip, copyable=false while streaming; **sub JSON fail style matches main**  
- **Error Handling**: ✅ Cancel → Stopped / keep partial  

**Operation**: Wave P0 — Status overlay  
- **Logic Steps**: ⚠️ Overlay + no reflow; collides with language controls (I-3)  

**Operation**: Wave P1 — setup / empty / Retry / Test connection  
- **Logic Steps**: ⚠️ 5/6 — still missing hotkey-interpolated empty from `beginAtCursor`; QA Retry  

**Operation**: Wave P2 — focus / VO / Reduce Transparency  
- **Logic Steps**: ⚠️ Main/QA `.default`; sub still `.none` (I-5)  

**Operation**: Wave P3 — titles / header / pin / ISO  
- **Logic Steps**: ✅ Unchanged, aligned  

**Operation**: Wave P4 — discoverability  
- **Logic Steps**: ⚠️ Menubar due **image** still missing (I-6); empty-from-hotkey (I-2)  

**Operation**: Wave P5 — Settings  
- **Logic Steps**: ✅ Unchanged, aligned  

### Norms Alignment

**Status**: ✅ Aligned

English UI, no emoji, SF Symbols. MainActor hops on stream callbacks. Generation checks. History after final. Frame-based layout. Comments only on stream JSON / overlay / ISO / UTF-8 remainder.

### Safeguards Alignment

**Status**: ⚠️ Partial Violations

**Respected Safeguards**:
- No new window, no SwiftUI, no rewrite of `PopoverLayoutMath` / `ActionRowSection` / floating bar.
- Image, speech, floating Quick Translate do not stream (`stream: false` at `Translator.swift:585,623` and `+Subtranslate.swift:672`).
- Reflow throttled; status hide/show does not change panel height.
- Test connection does not log the API key; HTTP errors use status map (`httpErrorDescription`); `userFacingError` strips `Bearer` / `sk-` / `api_key`.
- Non-SSE fallback via `responseContent(from: buffer)`; Stop still `task.cancel()`.
- `dailyReviewLimit` / `isDictionaryTerm` / `previewLanguagePair` / `shouldSubtranslate` / history semantics unchanged.
- Cancel is not a red error on main.
- `focusRingType = .none` remains on glass hosts.
- Pin missing key = false; hotkey defaults and `ui.width` 820 unchanged.
- `onPartial` optional; public completions preserved.
- `closePanel` cancels in-flight, increments both generations, `removeSubSection`.
- P1+ does not revert Stop / stream / overlay.
- **Stream UTF-8 correctness (r1 C-1) now respected.**
- **Sub unclosed JSON raw+error (r1 C-2) now respected.**

**Violations**:
- 🟡 **Safeguard 12 (wave isolation)**: P0–P5 in one tree — authorized; do not treat as 🔴.

## Intent Drift Analysis

### Positive Drift (Unauthorized Additions)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| D-P1 | 🟡 | working tree | All P0–P5 in one change (authorized; stays 🟡) |
| D-P2 | 🟢 | `+Menu.swift:152` | Learning Progress still opens NSAlert |
| D-P3 | 🟢 | `Translator.swift:588` | Test connection reuses `.imageSearch` |

### Negative Drift (Missing Implementations)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| D-N1 | ~~🔴~~ ✅ | `Translator.swift:697-715` | Byte-safe SSE decode — **closed** |
| D-N2 | ~~🔴~~ ✅ | `+Subtranslate.swift:385-388` | Raw+error on unclosed translate JSON (sub) — **closed** |
| D-N3 | 🟡 | `+Translate.swift:77` | Empty state interpolates hotkey |
| D-N4 | 🟡 | `+QA.swift:229` | In-pane Retry on QA failure |
| D-N5 | 🟡 | `+Subtranslate.swift:30` | Sub focus rings `.default` |
| D-N6 | 🟡 | `+Menu.swift:119` | Menubar due **image** |

### Direction Drift (Divergent Approaches)

| Finding | Severity | Location | Description |
|---------|----------|----------|-------------|
| D-D1 | 🟡 | `+Layout.swift:135` | Status overlay vs reserved header slot |
| D-D2 | 🟢 | `Translator.swift:669` | `StreamCollector` instead of `StreamDelta` |

## Implicit Decisions (AI Judgment Points)

| Decision | Category | Location | AI's Choice | Risk |
|----------|----------|----------|-------------|------|
| UTF-8 remainder window | Algorithm | `Translator.swift:705` | Drop last 1…3 bytes | Low (correct for UTF-8) |
| SSE via URLSession delegate | Algorithm | `Translator.swift:261-306` | New session + `StreamCollector` per request | Low (was Medium while C-1 open) |
| One task, `inFlightScope` | Concurrency | `+Status.swift:64-114` | Main and sub cancel each other | Low |
| Test connection prompt | Config | `Translator.swift:588` | `.imageSearch` + “OK” | Low |
| Status vs languages | Layout | `+Layout.swift:135` | Same x-range, languages on top | Medium (I-3) |
| Combined wave drop | Process | git working tree | All waves at once (authorized) | Low |

## Scope Boundary Check

**Status**: ⚠️ Minor Boundary Crossing

**In-Scope Components**: Same 16-file `Sources/translate` surface as r1. `ActionRowSection`, `PopoverLayoutMath`, `LanguageDetector`, tests unchanged.

**Boundary Crossings**:
- Process: P0–P5 together (authorized I-1). No out-of-folder edits. No History/Review rewrites. No `windows-app` touch.

## Recommended Actions

1. **C-1 / C-2**: No further code change required for those defects.
2. **Optional polish (🟡)**: I-2 hotkey empty state; I-3 status vs languages; I-4 QA Retry; I-5 sub focus rings; I-6 menubar due image.
3. **Prompt (`/spdd-prompt-update`)**: Record combined-wave authorization and retire Safeguard 12 for this issue if the tree will ship as one drop.
4. **`/spdd-sync`**: Allowed from a high-risk standpoint (zero 🔴). Sync still should not paper over I-2…I-6 unless those omissions are accepted into the prompt.

## Context Integrity

- Prompt file read in full (Requirements through Safeguard 12).
- Prior review read in full.
- `StreamCollector`, `consumePendingBytes`, `performStream` completion, `setSubResultText`, `finishSubRequest`, `runSubRequest`, `translationResult`, `finishTextTranslation` read completely.
- Yellow call sites re-checked (I-2…I-6 line numbers current).
- `swift test` not run (repo rule).
- Code and prompt were not modified.
