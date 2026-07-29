# Windows Popup Parity Design

## Goal

Bring Windows translation popup and activation flows to functional parity with current macOS behavior while keeping native WinUI presentation and Windows-safe platform behavior.

## Scope

- Replace stacked Windows popup with macOS-style split-pane hierarchy.
- Use native WinUI icons, theme resources, focus visuals, tooltips, and accessibility names.
- Auto-translate valid selected text captured by global hotkey.
- Auto-preview and translate valid clipboard images captured by global hotkey.
- Keep tray/manual popup activation non-translating.
- Keep app hidden on normal startup until tray, hotkey, or explicit activation opens it.
- Expose History and Check for Updates from popup header.
- Expose speech rate, source/result speech, copy, and bookmark actions in pane headers.
- Persist image translations in history without persisting source image bytes.
- Document deliberate Windows differences for simulated-copy clipboard handling and MSIX updates.

## Non-goals

- Recreate macOS glass materials or AppKit appearance.
- Add dependencies or a new UI framework.
- Persist source image files in history.
- Replace Windows MSIX installer behavior with a custom updater.
- Restore simulated-copy clipboard snapshots without proven clipboard ownership.
- Modify macOS source or behavior.

## Popup Layout

Use one compact custom title/header and remove duplicate system-title-bar chrome where WinUI supports it.

```text
┌───────────────────────────────────────────────────────────┐
│ NTranslate                      Update History Pin Close   │
├────────────────────────────┬──────────────────────────────┤
│ EN                 1× 🔊   │ VI                    🔊 ⧉ ☆ │
│                            │                              │
│ Source text/image preview  │ Translation result           │
│                            │                              │
├────────────────────────────┴──────────────────────────────┤
│ Status/loading/error                                       │
├───────────────────────────────────────────────────────────┤
│ Images  Learn  Translate       English  ↔  Vietnamese     │
└───────────────────────────────────────────────────────────┘
```

### Header

- App title on left.
- Update, History, Pin, Close icon buttons on right.
- Every icon-only button has tooltip and `AutomationProperties.Name`.
- Header remains dedicated drag surface; interactive controls do not start drag.

### Source pane

- Compact detected/selected language code.
- Speech-rate selector and source speech action in pane header.
- Scrollable source editor in text mode.
- Image preview and `Clipboard image` label in image mode.

### Result pane

- Compact target language code.
- Result speech, copy, and bookmark actions in pane header.
- Scrollable read-only result editor.

### Footer

- Images, Learn, and accent Translate buttons on left.
- Source language, swap icon, and target language controls on right.
- Layout must not clip controls at default dimensions or common DPI scaling.

### Visual system

- Prefer `SymbolIcon`; use `FontIcon` with `Segoe Fluent Icons` only when no suitable symbol exists.
- Translate uses icon plus text and accent button styling.
- Other contextual actions use compact icon buttons.
- Use WinUI theme resources rather than hard-coded light-mode colors.
- Preserve keyboard focus, high contrast, and accessible live regions.

## Activation and Translation Flows

### Hotkey text

1. Global hotkey cancels prior capture and popup translation work.
2. Capture tries UI Automation selected text.
3. If enabled and needed, simulated copy runs.
4. Clipboard text remains fallback.
5. Valid text is routed to popup.
6. Popup becomes visible immediately and translation starts immediately.
7. Language resolution, request arbitration, history, auto-copy, and speech prefetch use existing `TranslationViewModel` behavior.
8. A newer hotkey request invalidates stale capture and translation side effects.

Empty capture opens a blank manual popup with guidance and makes no API call.

### Hotkey image

1. Text remains first priority.
2. If no valid text exists, capture checks clipboard bitmap content.
3. Popup enters image mode and shows preview.
4. Existing image normalization validates format, encoded size, and decoded dimensions.
5. Valid image translates immediately using current target language.
6. Invalid or oversized image keeps popup open and shows error without API submission.

### Manual activation

Tray click, app activation, and explicit manual opening show popup without starting translation. Reopening a history record restores its accepted fields without automatically issuing a new request.

### Startup

Normal startup initializes tray, config, credentials, history, hotkey, crash handling, and recovery state, then stays hidden. Explicit secondary activation may still request popup display through existing activation policy.

## History and Bookmark

- Accepted text and image results create history records.
- Image history uses source label `Clipboard image`; image bytes are not persisted.
- Reopening image history restores label, result, languages, and mode metadata, but no unavailable preview.
- Bookmark button is enabled only when current accepted result has a history record ID.
- Bookmark state reflects `IsSaved` and toggles through existing history runtime/store.
- Failed history mutation leaves prior UI state intact and reports status.
- Copy and auto-copy only operate on accepted results, never guidance/loading/error text.

## Speech

- Source and result speech buttons retain existing play/loading/pause/resume states.
- Speech rate is selectable from supported values within existing `0.5...1.5` validation.
- Rate changes apply to active playback and become current runtime setting.
- Image mode disables source speech because source has no text.

## Updates

Popup Update action invokes existing `ManualUpdateFlow`:

1. Check GitHub releases.
2. Show current/available/error state.
3. Require explicit install confirmation.
4. Download expected `NTranslate-<version>-win-x64.msix`.
5. Verify package identity, publisher, architecture, and version.
6. Open Windows package installer.

Windows does not silently replace the running application or guarantee automatic restart after installer completion. Documentation must state this platform difference.

## Clipboard Safety

Simulated copy intentionally leaves newly copied content in clipboard. Windows implementation will not restore old content until ownership can be proven reliably. This avoids overwriting concurrent clipboard writes. Existing skipped ownership integration tests remain blocker for restoration.

## Error Handling

- Capture failures fall through to next source; diagnostics do not leak selected text.
- API or credential errors preserve source and show retryable status.
- Image validation errors do not call translation API.
- History save/bookmark failures preserve accepted result and prior bookmark state.
- Update failures use existing manual update error UI.
- Closing, deactivation, or newer hotkey invalidates in-flight work and stale side effects.

## Testing

### Unit and structural tests

- Hotkey capture routing distinguishes empty, text, and image.
- Valid hotkey text shows popup then starts one translation.
- Empty/manual activation starts no translation.
- New capture cancels stale auto-translation effects.
- Valid image hotkey enters preview mode and starts one image translation.
- Invalid image reports error without API call.
- Image result creates history metadata without image bytes.
- Bookmark availability, toggle success, and failure rollback.
- Speech-rate control and pane action bindings.
- Popup XAML hierarchy, named controls, icon accessibility, keyboard accelerators, live regions, split panes, and non-overflow grouping.
- Startup does not call manual popup display.

### Required verification

1. `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1`
2. `dotnet test .\windows\NTranslate.slnx --no-restore`
3. Ensure manifest version exceeds installed MSIX version before install; bump manifest and pinned test only if required.
4. `\.\install-app.ps1`
5. Inspect installed popup through actual UI at default size and verify source/result split, visible actions, icon accessibility, and no clipping.
6. Verify selected-text hotkey through real UI where possible; do not claim physical tray or hotkey interaction beyond observed evidence.

## Implementation Constraints

- Windows work remains on a branch based on and targeting `windows-app`; never target `main`.
- Touch only Windows source, tests, packaging metadata required for install, and Windows documentation.
- No dependency additions.
- Reuse history, update, speech, config, and request-generation components.
- Keep diff small; prefer XAML re-layout and narrow adapters over new abstractions.
- Do not commit, push, publish, or create release without explicit request.
