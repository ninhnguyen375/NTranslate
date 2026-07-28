# Windows v1 Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to execute the three subsystem plans concurrently in isolated worktrees. The user explicitly requested no per-task code-review rounds: run focused tests in each track, integrate all tracks, then perform one review of the complete integrated diff. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Windows v1 parity, integrate three parallel subsystem tracks, review once, build and test Release, create and sign an x64 MSIX, install it, and run installed-app smoke checks.

**Architecture:** Existing subsystem plans remain authoritative for implementation detail. Run Media, History/Settings/Recovery, and Package/Update in separate worktrees with disjoint ownership; reserve shared configuration, project, XAML resource, and composition files for the integration track. Merge tested subsystem commits into `windows-app`, reconcile shared contracts once, review the integrated result once, then package, install, and smoke-test it.

**Tech Stack:** .NET SDK 10.0.301, C# 14, WinUI 3, Windows App SDK, Windows UI Automation, Windows Media Playback, Credential Locker, `System.Text.Json`, `HttpClient`, PowerShell 5.1, Windows SDK Build Tools, MakeAppx, SignTool, xUnit, Git worktrees

## Global Constraints

- Host/support floor: Windows 10 22H2 build 19045+, x64.
- Target `net10.0-windows10.0.19041.0`; MSIX MinVersion `10.0.19045.0`.
- Package identity `NinhNguyen375.NTranslate`; publisher `CN=Ninh Nguyen`.
- Release asset name `NTranslate-<semver>-win-x64.msix`.
- Use .NET, WinUI, WinRT, and Win32 APIs before dependencies.
- Add no database, ORM, MVVM framework, logging package, audio converter, third-party HTTP client, or workload install.
- Every async public operation accepts `CancellationToken`; generation checks gate UI mutations.
- Learn and image operations never create history; successful text Translate and same-language grammar operations do.
- API keys remain only in Credential Locker. Logs, config, diagnostics, fixtures, and commits contain no secret or translation/clipboard content.
- History/config writes are atomic. Malformed history is read-only and never overwritten.
- Updater verifies signature, identity, publisher, architecture, and version before App Installer handoff.
- Private keys, PFX files, certificate passwords, build output, downloaded packages, and user config remain untracked.
- Do not run macOS `./install-app.sh`; this delivery changes Windows code and tooling only.
- Do not review each subsystem task. Run one complete review after integration, then fix every confirmed finding and rerun verification.

## Source Plans

Subsystem agents execute these plans exactly, including their TDD cycles and focused commits:

- Media: `docs/superpowers/plans/2026-07-27-windows-media.md`
- History/Settings/Recovery: `docs/superpowers/plans/2026-07-27-windows-history-settings.md`
- Package/Update: `docs/superpowers/plans/2026-07-27-windows-package-install.md`

Current source differs from paths named in older plans. Use current names instead of creating duplicate concepts:

- Existing request generation gate: `windows/src/NTranslate.Core/Requests/RequestCoordinator.cs`
- Existing translator ViewModel: `windows/src/NTranslate.App/Popup/TranslationViewModel.cs`
- Existing translator window: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml` and `.xaml.cs`
- Existing composition root: `windows/src/NTranslate.App/AppComposition.cs`
- Existing config model: `windows/src/NTranslate.Core/Configuration/AppConfig.cs`
- Existing solution: `windows/NTranslate.slnx`

## File Ownership

### Media track owns

- Create/modify: `windows/src/NTranslate.Core/Translation/**`
- Create/modify: `windows/src/NTranslate.Core/Speech/**`
- Create/modify: `windows/src/NTranslate.Platform/Images/**`
- Create/modify: `windows/src/NTranslate.Platform/Media/**`
- Create/modify: `windows/src/NTranslate.Platform/Shell/**`
- Create/modify: matching tests and bounded media/image fixtures
- Modify in its branch: `windows/src/NTranslate.App/Popup/TranslationViewModel.cs`
- Modify in its branch: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml`
- Modify in its branch: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml.cs`

### History track owns

- Create/modify: `windows/src/NTranslate.Core/History/**`
- Create/modify: `windows/src/NTranslate.Core/Settings/**`
- Create/modify: `windows/src/NTranslate.Core/Recovery/**`
- Create/modify: `windows/src/NTranslate.Platform/Storage/**`
- Create/modify: `windows/src/NTranslate.Platform/Diagnostics/**`
- Create/modify: `windows/src/NTranslate.App/History/**`
- Create/modify: `windows/src/NTranslate.App/Settings/**`
- Create/modify: `windows/src/NTranslate.App/Recovery/**`
- Create/modify: matching tests

### Package track owns

- Create/modify: `windows/src/NTranslate.Core/Updates/**`
- Create/modify: `windows/src/NTranslate.Platform/Updates/**`
- Create/modify: `windows/src/NTranslate.App/Updates/**`
- Create/modify: `windows/packaging/**`
- Create/modify: `windows/install-app.ps1`
- Create/modify: Windows package, script, update, accessibility, and smoke tests
- Create/modify: `windows/README.md` and Windows sections in root `README.md`

### Integration track owns shared files

Subsystem agents may return required changes for these files but must not create alternate config/composition types:

- `windows/src/NTranslate.Core/Configuration/AppConfig.cs`
- `windows/src/NTranslate.Core/Configuration/ConfigJson.cs`
- `windows/src/NTranslate.App/App.xaml`
- `windows/src/NTranslate.App/App.xaml.cs`
- `windows/src/NTranslate.App/AppComposition.cs`
- `windows/src/NTranslate.App/NTranslate.App.csproj`
- `windows/src/NTranslate.Platform/NTranslate.Platform.csproj`
- `windows/Directory.Build.props`
- `windows/NTranslate.slnx`
- central package/version/lock files
- `.gitignore`

---

### Task 1: Capture Baseline and Create Isolated Tracks

**Files:**
- Read: `docs/superpowers/specs/2026-07-28-windows-v1-completion-design.md`
- Read: three source plans listed above
- Verify: `windows/NTranslate.slnx`
- Create at execution time: `.worktrees/windows-media`, `.worktrees/windows-history`, `.worktrees/windows-package`

**Interfaces:**
- Consumes: clean `windows-app` branch at planning commit
- Produces: baseline commit SHA and three named worktrees based on that exact SHA

- [ ] **Step 1: Verify clean baseline**

```powershell
git status --porcelain=v1
git branch --show-current
git rev-parse HEAD
```

Expected: no porcelain output; branch `windows-app`; record exact HEAD SHA.

- [ ] **Step 2: Run fresh baseline tests**

```powershell
dotnet test .\windows\NTranslate.slnx --configuration Release
```

Expected: exit 0; zero failed tests. Stop before creating tracks if baseline fails.

- [ ] **Step 3: Invoke worktree setup workflow**

Invoke `superpowers:using-git-worktrees`. Create branches and worktrees from recorded baseline:

```text
feature/windows-media       .worktrees/windows-media
feature/windows-history     .worktrees/windows-history
feature/windows-package     .worktrees/windows-package
```

Expected: each worktree HEAD equals recorded baseline SHA; main workspace stays on `windows-app`.

- [ ] **Step 4: Verify track isolation**

```powershell
git worktree list --porcelain
git -C .worktrees/windows-media status --short --branch
git -C .worktrees/windows-history status --short --branch
git -C .worktrees/windows-package status --short --branch
```

Expected: each feature branch appears once; all worktrees clean.

### Task 2: Execute Media Track

**Files:**
- Plan: `docs/superpowers/plans/2026-07-27-windows-media.md`
- Worktree: `.worktrees/windows-media`
- Owned paths: Media ownership block above

**Interfaces:**
- Consumes: existing `AppConfig`, `OpenAiCompatibleClient`, `Requests.RequestCoordinator`, clipboard service, popup ViewModel/window
- Produces: Learn/grammar/image/search orchestration, `SpeechCoordinator`, `ISpeechPlayer`, image normalizer, browser launcher, popup controls, focused tests

- [ ] **Step 1: Dispatch one implementation agent in Media worktree**

Use the source plan task-by-task with these mandatory adaptations:

```text
Do not create Core/Translation/RequestCoordinator.cs; extend or reuse Core/Requests/RequestCoordinator.cs.
Use App/Popup/TranslationViewModel.cs, TranslationWindow.xaml, and TranslationWindow.xaml.cs.
Do not modify integration-owned files. Record exact required AppConfig, project-reference, and composition changes in final report.
Commit each green source-plan task to feature/windows-media.
Do not perform code review; focused test evidence is required.
```

- [ ] **Step 2: Verify Media branch**

```powershell
dotnet test .\.worktrees\windows-media\windows\NTranslate.slnx -c Release --filter "FullyQualifiedName~RequestCoordinatorTests|FullyQualifiedName~Image|FullyQualifiedName~Speech|FullyQualifiedName~TranslationViewModelTests"
git -C .worktrees/windows-media diff --check
git -C .worktrees/windows-media status --short
```

Expected: zero failed tests, no whitespace errors, clean worktree.

- [ ] **Step 3: Record Media integration contract**

Agent report must name exact constructors and required shared changes. Minimum expected service boundary:

```csharp
public interface IImageNormalizer
{
    Task<NormalizedImage> NormalizePngAsync(Stream source, CancellationToken cancellationToken);
}

public interface ISpeechPlayer : IAsyncDisposable
{
    event EventHandler? PlaybackEnded;
    event EventHandler<Exception>? PlaybackFailed;
    Task ValidateAsync(ReadOnlyMemory<byte> audio, CancellationToken cancellationToken);
    Task PlayAsync(SpeechChannel channel, ReadOnlyMemory<byte> audio, double rate, CancellationToken cancellationToken);
    void Pause();
    void Resume();
    void Stop();
    void SetRate(double rate);
}
```

Expected: report includes Media branch tip SHA and all requested `AppConfig`, `.csproj`, and composition changes.

### Task 3: Execute History, Settings, and Recovery Track

**Files:**
- Plan: `docs/superpowers/plans/2026-07-27-windows-history-settings.md`
- Worktree: `.worktrees/windows-history`
- Owned paths: History ownership block above

**Interfaces:**
- Consumes: existing `AppConfig`, `IApiKeyStore`, translator accepted-result event or callback
- Produces: `ITranslationHistoryStore`, History window/ViewModel, Settings transaction coordinator/window, crash log service/recovery notice, focused tests

- [ ] **Step 1: Dispatch one implementation agent in History worktree**

Use the source plan task-by-task with these mandatory adaptations:

```text
Extend existing Core/Configuration/AppConfig.cs; do not create a second config type.
Do not modify integration-owned files. Record exact AppConfig, ConfigJson, project, App.xaml, tray, and composition changes in final report.
Expose history through ITranslationHistoryStore and accepted translation through a narrow callback/interface; do not make History depend on popup internals.
Commit each green source-plan task to feature/windows-history.
Do not perform code review; focused test evidence is required.
```

- [ ] **Step 2: Verify History branch**

```powershell
dotnet test .\.worktrees\windows-history\windows\NTranslate.slnx -c Release --filter "FullyQualifiedName~History|FullyQualifiedName~Settings|FullyQualifiedName~Crash|FullyQualifiedName~Recovery"
git -C .worktrees/windows-history diff --check
git -C .worktrees/windows-history status --short
```

Expected: zero failed tests, no whitespace errors, clean worktree.

- [ ] **Step 3: Record History integration contract**

Minimum expected persistence boundary:

```csharp
public interface ITranslationHistoryStore
{
    IReadOnlyList<TranslationRecord> Records { get; }
    string? LoadError { get; }
    Task AppendAsync(TranslationRecord record, CancellationToken token = default);
    Task SetSavedAsync(Guid id, bool saved, CancellationToken token = default);
    Task AttachAudioAsync(Guid id, TranslationAudioKind kind, ReadOnlyMemory<byte> data, CancellationToken token = default);
    Task<byte[]?> ReadAudioAsync(Guid id, TranslationAudioKind kind, CancellationToken token = default);
    Task RemoveAsync(IReadOnlySet<Guid> ids, CancellationToken token = default);
}
```

Expected: report includes History branch tip SHA, constructor signatures, runtime-reload callback, and every shared-file change needed.

### Task 4: Execute Package and Update Track

**Files:**
- Plan: `docs/superpowers/plans/2026-07-27-windows-package-install.md`
- Worktree: `.worktrees/windows-package`
- Owned paths: Package ownership block above

**Interfaces:**
- Consumes: current app executable and package constants
- Produces: strict update policy/client, MSIX verifier/coordinator/UI, manifest, signing scripts, `windows/install-app.ps1`, docs, accessibility checks, installed smoke runner

- [ ] **Step 1: Dispatch one implementation agent in Package worktree**

Use source-plan Tasks 1-9 with these mandatory adaptations:

```text
Do not modify integration-owned files directly except generated lock/version files required to make this branch build; isolate each such commit and list it for integration.
Package current NTranslate.App executable; do not invent a second launcher.
Script tests must inject tool paths/process runners and must not trust certificates, install packages, or launch apps during focused tests.
Create installed smoke scripts, but defer real package installation and real installed smoke execution until after all branches are integrated and reviewed.
Commit each green source-plan task to feature/windows-package.
Do not perform code review; focused test evidence is required.
```

- [ ] **Step 2: Verify Package branch without real installation**

```powershell
dotnet test .\.worktrees\windows-package\windows\NTranslate.slnx -c Release --filter "FullyQualifiedName~Update|FullyQualifiedName~SemanticVersion|FullyQualifiedName~Msix|FullyQualifiedName~Accessibility"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\.worktrees\windows-package\windows\packaging\scripts\Invoke-ScriptTests.ps1
git -C .worktrees/windows-package diff --check
git -C .worktrees/windows-package status --short
```

Expected: zero failed tests, script tests exit 0, no real certificate trust/install, clean worktree. If source plan chooses a different literal script-test filename, agent must create one canonical runner at the path above.

- [ ] **Step 3: Record Package integration contract**

Minimum expected verifier boundary:

```csharp
public interface IMsixPackageVerifier
{
    Task<VerifiedMsixPackage> VerifyAsync(string packagePath, CancellationToken token);
}
```

Expected: report includes Package branch tip SHA, pinned SDK/package versions, shared project/build changes, tray/update command wiring, and exact install/smoke commands.

### Task 5: Integrate Three Tracks

**Files:**
- Modify: integration-owned files listed above
- Modify: `windows/src/NTranslate.App/Popup/TranslationViewModel.cs`
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml`
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml.cs`
- Test: all Windows test projects

**Interfaces:**
- Consumes: tested branch tip SHAs and integration reports from Tasks 2-4
- Produces: one composed Windows app with all services reachable from popup/tray/windows

- [ ] **Step 1: Confirm main workspace stayed clean**

```powershell
git status --porcelain=v1
git branch --show-current
```

Expected: no output from status; branch `windows-app`.

- [ ] **Step 2: Merge Package, History, then Media commits without review**

```powershell
git merge --no-ff feature/windows-package -m "merge: add Windows package and update track"
git merge --no-ff feature/windows-history -m "merge: add Windows history settings recovery track"
git merge --no-ff feature/windows-media -m "merge: add Windows media translation track"
```

Expected: merges complete. Resolve only mechanical path conflicts according to ownership. Do not discard either side of semantic conflicts in shared files.

- [ ] **Step 3: Reconcile `AppConfig` once**

Extend existing record; do not create nested duplicate config models. Required integrated fields include existing fields plus speech rate and Start with Windows:

```csharp
public sealed record AppConfig(
    string ApiBaseUrl,
    string? ApiSpeechUrl,
    string Model,
    string SourceLang,
    string TargetLang,
    string NativeLang,
    IReadOnlyList<string> Languages,
    IReadOnlyList<string> TargetLanguages,
    int MaxTranslateLength,
    string SystemPrompt,
    string LearnPrompt,
    string SentenceLearnPrompt,
    string GrammarPrompt,
    bool AutoPrefetchSpeech,
    string SpeechSourceModel,
    string SpeechSourceModelVietnamese,
    string SpeechSourceModelChinese,
    string SpeechTargetModel,
    double SpeechRate,
    string? HistoryDirectory,
    bool StartWithWindows,
    HotkeyConfig Hotkey,
    UiConfig Ui);
```

Update `ConfigJson` defaults/migration and tests so old config without new fields loads with `SpeechRate = 1.0` and `StartWithWindows = false`. Keep API key absent from model and serialized JSON.

- [ ] **Step 4: Run config tests**

```powershell
dotnet test .\windows\tests\NTranslate.Core.Tests\NTranslate.Core.Tests.csproj -c Release --filter FullyQualifiedName~AppConfigTests
```

Expected: exit 0; tests prove old-config defaults, rate validation `0.5...1.5`, secret exclusion, and all existing validation.

- [ ] **Step 5: Compose services in `AppComposition`**

Construct one lifetime graph using `%LOCALAPPDATA%\NTranslate` or validated configured history root:

```csharp
var root = string.IsNullOrWhiteSpace(config.HistoryDirectory)
    ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NTranslate")
    : Path.GetFullPath(config.HistoryDirectory);
```

Wire one credential store, config store, history store, image normalizer, browser launcher, speech player/coordinator, update service/coordinator, crash log service, History window, Settings window, and Translation window. Ensure shutdown cancels requests, stops/disposes media, flushes completed writes, unregisters hotkey, removes tray, and closes all windows.

- [ ] **Step 6: Connect accepted results to history and speech**

Translation orchestration must produce explicit accepted metadata rather than scraping UI strings:

```csharp
public sealed record AcceptedTextTranslation(
    Guid RecordId,
    DateTimeOffset Timestamp,
    string SourceText,
    string ResultText,
    string SourceLanguage,
    string TargetLanguage,
    bool IsGrammar);
```

Persist accepted Translate/grammar before exposing bookmark association. Learn/image bypass append. Pass `RecordId` to source/result speech identities so validated audio attaches only to matching record.

- [ ] **Step 7: Wire tray and activation routes**

Tray actions must route to one instance of each UI:

```text
Open Translator        -> ShowManual()
Translation History    -> HistoryWindow.Activate()
Settings               -> SettingsWindow.Activate()
Check for Updates      -> manual update coordinator
Start with Windows     -> transactional setting toggle
Exit                   -> AppShutdown.Run()
```

Second-process activation continues opening translator through existing `UiActivationGate`.

- [ ] **Step 8: Merge XAML resources and accessibility behavior**

Register History, Settings, update, and recovery resources once in `App.xaml`. Preserve accessible names, keyboard accelerators, logical focus order, high-contrast resources, text scaling, and non-color-only status. Keep code-behind limited to window/Win32/clipboard stream bridges.

- [ ] **Step 9: Run integration-focused tests**

```powershell
dotnet test .\windows\NTranslate.slnx -c Release --filter "FullyQualifiedName~TranslationViewModelTests|FullyQualifiedName~History|FullyQualifiedName~Settings|FullyQualifiedName~Speech|FullyQualifiedName~Update|FullyQualifiedName~AppComposition|FullyQualifiedName~Xaml"
```

Expected: exit 0; zero failed tests.

- [ ] **Step 10: Commit integration**

```powershell
git add -- windows shared .gitignore README.md
git diff --cached --check
git commit -m @'
feat(windows): integrate v1 feature tracks

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

Expected: one integration commit; no generated artifacts or secrets staged.

### Task 6: Run Full Verification and One Integrated Review

**Files:**
- Review: complete diff from baseline SHA recorded in Task 1 through current HEAD
- Modify: only files needed for confirmed review findings
- Test: `windows/NTranslate.slnx`, script tests, repository diff

**Interfaces:**
- Consumes: fully integrated source tree
- Produces: reviewed tree with all confirmed findings fixed and full green evidence

- [ ] **Step 1: Run fresh full verification before review**

```powershell
dotnet restore .\windows\NTranslate.slnx --locked-mode
dotnet build .\windows\NTranslate.slnx -c Release --no-restore
dotnet test .\windows\NTranslate.slnx -c Release --no-build --no-restore
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1
git diff --check
git status --short
```

Expected: every command exits 0; status contains no uncommitted files. If lock mode is introduced only after package-track integration, lock files must already be committed.

- [ ] **Step 2: Perform exactly one integrated code review**

Review complete baseline-to-HEAD diff across these dimensions:

```text
correctness and parity
cancellation, generations, disposal, and race safety
history/config/audio data loss and path containment
credential/log/update/package security
WinUI threading, lifecycle, keyboard, and accessibility
reuse, needless dependencies, and needless abstractions
packaging, signing, installation, and rollback behavior
```

Every proposed finding must include file/line, concrete failure scenario, and evidence. Adversarially verify findings before changing code. Do not report style-only preferences.

- [ ] **Step 3: Fix every confirmed finding with focused regression tests**

For each confirmed finding:

```text
Add a deterministic failing test or script assertion.
Run it and capture expected failure.
Apply minimum fix.
Run focused test and capture pass.
```

Do not combine unrelated cleanup. Skip refactors without a demonstrated defect or direct simplification.

- [ ] **Step 4: Commit reviewed fixes**

```powershell
git add -- windows shared .gitignore README.md
git diff --cached --check
git commit -m @'
fix(windows): close integrated v1 review findings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
'@
```

If review confirms zero findings, do not create an empty commit.

- [ ] **Step 5: Rerun full verification after fixes**

```powershell
dotnet restore .\windows\NTranslate.slnx --locked-mode
dotnet build .\windows\NTranslate.slnx -c Release --no-restore
dotnet test .\windows\NTranslate.slnx -c Release --no-build --no-restore
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1
git diff --check
git status --porcelain=v1
```

Expected: all commands exit 0; final status output empty.

### Task 7: Package, Sign, Install, and Smoke-Test Windows v1

**Files:**
- Execute: `windows/install-app.ps1`
- Execute: `windows/packaging/scripts/Invoke-InstalledAppSmoke.ps1`
- Inspect: generated MSIX under `windows/artifacts/packages/`
- Do not commit: artifacts, certificates, PFX, passwords, smoke output

**Interfaces:**
- Consumes: reviewed and verified integrated source tree
- Produces: installed signed package and PASS/FAIL/BLOCKED smoke report

- [ ] **Step 1: Confirm host and signing prerequisites**

```powershell
dotnet --info
dotnet workload list
Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture
```

Expected: SDK `10.0.301` available, workload list empty, x64 Windows build `19045` or newer.

- [ ] **Step 2: Build, sign, trust development certificate, install, and launch**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\install-app.ps1 -Version 1.0.0 -TrustDevelopmentCertificate
```

Expected: exit 0 and literal output fields `Version`, `Build`, `Package`, `Identity`, `OS`, and `TargetTested`. Record values for final report.

- [ ] **Step 3: Verify installed identity and package signature independently**

```powershell
Get-AppxPackage -Name NinhNguyen375.NTranslate | Select-Object Name,Version,Architecture,Publisher,PackageFullName
Get-AuthenticodeSignature .\windows\artifacts\packages\NTranslate-1.0.0-win-x64.msix | Select-Object Status,StatusMessage,@{Name='Subject';Expression={$_.SignerCertificate.Subject}},@{Name='Thumbprint';Expression={$_.SignerCertificate.Thumbprint}}
```

Expected: package version `1.0.0.0`, architecture `X64`, publisher `CN=Ninh Nguyen`, signature status `Valid`.

- [ ] **Step 4: Run automated installed-app smoke suite**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-InstalledAppSmoke.ps1 -PackageName NinhNguyen375.NTranslate -ExpectedVersion 1.0.0.0 -ResultsPath .\windows\artifacts\smoke
```

Expected: exit 0. Required checks: identity/version/signature, launch, tray, second-launch activation, manual translation fixture, copy, history, bookmark, Settings secret exclusion, update fixture, invalid-package rejection, exit, and log redaction.

- [ ] **Step 5: Run manual local smoke matrix**

Record each item as `PASS`, `FAIL: <exact symptom>`, or `BLOCKED: <exact reason>`:

```text
selection capture in native app
selection capture in browser
clipboard image translation
source TTS play/pause/resume/rate
result TTS play/pause/resume/rate
multi-monitor popup placement
high-contrast keyboard navigation
text scaling and focus order
live chat/TTS endpoint
Windows 11 Fluent visual check
```

Live endpoint may be `BLOCKED` when no valid credential/model exists. Windows 11 visual check must be `BLOCKED: host is Windows 10 build 19045` on current host. Other local checks must not be marked passed without execution.

- [ ] **Step 6: Inspect repository safety after installation**

```powershell
git status --short
git ls-files | Select-String -Pattern '\.(pfx|cer|msix)$|windows/artifacts|config\.json$'
git grep -n -I -E 'Bearer [A-Za-z0-9._-]+|apiKey["'"']?\s*[:=]\s*["'"'][^"'"']+["'"']'
```

Expected: no tracked artifact, certificate, user config, or real secret. Generated untracked output must be covered by `.gitignore`, so `git status --short` remains empty.

- [ ] **Step 7: Report exact completion evidence**

Report:

```text
commit SHA
.NET build/test passed/failed/skipped counts
script-test result
MSIX Version and Build
MSIX filename and full path
installed package identity
signature status, subject, and thumbprint
installed smoke result path and counts
manual smoke PASS/FAIL/BLOCKED matrix
review finding count and fix count
```

Do not push or create a PR unless user explicitly requests it after seeing results.
