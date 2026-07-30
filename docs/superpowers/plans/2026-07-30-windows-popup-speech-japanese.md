# Windows Popup Speech Japanese Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix first settings save, add Alt+Enter translation, synchronize speech glyphs with playback, and add migrated Japanese source speech support.

**Architecture:** Preserve existing owners: config parsing owns migration, popup code-behind owns keyboard routing, speech coordinator owns playback state, and view model exposes UI state. Add only fields and notifications required by existing flows.

**Tech Stack:** C# 14, .NET 10, WinUI 3, xUnit, PowerShell, MSIX.

## Global Constraints

- Windows work stays on `windows-app`; never target `main`.
- Japanese source model defaults to `edge-tts/ja-JP-NanamiNeural`.
- Existing configs gain `Japanese` case-insensitively without losing order or values.
- No new dependency or unrelated refactor.
- Update manifest version and pinned test together before install.
- Do not commit, push, publish, or create release.

---

### Task 1: Missing config first save

**Files:**
- Modify: `windows/src/NTranslate.App/IntegrationAdapters.cs:45-56`
- Test: `windows/tests/NTranslate.App.Tests/JsonConfigStoreTests.cs`

**Interfaces:**
- Produces: `JsonConfigStore.LoadAsync(CancellationToken) -> AppConfig.Default` when path does not exist.

- [x] Write regression test `Missing_file_loads_default_config` using a unique absent temp path.
- [x] Run filtered test and verify `DirectoryNotFoundException` failure.
- [x] Add `File.Exists(path) ? parse : AppConfig.Default`.
- [x] Run filtered test and verify pass.

### Task 2: Alt+Enter translation

**Files:**
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml`
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml.cs`
- Test: `windows/tests/NTranslate.App.Tests/Popup/TranslationWindowXamlTests.cs`

**Interfaces:**
- Consumes: existing `ViewModel.TranslateAsync(OperationToken)`.
- Produces: source input key handler that consumes Alt+Enter and invokes translation.

- [ ] Add failing source/XAML test proving source TextBox wires a key handler and handler requires Enter plus Menu modifier before calling `TranslateAsync`.
- [ ] Run focused app tests; verify failure from absent handler.
- [ ] Add minimal `KeyDown` handler. Return unless key is `VirtualKey.Enter` and Alt/Menu is down; set `Handled = true`; await same translate path as button.
- [ ] Run focused app tests; verify pass.

### Task 3: Playback glyph state

**Files:**
- Modify: `windows/src/NTranslate.Core/Speech/SpeechCoordinator.cs`
- Modify: `windows/src/NTranslate.App/Popup/TranslationViewModel.cs`
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml.cs`
- Test: `windows/tests/NTranslate.Core.Tests/Speech/SpeechCoordinatorTests.cs`
- Test: `windows/tests/NTranslate.App.Tests/Popup/TranslationViewModelTests.cs`
- Test: `windows/tests/NTranslate.App.Tests/Popup/TranslationWindowXamlTests.cs`

**Interfaces:**
- Produces: coordinator playback-state event or callback carrying channel phase.
- Produces: view-model source/result speech action properties and `PropertyChanged` notifications.
- Consumes: `SpeechPhase.Playing`, `Paused`, `Idle`, `Failed`, `Loading`.

- [ ] Add failing coordinator tests proving state notifications after play, pause, resume, end, failure, and invalidation.
- [ ] Add failing view-model tests proving Playing maps to Pause and Paused/Idle/Failed maps to Play for each channel.
- [ ] Run focused tests; verify expected failures.
- [ ] Emit state change from coordinator only after locked transitions.
- [ ] Forward state through view model as UI properties and notify on UI dispatcher.
- [ ] Update window glyphs from view-model properties during initialization and `PropertyChanged`; no click-based inference.
- [ ] Run focused Core and App tests; verify pass.

### Task 4: Japanese config, migration, settings, resolver

**Files:**
- Modify: `windows/src/NTranslate.Core/Configuration/AppConfig.cs`
- Modify: `windows/src/NTranslate.Core/Configuration/ConfigJson.cs`
- Modify: `windows/src/NTranslate.Core/Settings/SettingsDraft.cs`
- Modify: `windows/src/NTranslate.Core/Speech/SpeechModelResolver.cs`
- Modify: `windows/src/NTranslate.App/Settings/SettingsWindow.xaml`
- Modify: default Windows config resource located by `ConfigJson.LoadDefault`
- Test: `windows/tests/NTranslate.Core.Tests/Configuration/AppConfigTests.cs`
- Test: `windows/tests/NTranslate.Core.Tests/Settings/SettingsDraftTests.cs`
- Test: speech resolver tests in existing speech test file
- Test: Settings XAML tests in `windows/tests/NTranslate.App.Tests/Settings`

**Interfaces:**
- Produces: `AppConfig.SpeechSourceModelJapanese : string`.
- Produces: `SettingsDraft.SpeechSourceModelJapanese : string`.
- Resolver returns Japanese field for language `Japanese`.

- [ ] Add failing tests for default Japanese language/model, legacy JSON migration, case-insensitive no-duplicate migration, serialization round-trip, settings draft round-trip/validation, resolver, and XAML field.
- [ ] Run focused Core/App tests; verify failures.
- [ ] Extend config record and default JSON with `Japanese` and `edge-tts/ja-JP-NanamiNeural`.
- [ ] Normalize parsed config by appending Japanese only when absent and defaulting missing/blank Japanese model.
- [ ] Extend draft copy, conversion, and validation.
- [ ] Add Advanced Settings label/input binding.
- [ ] Extend resolver switch with Japanese.
- [ ] Run focused tests; verify pass.

### Task 5: Version, full verification, installation

**Files:**
- Modify: `windows/packaging/manifest/AppxManifest.xml`
- Modify: `windows/packaging/tests/Manifest.Tests.ps1`

**Interfaces:**
- Produces: installable MSIX version greater than installed `1.2.12.0`.

- [ ] Change manifest version to `1.2.13.0` and pinned expectation to same value.
- [ ] Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1`; require pass.
- [ ] Run `dotnet test .\windows\NTranslate.slnx --no-restore`; require zero failures.
- [ ] Run `.\install-app.ps1`; require Release build, tests, package, signing, install, verification, and launch to pass.
- [ ] Inspect `git diff --check` and `git status --short`; report changed files without committing.
- [ ] Report Version `1.2.13`, Build `1.2.13.0`, package path, exact test totals/skips, installer result, and any physical-interaction limits.
