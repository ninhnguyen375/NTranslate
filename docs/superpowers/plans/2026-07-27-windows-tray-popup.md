# Windows Tray and Text Popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver runnable single-instance tray app with global hotkey, safe selected-text capture, Fluent popup, and cancellable text translation.

**Architecture:** App owns lifecycle and ViewModel. Platform isolates UI Automation, clipboard, Win32 hotkey/tray/window placement. Core plan supplies config, language policy, prompts, and OpenAI client.

**Tech Stack:** .NET 10, C# 14, WinUI 3, Windows App SDK, UI Automation, Win32 P/Invoke, xUnit

## Global Constraints

- Windows 10 22H2 build 19045+, x64.
- App starts in tray with no visible normal window; second launch activates existing process.
- Capture order: UI Automation, optional simulated `Ctrl+C`, current clipboard, manual input.
- Restore simulated-copy clipboard only when no third party changed it.
- Never auto-replace source-app text.
- Popup supports pin, close-on-deactivate, drag-to-pin, `Escape`, `Ctrl+Enter`, `Ctrl+Shift+C`.
- Every request uses cancellation and generation gating.
- Never log source/result/clipboard/key.

---

## File Map

- `NTranslate.Platform/Capture/*`: selection contract, UIA reader, fallback coordinator.
- `NTranslate.Platform/Clipboard/*`: snapshot/read/write/conditional restore.
- `NTranslate.Platform/Input/SendInputKeyboard.cs`: `Ctrl+C` injection.
- `NTranslate.Platform/Native/NativeMethods.cs`: minimal P/Invoke.
- `NTranslate.Platform/Hotkeys/GlobalHotkey.cs`: registration/message handling.
- `NTranslate.Platform/Tray/TrayIcon.cs`: `Shell_NotifyIconW` lifecycle.
- `NTranslate.Platform/Windows/*`: message router, desktop context, popup placement.
- `NTranslate.App/Program.cs`: single-instance entry.
- `NTranslate.App/App.xaml(.cs)`: composition/shutdown.
- `NTranslate.App/Popup/*`: ViewModel, popup, coordinator.

### Task 1: Add selection fallback coordinator

```csharp
public enum SelectionSource { UiAutomation, SimulatedCopy, Clipboard }
public sealed record SelectionCapture(string Text, SelectionSource Source, string? Diagnostic);
public interface IUiAutomationSelectionReader { Task<string?> ReadSelectedTextAsync(CancellationToken token); }
public interface ISelectionCaptureService { Task<SelectionCapture?> CaptureAsync(bool simulateCopy, CancellationToken token); }
```

- [ ] Write tests: UIA wins; UIA exception falls through; simulated copy sequence change returns copied text and restores; timeout reads existing clipboard; whitespace returns null; cancellation propagates.
- [ ] Run focused tests; expect compile FAIL.
- [ ] Implement `SelectionCaptureService` with production copy timeout 250 ms and 10 ms bounded checks. Trim only outer whitespace. Keep diagnostic metadata free of selected text.
- [ ] Re-run tests; expect PASS.
- [ ] Commit `feat(windows): add selection capture pipeline`.

### Task 2: Add UI Automation reader

- [ ] Write tests for joining ordered non-empty selection ranges.
- [ ] Run; expect compile FAIL.
- [ ] Add `Microsoft.WindowsDesktop.App.WPF` framework reference only. Read `AutomationElement.FocusedElement`, `TextPattern.Pattern`, `GetSelection()`, and `GetText(-1)` off UI thread. Return null for unsupported provider.
- [ ] Run tests; expect PASS.
- [ ] Commit `feat(windows): read selected text with UI Automation`.

### Task 3: Add clipboard and simulated copy adapters

```csharp
public interface IClipboardSnapshot : IDisposable { uint SequenceNumber { get; } }
public interface IClipboardService
{
    uint GetSequenceNumber();
    IClipboardSnapshot CaptureSnapshot();
    string? ReadUnicodeText();
    void WriteUnicodeText(string text);
    bool RestoreIfUnchanged(IClipboardSnapshot snapshot, uint copiedSequenceNumber);
}
```

- [ ] Write pure restore-policy tests and serialized clipboard integration round-trip with cleanup in `finally`.
- [ ] Run; expect FAIL.
- [ ] Implement OLE snapshot via `OleGetClipboard`, sequence via `GetClipboardSequenceNumber`, conditional `OleSetClipboard`/`OleFlushClipboard`, Unicode read/write on STA. Implement four `SendInput` events: Control down, C down, C up, Control up; require count 4.
- [ ] Run tests; expect PASS and original clipboard restored.
- [ ] Commit `feat(windows): preserve clipboard during simulated copy`.

### Task 4: Add popup placement

```csharp
public readonly record struct ScreenPoint(int X, int Y);
public readonly record struct ScreenRect(int Left, int Top, int Right, int Bottom);
public readonly record struct PopupSize(int Width, int Height);
public static ScreenPoint Place(ScreenPoint cursor, PopupSize popup, ScreenRect workArea, int gap = 12);
```

- [ ] Write tests for below/above/right/left preference, clamp, negative monitor coordinates, taskbar work area, and oversized popup.
- [ ] Run; expect FAIL.
- [ ] Implement pure physical-pixel math; convert WinUI dimensions using target-monitor DPI before calling.
- [ ] Run; expect PASS.
- [ ] Commit `feat(windows): position popup in monitor work area`.

### Task 5: Add native hotkey/message router

```csharp
public sealed record HotkeyRegistrationResult(bool IsRegistered, string? Error);
public interface IGlobalHotkey : IDisposable
{
    event EventHandler? Pressed;
    HotkeyRegistrationResult Register(HotkeyConfig config);
    void Unregister();
}
```

- [ ] Write parser tests for A-Z and configured modifiers; reject unsupported key/no modifier. Test `WM_HOTKEY` ID filtering.
- [ ] Run; expect FAIL.
- [ ] Implement `RegisterHotKey` with `MOD_NOREPEAT`, fixed ID `0x4E54`; re-register unregisters first. `WindowMessageRouter` retains WndProc delegate and restores original proc on dispose.
- [ ] Run; expect PASS.
- [ ] Commit `feat(windows): register configurable global hotkey`.

### Task 6: Add dependency-free tray icon

```csharp
public interface ITrayIcon : IDisposable
{
    event EventHandler? OpenTranslatorRequested;
    event EventHandler? ExitRequested;
    void Show();
}
```

- [ ] Write command-ID mapping tests: Open `1001`, Exit `1099`, unknown none.
- [ ] Run; expect FAIL.
- [ ] Implement `Shell_NotifyIconW`, version 4, `WM_APP+1`, double-click open, right-click native menu, `NIM_DELETE` once. Scope menu to Open Translator and Exit until later plans extend it.
- [ ] Run; expect PASS.
- [ ] Commit `feat(windows): add native tray lifecycle`.

### Task 7: Add single-instance startup

- [ ] Write `ActivationPolicy` tests for primary/redirect paths.
- [ ] Run; expect FAIL.
- [ ] Disable generated XAML main. In `[STAThread] Main`, initialize ComWrappers, `AppInstance.FindOrRegisterForKey("NTranslate.Primary")`, redirect secondary activation, and start WinUI only for primary. Dispatch activation to popup manual entry.
- [ ] Run tests; expect PASS.
- [ ] Commit `feat(windows): route launches to single instance`.

### Task 8: Add cancellable text popup ViewModel

- [ ] Write tests: blank/over-limit no request; correct trimmed text/languages; source/language change cancels and invalidates; old completion loses to newer; cancellation no error; API error preserves source; auto-copy only accepted success; guidance/loading/error cannot copy.
- [ ] Run; expect FAIL.
- [ ] Implement `INotifyPropertyChanged`, local minimal `IAsyncCommand`, and reuse Core `RequestCoordinator`. Translate uses language policy/prompt/client and checks generation before result/status/copy mutation.
- [ ] Run; expect PASS.
- [ ] Commit `feat(windows): add cancellable text translation state`.

### Task 9: Add Fluent popup and composition

- [ ] Add XAML-binding/accessibility tests for named controls, polite result live region, keyboard accelerators, and close cancellation.
- [ ] Run; expect FAIL.
- [ ] Add hidden startup window: title/pin/close, editable source, read-only result, language selectors, swap, Translate, Copy. Unpinned deactivation closes; drag pins; hotkey captures then opens; tray opens manual entry. Keep code-behind to HWND/window events only.
- [ ] Compose exactly one router, clipboard, capture, hotkey, tray, ViewModel, popup coordinator. Shutdown order: cancel work, unregister hotkey, delete tray, restore WndProc, close window.
- [ ] Run full tests and Release build; expect zero failures/errors.
- [ ] Commit `feat(windows): compose tray translation application`.

## Verification

```powershell
dotnet restore .\windows\NTranslate.slnx
dotnet test .\windows\NTranslate.slnx -c Release -p:Platform=x64
dotnet build .\windows\NTranslate.slnx -c Release -p:Platform=x64 --no-restore
git diff --check
```

Manual unpackaged smoke: tray only startup; second launch activates; Notepad/browser selection; safe clipboard restore; no-selection manual entry; stale request rejection; shortcuts; pin/deactivate/drag; hotkey collision leaves tray usable; Exit releases tray/hotkey.
