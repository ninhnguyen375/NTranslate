# SPDD Analysis: Ctrl+Option+D simulated copy is unreliable

## Original Business Requirement

phím tắt Ctrl+Opt+D chưa thật sự giả lập copy text, phải cần thực hiện thao tác Edit>Copy (cmd+C) thì mới chuẩn, kiểm tra lại

## Domain Concept Identification

### Existing Concepts (from codebase)

- **Copy-and-translate hotkey** (`PopoverController.registerHotKey`, `Sources/translate/PopoverController.swift:1593`): fixed `Control+Option+D` registered as `EventHotKeyID` id `2` via Carbon `RegisterEventHotKey`; dispatched as `HotkeyIntent.copyAndTranslate` and routed to `translateAtCursor(forceSimulatedCopy: true)` — relationship: it is the only entry point that forces the copy path, bypassing Accessibility selection reading.
- **Translatable input resolution** (`SelectionReader.resolveTranslatableInputWithDiagnostics`, `Sources/translate/SelectionReader.swift:65`): decides between three sources — `selection` (Accessibility `AXSelectedText`), `simulatedCopy` (synthetic Cmd+C), `clipboard` (read pasteboard as-is). With `forceCopy: true`, Accessibility is skipped entirely and clipboard fallback is disabled, so the synthetic keystroke is the single point of failure.
- **Synthetic copy keystroke** (`SelectionReader.copyViaKeyboard`, `Sources/translate/SelectionReader.swift:206`): builds a `CGEvent` key down/up for `kVK_ANSI_C` with `flags = .maskCommand`, posts to `.cghidEventTap`, then polls `NSPasteboard.general.changeCount` up to 20 × 10ms.
- **Clipboard preservation** (`SelectionReader.simulatedCopyInput`, `Sources/translate/SelectionReader.swift:154`): snapshots every pasteboard item, runs the copy closure, parses the result, then restores the original clipboard in a `defer`. Owns the clipboard lifecycle for the whole simulated-copy operation.
- **Pasteboard change detection**: `changeCount` before/after is the sole success signal; a false negative aborts the whole translate flow (`translateAtCursor` shows `showEmptySelectionPanel()`).
- **Configured `simulateCopy` flag** (`AppConfig.UI.simulateCopy`, `Sources/translate/AppConfig.swift:16`, surfaced as the Settings "Paste" checkbox): opt-in that makes the *normal* hotkey also try simulated copy after Accessibility fails — same underlying mechanism, so any defect here affects both paths.
- **Accessibility trust** (`AXIsProcessTrusted`): required both for `AXSelectedText` reads and for `CGEvent.post` to be delivered to other applications.
- **Frontmost application** (`previousApp` in `translateAtCursor`): the app that must receive the synthetic Cmd+C. The popover has not been presented yet at copy time, so the target app should still be frontmost — this ordering is load-bearing and currently implicit.

### New Concepts Required

- **Modifier state hygiene for synthetic input**: the physical `Control` and `Option` keys of the triggering hotkey are still held down when the synthetic Cmd+C is posted. Because the event is posted to `.cghidEventTap` with a `.combinedSessionState` source, the hardware modifier state is merged with the event's own flags, so the receiving app most likely observes `Cmd+Ctrl+Option+C` — not a Copy shortcut in any standard responder chain. This is the leading explanation of why manual **Edit ▸ Copy** works but the hotkey does not. A concept for "post the keystroke with a clean, known modifier state" does not exist in the codebase today.
- **Hotkey-release synchronization**: the notion of waiting until the user has physically released the triggering chord (or explicitly clearing it) before injecting keystrokes.
- **Delivery-vs-effect distinction**: today "copy failed" and "copy produced no new clipboard content" are the same outcome. A concept that separates *the keystroke was not delivered / was malformed* from *the app had nothing selected to copy* is needed to give correct feedback and to avoid restoring the clipboard over a legitimately empty result.
- **Copy readiness preconditions**: an explicit check that the process is Accessibility-trusted (and, in the `forceCopy` path, a distinct message when it is not) before attempting event injection.

### Key Business Rules

- **Ctrl+Option+D must copy the current selection of the frontmost app and translate it** — governs the copy-and-translate hotkey, `translateAtCursor(forceSimulatedCopy:)`, and `copyViaKeyboard`.
- **The user's clipboard must be preserved unchanged after the operation** — governs `simulatedCopyInput`; this is an existing guarantee that any fix must not weaken (including on the failure and error paths).
- **The synthetic keystroke must be indistinguishable from a real Cmd+C from the target app's perspective** — implicit rule, currently violated by residual modifier flags.
- **The popover must not steal focus before the copy is captured** — implicit rule; focus changes (including a permission prompt) between hotkey and copy invalidate the target app's selection.
- **Failure must degrade visibly, not silently** — governs the `forceCopy` branch, which returns `nil` and produces the generic "No text selected" panel even when the real cause was a malformed or undelivered keystroke.
- **Non-text selections (images) must still resolve** — the copy path also feeds the PNG/TIFF branch of `translatableInput`, so the fix must remain input-type agnostic.

## Strategic Approach

### Solution Direction

Treat this as a **synthetic-input fidelity defect** localized to `SelectionReader.copyViaKeyboard`, not as a hotkey-registration or clipboard-restoration defect. Registration is confirmed working (the code path fires), and clipboard save/restore is already covered by tests. The direction is:

1. Make the injected keystroke carry exactly the Cmd modifier as observed by the target app — neutralizing the still-held Control/Option from the triggering chord, and setting the flags on the event source/event pair consistently rather than relying on the combined hardware state.
2. Give the target app a realistic timing window: allow the triggering hotkey to settle before injection, and keep a bounded wait for the pasteboard to update afterwards.
3. Distinguish "keystroke could not be injected" from "nothing was copied", and surface the former through the existing status-line mechanism (`setStatus` / `PopoverFeedback`) instead of the generic empty-selection panel.
4. Keep the existing seam — `simulatedCopyInput(from:performCopy:)` already isolates the injection closure from the clipboard bookkeeping, so the change stays inside one function plus a small policy helper, and remains unit-testable through the injected closure.

Data flow direction is unchanged: Carbon hotkey → `PopoverController.copyAndTranslateHotKeyPressed` → `SelectionReader.resolveTranslatableInputWithDiagnostics(forceCopy: true)` → `copyViaKeyboard` → clipboard parse → popover presentation → translate.

### Key Design Decisions

- **Where to fix — event construction vs. hotkey design**: rewriting the injection (clean modifier state, correct source/tap) is a contained change with an existing test seam; changing the hotkey to a modifier-free chord would move the problem rather than solve it and would break a documented, user-visible shortcut. → **Fix the event construction**; keep `Control+Option+D`.
- **How to neutralize residual modifiers**: options are (a) explicitly post modifier key-up / `flagsChanged` events for Control and Option before the Cmd+C pair and restore afterwards, (b) wait for the user to physically release the chord before injecting, (c) rely on setting `flags` on both the event and a `.privateState`/`hidSystemState` source so the combined state is not consulted. (a) is deterministic but mutates global modifier state and must be exactly reverted; (b) is user-perception-dependent and adds unbounded latency; (c) is the least invasive but its effectiveness depends on macOS combining hardware state at the tap. → **Recommend combining a deterministic modifier-clear with a bounded settle delay**, and verify empirically against a real app before committing to the minimal variant — the physical world (real modifier timing, real app responder chains) needs measurement, not just reasoning.
- **Which event tap to post to**: `.cghidEventTap` injects at the lowest level and reaches all apps; `.cgSessionEventTap` / `.cgAnnotatedSessionEventTap` sit above the HID layer and interact differently with hardware modifier state. → **Revisit the tap choice as part of the same experiment**; do not change it blindly.
- **Success signal**: keep `changeCount` as the primary signal (cheap, already tested) but add a distinct "injection failed" outcome for the cases where the `CGEventSource`/`CGEvent` cannot be constructed or the process is not Accessibility-trusted. → **Keep `changeCount`, add an explicit precondition failure.**
- **Polling budget**: current 20 × 10ms ≈ 200ms via `RunLoop.current.run` may be too short for slow apps (Office, Electron, remote desktops) and, being a nested run loop on the main thread, can re-enter AppKit. → **Re-evaluate both the budget and the waiting mechanism**; a longer bounded wait is preferable to a false "no text selected".
- **Feedback surface**: reuse `PopoverFeedback` + `setStatus` rather than adding a new alerting mechanism. → **Extend the existing feedback strings.**

### Alternatives Considered

- **Drive the target app's Edit ▸ Copy menu item via Accessibility (`AXPress`)**: matches exactly what the user reports as working, but requires locating the menu item per app, is slow, breaks on non-standard menus and non-English localizations, and fails for apps without a menu bar. Rejected as the primary mechanism; it could be a last-resort fallback if event injection proves unfixable.
- **AppleScript `tell application "System Events" to keystroke "c" using command down`**: same underlying event injection with more process overhead and an additional automation-permission prompt. Rejected.
- **Drop simulated copy and rely solely on Accessibility `AXSelectedText`**: already the default path, and its failure in browsers/Electron apps is precisely why the copy path exists. Rejected.
- **Change the hotkey to avoid held modifiers**: any usable global hotkey needs modifiers, so the residual-modifier problem recurs. Rejected.

## Risk & Gap Analysis

### Requirement Ambiguities

- **Scope of "chưa thật sự giả lập copy"**: not stated whether the copy fails in *all* apps or only some. The residual-modifier hypothesis predicts near-universal failure; a partial failure would instead point at timing or app-specific responder chains. → Needs a concrete reproduction list (which apps, which selection types) before locking the fix.
- **Observed symptom**: unclear whether the popover shows "No text selected", shows the *previous* clipboard content, or shows stale translated text. Each points to a different failure stage (injection vs. detection vs. restoration ordering).
- **Whether the configured `simulateCopy` checkbox path shows the same defect**: the requirement names only Ctrl+Option+D, but both paths share `copyViaKeyboard`. Assumed in scope since a root-cause fix covers both; confirm with the user if the Settings path is expected to change behavior.
- **Expected behavior when nothing is selected**: with `forceCopy: true` the clipboard fallback is deliberately disabled, so an empty selection yields the empty panel. Not stated whether the user expects a fallback to existing clipboard content instead.

### Edge Cases

- **User still holding Control+Option when the copy is injected** — the default case for a hotkey trigger, and the prime suspect.
- **User releases the chord unusually fast or slowly** — any fixed settle delay must work at both ends.
- **App has no selection** — must not be reported as an injection failure, and the clipboard must remain untouched.
- **App copies slowly** (Office, Electron, JetBrains, remote desktop/VM sessions) — exceeds the current ~200ms budget and produces a false negative.
- **App writes multiple pasteboard flavors or writes lazily/promised data** — `changeCount` may increment before the payload is readable.
- **Selection is an image** — the copy path feeds `normalizedPNG`; a large image can also throw `imageTooLarge` *after* a successful copy, and clipboard restoration must still run (it does, via `defer`).
- **Clipboard restoration racing the target app** — if the app writes the pasteboard after the `defer` restores it, the user's clipboard is silently replaced.
- **Accessibility permission not granted** — `CGEvent.post` is silently dropped; `translateAtCursor` prompts for permission at entry, and that prompt itself can steal focus and destroy the selection.
- **Another app owns a global Cmd+C hook / clipboard manager** — may consume or duplicate the injected event.
- **Secure input mode active** (password fields, some terminals) — event injection is blocked outright and cannot be worked around; needs a distinct message.
- **Hotkey pressed while the NTranslate popover itself is frontmost** — the copy would target NTranslate's own text view rather than the user's app.
- **Modifier-clearing events leaking** — if Control/Option key-up events are injected and the restore is skipped (early return, thrown error), the system is left believing modifiers changed state. Any such approach needs a guaranteed-restore construct.

### Technical Risks

- **Global modifier state mutation**: injecting modifier key-up/down events affects every application system-wide. Impact: stuck modifiers, misinterpreted keystrokes in other apps. Mitigation: strictly scoped and unconditionally reverted (defer-style), with the smallest possible window.
- **Nested run loop during polling**: `RunLoop.current.run(until:)` on the main thread while a Carbon hotkey handler is unwinding can re-enter AppKit and has historically caused crashes in this codebase (see `fc6a691 Fix simulateCopy config and fix hotkey dispatch crash`, `9b499fa Fix Excel hotkey crash`). Impact: regression risk on the exact code being touched. Mitigation: keep the existing dispatch-to-main indirection, prefer a bounded non-reentrant wait, and re-run the existing crash-related tests.
- **Unverifiable in unit tests**: the actual event injection cannot be covered by `swift test` — `simulatedCopyInput` is testable only through its injected closure, and `copyViaKeyboard` is the untested part. Impact: the fix can only be validated by manual testing in real apps. Mitigation: keep the injection logic behind a small pure policy function where possible (flags/timing computation), unit-test that, and define an explicit manual test matrix.
- **Timing tuning is empirical**: settle delay and polling budget are physical-world parameters that vary by machine load and app. Impact: an under-tuned value reintroduces the bug on slower setups. Mitigation: choose bounded-with-retry over a single fixed sleep, and keep the values adjustable rather than deeply hardcoded.
- **Latency regression**: any added delay is felt on every Ctrl+Option+D invocation and, if `simulateCopy` is enabled, on the normal hotkey after every Accessibility failure.
- **Clipboard data loss**: this flow already owns the user's clipboard; a mistake in the restore path is user-visible data loss. Any change must keep the `defer`-based restoration intact on every exit path, including thrown errors.
- **Silent-failure surface**: `CGEventSource(stateID:)` and `CGEvent(keyboardEventSource:...)` returning `nil` currently collapse into "no text selected", hiding real misconfiguration.
- **macOS 26 platform target**: the package targets `.macOS(.v26)`; event-tap and secure-input behavior on this version must be verified rather than assumed from older documented behavior.

### Acceptance Criteria Coverage

The requirement is a bug report and contains no formal acceptance criteria. The criteria below are derived from the reported symptom and the invariants found in the codebase; they must be confirmed with the user before the REASONS Canvas phase.

| AC# | Description | Addressable? | Gaps/Notes |
|-----|-------------|--------------|------------|
| 1 | Pressing Ctrl+Option+D over a text selection copies that selection without any manual Edit ▸ Copy | Yes | Core fix in `copyViaKeyboard`; verification is manual only |
| 2 | Behavior matches a real Cmd+C across common apps (Safari/Chrome, Notes, VS Code, Terminal, Office) | Partial | App list not specified by the user; secure-input contexts cannot be supported at all |
| 3 | The user's clipboard is unchanged after the operation, including on failure and error paths | Yes | Already guaranteed by `simulatedCopyInput`'s `defer`; must not regress |
| 4 | Slow-to-respond apps still succeed | Partial | Requires a timing budget decision; no upper bound defined by the requirement |
| 5 | An empty selection produces clear feedback, distinct from an injection failure | Partial | Requires new feedback strings; exact wording not specified by the user |
| 6 | Missing Accessibility permission / secure input produces an actionable message instead of "No text selected" | Partial | Depends on AC 5's feedback surface; secure-input detection needs verification on macOS 26 |
| 7 | No stuck modifier keys or side effects in other applications after the operation | Yes | Directly constrains the modifier-clearing design |
| 8 | Image selections continue to work through the copy path | Yes | Existing `normalizedPNG` path is unaffected by the modifier fix |
| 9 | No regression to the normal hotkey path or the Settings `simulateCopy` checkbox | Yes | Shared code path; covered by existing tests plus manual checks |
