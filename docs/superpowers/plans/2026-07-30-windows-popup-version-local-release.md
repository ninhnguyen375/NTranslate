# Windows Popup Version and Local Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show `NTranslate 1.2.3` in Windows popup, make manual update check execute immediately, and remove GitHub Actions release automation.

**Architecture:** Resolve package version once in `AppComposition`, pass it to popup and updater, and bind popup title to a formatted string. Remove blocking checking dialog so network check runs before result dialog. Delete workflow and its dedicated script test; keep local installer/release conventions.

**Tech Stack:** C# 14, WinUI 3 XAML, xUnit, PowerShell packaging tests, GitHub CLI release flow.

## Global Constraints

- Popup title format: `NTranslate 1.2.3`.
- Version source: running package version, with existing assembly fallback.
- Update tags remain `windows-v<version>`.
- Release assets remain `NTranslate-<version>-win-x64-setup.exe` and matching `.sha256`.
- No new dependency or unrelated refactor.

---

### Task 1: Popup version title

**Files:**
- Modify: `windows/tests/NTranslate.App.Tests/Popup/TranslationWindowXamlTests.cs`
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml`
- Modify: `windows/src/NTranslate.App/Popup/TranslationWindow.xaml.cs`
- Modify: `windows/src/NTranslate.App/AppComposition.cs`

**Interfaces:**
- Consumes: `CurrentVersionResolver.Resolve(...) -> SemanticVersion`.
- Produces: `TranslationWindow(..., SemanticVersion version, ...)` and `TitleText` formatted as `NTranslate {version}`.

- [ ] Add failing source/XAML assertions requiring title binding and version formatting.
- [ ] Run targeted popup tests; expect failure because title is hard-coded and constructor has no version.
- [ ] Resolve `currentVersion` before popup construction, pass it to `TranslationWindow`, expose formatted title, and bind title `Text`.
- [ ] Run targeted popup and app tests; expect pass.

### Task 2: Non-blocking manual update check

**Files:**
- Modify: `windows/tests/NTranslate.App.Tests/Updates/UpdateCoordinatorTests.cs`
- Modify: `windows/src/NTranslate.App/Updates/ManualUpdateFlow.cs`

**Interfaces:**
- Consumes: `UpdateCoordinator.CheckAsync(bool manual, CancellationToken token)`.
- Produces: `ManualUpdateFlow.RunAsync` checks first, then shows exactly one result dialog; installation still requires `true` from available-result dialog.

- [ ] Add failing test with dialog completion left blocked; assert update check starts before dialog invocation can block.
- [ ] Run targeted update test; expect timeout/failure because checking dialog runs first.
- [ ] Delete preliminary checking dialog call; retain result dialog and explicit install confirmation.
- [ ] Run all update tests; expect pass.

### Task 3: Remove GitHub Actions release automation

**Files:**
- Delete: `.github/workflows/windows-release.yml`
- Delete: `windows/packaging/tests/ReleaseWorkflow.Tests.ps1`
- Modify: `windows/README.md`

**Interfaces:**
- Keeps: `windows/install-app.ps1` local build/package/checksum output.
- Removes: hosted build/upload workflow and workflow-only assertions.

- [ ] Delete workflow and dedicated workflow test.
- [ ] Replace README GitHub Actions wording with local build then `gh release create/view/upload` workflow already used by maintainer.
- [ ] Run packaging script tests; expect pass without workflow-specific test.

### Task 4: Full verification and install

**Files:** none beyond prior tasks.

- [ ] Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1`.
- [ ] Run `dotnet test .\windows\NTranslate.slnx --no-restore`.
- [ ] Check installed MSIX version; if manifest version is not greater, report blocker rather than bumping unrequested version.
- [ ] Run `.\install-app.ps1` when install version permits.
- [ ] Report exact test totals, Version, Build, package path, and any install blocker/failure.
