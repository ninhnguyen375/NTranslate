# Windows Popup Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Windows popup match macOS hierarchy, auto-translate hotkey text/images, stay hidden at startup, and complete reviewed history/update/clipboard parity.

**Architecture:** Extend capture result with optional bitmap data, then let `AppComposition` dispatch explicit manual, text-auto, or image-auto popup requests. Reuse `TranslationViewModel`, history runtime, speech coordinator, and update flow; re-layout popup in XAML and add only narrow callbacks for header actions and bookmark persistence.

**Tech Stack:** C# 14, .NET 10, WinUI 3, Windows App SDK, xUnit, MSIX/PowerShell packaging.

## Global Constraints

- Work only on branch based on and targeting `windows-app`; never target `main`.
- No dependency additions.
- Keep WinUI native; no macOS glass emulation.
- Preserve simulated-copy clipboard content; do not restore old clipboard without proven ownership.
- Use `SymbolIcon` first and `FontIcon` with `Segoe Fluent Icons` only when needed.
- Every icon-only control needs tooltip and `AutomationProperties.Name`.
- Do not persist source image bytes.
- Do not commit, push, publish, or create release.
- Before installation run script tests and `dotnet test ... --no-restore`.
- Install final Windows build with `.\install-app.ps1`; report Version, Build, package path, and tests.

---

## File Map

- `windows/src/NTranslate.Platform/Capture/SelectionCapture.cs` — capture result contract for text or image.
- `windows/src/NTranslate.Platform/Capture/SelectionCaptureService.cs` — selection/clipboard priority and safe image extraction.
- `windows/src/NTranslate.Platform/Clipboard/IClipboardService.cs` — narrow bitmap-read capability.
- `windows/src/NTranslate.Platform/Clipboard/OleClipboardService.cs` — bitmap clipboard implementation.
- `windows/src/NTranslate.App/AppComposition.cs` — startup policy, capture routing, popup auto-translation, popup history/update callbacks.
- `windows/src/NTranslate.App/AppPolicies.cs` — pure routing decision test seam.
- `windows/src/NTranslate.App/Popup/TranslationWindow.xaml` — split-pane popup hierarchy and native icons.
- `windows/src/NTranslate.App/Popup/TranslationWindow.xaml.cs` — popup request modes, image preview, header callbacks, custom title bar.
- `windows/src/NTranslate.App/Popup/TranslationViewModel.cs` — pane labels, speech rate, current history ID/saved state, image history metadata.
- `windows/src/NTranslate.App/History/HistoryViewModel.cs` or existing history runtime adapter — bookmark mutation by current record ID.
- `windows/src/NTranslate.App/IntegrationAdapters.cs` — narrow history bookmark adapter if required by existing boundaries.
- `windows/tests/**` — capture, routing, view-model, startup, and XAML structural tests.
- `docs/windows-app-flows.md` — Windows behavior and deliberate platform differences.

---

### Task 1: Route text and image captures explicitly

**Files:**
- Modify: `windows/src/NTranslate.Platform/Capture/SelectionCapture.cs`
- Modify: `windows/src/NTranslate.Platform/Capture/SelectionCaptureService.cs`
- Modify: `windows/src/NTranslate.Platform/Clipboard/IClipboardService.cs`
- Modify: `windows/src/NTranslate.Platform/Clipboard/OleClipboardService.cs`
- Modify: `windows/src/NTranslate.App/AppPolicies.cs`
- Test: `windows/tests/NTranslate.Platform.Tests/Capture/SelectionCaptureServiceTests.cs`
- Test: `windows/tests/NTranslate.App.Tests/AppPoliciesTests.cs`

**Interfaces:**
- Produce `SelectionCapture` with mutually exclusive `Text` and `ImagePng` payloads plus `SelectionSource` and diagnostic.
- Produce `CaptureRouting.Resolve(SelectionCapture?)` returning `PopupCaptureKind.Empty`, `Text`, or `Image`.

- [ ] **Step 1: Add failing capture tests**

Add cases proving: UIA text wins; clipboard text wins over bitmap; bitmap is returned only when text is absent; invalid bitmap becomes empty capture with sanitized diagnostic; simulated copy still leaves new clipboard content.

```csharp
[Fact]
public async Task Clipboard_bitmap_is_used_only_when_text_is_unavailable()
{
    var clipboard = new FakeClipboard(null) { Bitmap = ValidPng };
    var capture = await CreateService(new FakeUiaReader(null), clipboard, new FakeCopyCommand())
        .CaptureAsync(simulateCopy: false, CancellationToken.None);
    Assert.Equal(SelectionSource.Clipboard, capture!.Source);
    Assert.Null(capture.Text);
    Assert.Equal(ValidPng, capture.ImagePng);
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```powershell
dotnet test .\windows\tests\NTranslate.Platform.Tests\NTranslate.Platform.Tests.csproj --no-restore --filter "FullyQualifiedName~SelectionCaptureServiceTests"
```

Expected: compile/test failure because image capture contract does not exist.

- [ ] **Step 3: Implement minimal capture contract and clipboard bitmap read**

Use one immutable result record; reject construction with both payloads. Read bitmap only after UIA/simulated-copy/clipboard text returns no usable text. Normalize bitmap through existing Windows imaging APIs into bytes without calling translation API. Keep clipboard restore behavior unchanged.

- [ ] **Step 4: Add and pass pure routing tests**

```csharp
Assert.Equal(PopupCaptureKind.Text, CaptureRouting.Resolve(new("hello", null, SelectionSource.UiAutomation, null)).Kind);
Assert.Equal(PopupCaptureKind.Image, CaptureRouting.Resolve(new(null, ValidPng, SelectionSource.Clipboard, null)).Kind);
Assert.Equal(PopupCaptureKind.Empty, CaptureRouting.Resolve(null).Kind);
```

Run focused Platform and App policy tests; expected PASS.

---

### Task 2: Auto-translate hotkey capture and hide normal startup

**Files:**
- Modify: `windows/src/NTranslate.App/AppComposition.cs`
- Modify: `windows/src/NTranslate.App/AppPolicies.cs`
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml.cs`
- Test: `windows/tests/NTranslate.App.Tests/AppPoliciesTests.cs`
- Test: `windows/tests/NTranslate.App.Tests/Popup/TranslationWindowXamlTests.cs`
- Test: create `windows/tests/NTranslate.App.Tests/Popup/PopupRequestTests.cs` only if no existing pure seam can test dispatch.

**Interfaces:**
- Consume `CaptureRouting.Resolve` from Task 1.
- Produce explicit `ShowManual()`, `ShowAndTranslateTextAsync(string, CancellationToken)`, and `ShowAndTranslateImageAsync(byte[], CancellationToken)` behavior.

- [ ] **Step 1: Add failing request-policy tests**

Cover:

```csharp
Assert.Equal(PopupRequestAction.ShowAndTranslateText, PopupRequestPolicy.Resolve(textCapture));
Assert.Equal(PopupRequestAction.ShowAndTranslateImage, PopupRequestPolicy.Resolve(imageCapture));
Assert.Equal(PopupRequestAction.ShowManual, PopupRequestPolicy.Resolve(null));
```

Also assert startup source no longer invokes `ShowManual()` inside `Start()`.

- [ ] **Step 2: Run tests and verify failure**

```powershell
dotnet test .\windows\tests\NTranslate.App.Tests\NTranslate.App.Tests.csproj --no-restore --filter "FullyQualifiedName~AppPoliciesTests|FullyQualifiedName~PopupRequestTests"
```

Expected: missing request actions and startup assertion failure.

- [ ] **Step 3: Implement popup request dispatch**

In `CaptureAndShowAsync`, preserve generation checks, enqueue one UI action, show popup first, then start translation using popup lifetime token. A newer hotkey must cancel capture and call existing view-model invalidation so stale results cannot write UI/history/clipboard.

Text path:

```csharp
_window.ShowPopup(text);
_ = _viewModel.TranslateAsync(_window.OperationToken);
```

Image path:

```csharp
_window.ShowImagePopup(imageBytes);
_ = _viewModel.TranslateImageAsync(new MemoryStream(imageBytes, writable: false), _window.OperationToken);
```

Expose narrow internal methods/token rather than duplicating request cancellation. Empty capture calls manual show and no API method. Remove unconditional `ShowManual()` from normal `Start()`.

- [ ] **Step 4: Run focused tests and pass**

Expected: manual/empty no translation; text/image exactly one translation; startup hidden; stale generation ignored.

---

### Task 3: Persist image history and support current-result bookmark

**Files:**
- Modify: `windows/src/NTranslate.App/Popup/TranslationViewModel.cs`
- Modify: `windows/src/NTranslate.App/AppComposition.cs`
- Modify: `windows/src/NTranslate.App/History/HistoryViewModel.cs` or `windows/src/NTranslate.App/IntegrationAdapters.cs`
- Test: `windows/tests/NTranslate.App.Tests/Popup/TranslationViewModelTests.cs`
- Test: existing history tests covering saved mutation.

**Interfaces:**
- Produce `CurrentHistoryId`, `IsCurrentSaved`, `CanToggleSaved`, `ToggleSavedAsync(CancellationToken)`.
- Record image history with source label `Clipboard image`, result, languages, and `TranslationMode.ImageTranslate`; no image bytes.

- [ ] **Step 1: Add failing view-model tests**

Add tests proving accepted image result records history metadata, source speech remains disabled, bookmark enables only after history returns ID, successful toggle updates state, failed toggle preserves state and sets status.

```csharp
[Fact]
public async Task Accepted_image_translation_records_metadata_without_source_bytes()
{
    var history = new RecordingHistory();
    var vm = CreateAdvancedViewModel(ScriptedHandler.Sync(_ => JsonResponse("translated")), history: history);
    await vm.TranslateImageAsync(new MemoryStream(ValidPng), CancellationToken.None);
    var entry = Assert.Single(history.Records);
    Assert.Equal("Clipboard image", entry.SourceText);
    Assert.Equal(TranslationMode.ImageTranslate, entry.Mode);
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Expected: image history absent and bookmark members missing.

- [ ] **Step 3: Generalize history callback minimally**

Remove composition filter that accepts only `TranslationMode.Translate`. Convert text and image `TranslationHistoryEntry` to existing `TranslationRecord`; use `Clipboard image` for image source. Add narrow `Func<Guid, bool, CancellationToken, Task>` bookmark callback to `TranslationViewModel`, backed by existing history runtime saved mutation. Preserve old state until callback succeeds.

- [ ] **Step 4: Run popup/history tests and pass**

Expected: text grammar history unchanged; image metadata recorded; bookmark state correct; no image persistence.

---

### Task 4: Add popup pane state and speech-rate behavior

**Files:**
- Modify: `windows/src/NTranslate.App/Popup/TranslationViewModel.cs`
- Test: `windows/tests/NTranslate.App.Tests/Popup/TranslationViewModelTests.cs`

**Interfaces:**
- Produce `SourceLanguageCode`, `TargetLanguageCode`, `SpeechRates`, `SelectedSpeechRate`, and existing speech action properties.

- [ ] **Step 1: Add failing tests**

Test language-code mapping (`AUTO`, `EN`, `VI`, `ZH`, fallback first two letters), auto-detect source code updates from text, supported rates remain in `0.5...1.5`, and changing rate applies through speech boundary without changing persistent config unexpectedly.

- [ ] **Step 2: Run focused tests and verify failure**

Expected: new properties missing.

- [ ] **Step 3: Implement computed properties**

Use one private language-code function and fixed native list such as `[0.5, 0.75, 1.0, 1.25, 1.5]`. Reuse existing speech coordinator rate setter/boundary. Raise property notifications when source text or language selection changes.

- [ ] **Step 4: Run focused tests and pass**

Expected: language labels and speech rate state pass without regressions.

---

### Task 5: Replace popup XAML with macOS-style split pane

**Files:**
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml`
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml.cs`
- Modify: `windows/src/NTranslate.App/AppComposition.cs`
- Test: `windows/tests/NTranslate.App.Tests/Popup/TranslationWindowXamlTests.cs`

**Interfaces:**
- Consume Task 3 bookmark members and Task 4 pane/rate members.
- Consume callbacks for History and Update supplied by composition.

- [ ] **Step 1: Rewrite structural tests first**

Assert exact hierarchy and bindings:

- header contains `UpdateButton`, `HistoryButton`, `PinButton`, `CloseButton`;
- `PaneGrid` has two `*` columns and a divider;
- `SourcePaneHeader` contains source code/rate/speech;
- `ResultPaneHeader` contains target code/speech/copy/bookmark;
- footer has left `ActionPanel` and right `LanguagePanel` rather than one flat button row;
- `ImagePreview` replaces source editor via view-model visibility;
- status is wrapped polite live region;
- icon buttons have tooltip and automation name;
- Translate uses accent style and icon plus text;
- existing keyboard accelerators remain.

- [ ] **Step 2: Run XAML tests and verify failure**

```powershell
dotnet test .\windows\tests\NTranslate.App.Tests\NTranslate.App.Tests.csproj --no-restore --filter "FullyQualifiedName~TranslationWindowXamlTests"
```

Expected: missing controls and old stacked hierarchy.

- [ ] **Step 3: Implement native WinUI layout**

Use Grid rows: header, body, status, footer. Body uses equal columns and thin divider. Use scrollable TextBoxes, contextual icon buttons, `SymbolIcon`/`FontIcon`, tooltips, and theme resources. Wire header callbacks and bookmark/rate handlers. Use `ExtendsContentIntoTitleBar = true` and `SetTitleBar(TitleDragRegion)` if supported by current WinUI window; preserve close/pin drag behavior tests.

- [ ] **Step 4: Prevent overflow and preserve accessibility**

Keep footer left/right groups separated by `*` spacer. Use compact buttons and language controls with bounded widths. Ensure every visible interactive control has frame at default `Ui.Width`/`Ui.Height` and remains keyboard reachable.

- [ ] **Step 5: Run XAML and popup tests and pass**

Expected: structural, accessibility, lifecycle, foreground, view-model tests PASS.

---

### Task 6: Document Windows flows and deliberate differences

**Files:**
- Create: `docs/windows-app-flows.md`
- Reference: `docs/macos-app-flows.md`
- Test: documentation links/format via `git diff --check`.

- [ ] **Step 1: Write Windows user-flow document**

Mirror 14 macOS sections but state Windows behavior exactly: tray, global hotkey auto-translation for text/image, UI Automation rather than Accessibility permission, simulated-copy clipboard retained for safety, MSIX installer handoff, hidden normal startup, split-pane popup controls, image-history metadata limitation.

- [ ] **Step 2: Check document accuracy against source**

Search each named feature in current Windows source and remove claims lacking implementation evidence.

- [ ] **Step 3: Run formatting check**

```powershell
git diff --check
```

Expected: no whitespace errors.

---

### Task 7: Full verification, install, and installed-app inspection

**Files:**
- Modify only if required: `windows/packaging/manifest/AppxManifest.xml`
- Modify with manifest if required: `windows/packaging/tests/Manifest.Tests.ps1`

- [ ] **Step 1: Run required pre-install tests**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1
dotnet test .\windows\NTranslate.slnx --no-restore
```

Expected: all required tests pass; only known clipboard ownership integration skips may remain.

- [ ] **Step 2: Compare installed and manifest versions**

Read installed package version and `windows/packaging/manifest/AppxManifest.xml`. If manifest is not greater, increment only fourth MSIX version component and update pinned manifest expectation together. Re-run manifest/script tests.

- [ ] **Step 3: Install Windows build**

```powershell
.\install-app.ps1
```

Expected: locked restore, Release build, full tests, publish, MSIX packaging, signing, install, verification, and launch all succeed.

- [ ] **Step 4: Inspect installed popup through real UI**

Use `cua-driver`: start session, resolve installed NTranslate AUMID/window, snapshot before each action, inspect screenshot/tree, verify split panes, all icon actions visible, no clipping, source/result editors usable, language/footer grouping present. Use safe actions only and bracket every action with snapshots.

- [ ] **Step 5: Exercise selected-text hotkey where observable**

Use a harmless local text surface, select text, invoke configured hotkey through representative Windows delivery, observe popup loading/result. Do not issue paid translation if API/key state makes this unsafe; in that case verify request transition with test evidence and report live step skipped. Do not claim physical tray clicks without Explorer-observed interaction or user confirmation.

- [ ] **Step 6: Report exact outcome**

Report Version, Build, package path, script/.NET/installer test results, installed popup evidence, skipped checks, and any remaining platform differences. Preserve unrelated untracked macOS docs.
