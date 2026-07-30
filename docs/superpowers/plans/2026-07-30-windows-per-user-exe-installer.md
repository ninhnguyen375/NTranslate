# Windows Per-User EXE Installer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Windows MSIX release/install/update path with unsigned per-user Inno Setup EXE plus SHA-256 sidecar.

**Architecture:** Keep GitHub release discovery and bounded downloader. Select exact setup/checksum asset pair, verify downloaded EXE with BCL SHA-256, then launch Inno silently. Replace MSIX packaging scripts with Inno compile/install/smoke flow and GitHub Actions release workflow.

**Tech Stack:** .NET 10, C# 14, PowerShell 5.1, Inno Setup 6, GitHub Actions, xUnit.

## Global Constraints

- Branch remains `windows-app`; never target `main`.
- Artifacts: `NTranslate-<version>-win-x64-setup.exe` and matching `.sha256`.
- Install path: `{localappdata}\Programs\NTranslate`; `PrivilegesRequired=lowest`.
- No certificate creation, TrustedPeople changes, elevation, HKLM writes, or automatic MSIX removal.
- Legacy identity `NinhNguyen375.NTranslate` blocks install with manual-uninstall guidance.
- Setup max 512 MiB; checksum max 4 KiB; HTTPS GitHub hosts remain allowlisted.
- Use stdlib/BCL only; no new .NET dependency.

---

### Task 1: Select installer asset pair

**Files:**
- Modify: `windows/src/NTranslate.Core/Updates/UpdatePolicy.cs`
- Test: `windows/tests/NTranslate.Core.Tests/Updates/UpdatePolicyTests.cs`

**Interfaces:**
- Produces `WindowsUpdate` containing installer and checksum names/URLs.

- [ ] Add failing tests for exact case-sensitive setup + sidecar pair, missing/duplicate/wrong-version assets, and highest valid stable release.
- [ ] Run `dotnet test windows/tests/NTranslate.Core.Tests/NTranslate.Core.Tests.csproj --filter FullyQualifiedName~UpdatePolicyTests` and confirm failure.
- [ ] Change `WindowsUpdatePolicy.Select` to require `NTranslate-<version>-win-x64-setup.exe` plus `.sha256`.
- [ ] Run focused and full Core tests.

### Task 2: Verify checksum sidecar

**Files:**
- Replace: `windows/src/NTranslate.Platform/Updates/MsixPackageVerifier.cs` with `InstallerChecksumVerifier.cs`
- Replace test: `windows/tests/NTranslate.Platform.Tests/Updates/MsixPackageVerifierTests.cs` with `InstallerChecksumVerifierTests.cs`

**Interfaces:**
- Produces `IInstallerChecksumVerifier.VerifyAsync(string installerPath, string checksumPath, string expectedInstallerName, SemanticVersion expectedVersion, CancellationToken token)`.

- [ ] Add failing tests for missing/reparse files, malformed digest, wrong/case-changed/path filename, multiple records, mismatch, cancellation, and valid upper/lowercase digest.
- [ ] Confirm focused tests fail.
- [ ] Parse one `<64 hex> *<exact filename>` record, hash through `SHA256.HashDataAsync`, compare via `CryptographicOperations.FixedTimeEquals`.
- [ ] Delete MSIX ZIP/XML/WinTrust code; run focused and full Platform tests.

### Task 3: Bound downloads by asset type

**Files:**
- Modify: `windows/src/NTranslate.Core/Updates/GitHubReleaseClient.cs`
- Test: `windows/tests/NTranslate.Core.Tests/Updates/GitHubReleaseClientTests.cs`

- [ ] Add failing tests for caller-provided 512 MiB and 4 KiB limits while preserving URL, redirect, partial cleanup, and cancellation checks.
- [ ] Generalize `DownloadAsync` with `long maximumBytes`; reject non-positive limits.
- [ ] Run focused and full Core tests.

### Task 4: Install verified update

**Files:**
- Modify: `windows/src/NTranslate.App/Updates/UpdateCoordinator.cs`
- Modify: `windows/src/NTranslate.App/AppComposition.cs`
- Test: `windows/tests/NTranslate.App.Tests/Updates/UpdateCoordinatorTests.cs`
- Test: `windows/tests/NTranslate.App.Tests/AppCompositionTests.cs`

- [ ] Add failing tests proving setup then checksum download, distinct limits, verify-before-launch, no shutdown on failure, exact silent args, and shutdown once after successful launch.
- [ ] Inject generalized downloader, `IInstallerChecksumVerifier`, launcher, and existing app shutdown action.
- [ ] Launch verified path using `ProcessStartInfo.ArgumentList`: `/NORESTART /VERYSILENT /SUPPRESSMSGBOXES /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS`; never request elevation.
- [ ] Wire composition; run focused and full App tests.

### Task 5: Add Inno installer

**Files:**
- Create: `windows/packaging/NTranslate.iss`
- Create: `windows/packaging/tests/Installer.Tests.ps1`

- [ ] Write failing static policy test for `PrivilegesRequired=lowest`, `{localappdata}\Programs\NTranslate`, x64, exact output name, close/restart, shortcuts, uninstall, and legacy identity guard; reject HKLM, cert stores, and `Remove-AppxPackage`.
- [ ] Add minimal `.iss` using `AppVersion`, `SourceDir`, `OutputDir` defines and stable `AppId`.
- [ ] Add hidden current-user `Get-AppxPackage -Name NinhNguyen375.NTranslate` guard that stops with manual uninstall guidance.
- [ ] Compile with Inno Setup and verify exact output filename.

### Task 6: Convert local install scripts

**Files:**
- Modify: `windows/install-app.ps1`
- Modify: `install-app.ps1`
- Modify: `windows/packaging/tests/Install.Tests.ps1`
- Modify: `windows/packaging/tests/RootInstall.Tests.ps1`
- Modify: `windows/packaging/scripts/Invoke-InstalledAppSmoke.ps1`
- Modify: `windows/packaging/tests/Invoke-InstalledAppSmoke.Tests.ps1`

- [ ] Rewrite failing tests around restore/build/test/publish/ISCC/hash/install order, exact artifacts, direct installed EXE smoke, and absence of trust/cert code.
- [ ] Replace MakeAppx/SignTool/Add-AppxPackage flow with publish, ISCC, `Get-FileHash`, sidecar, silent setup, `%LOCALAPPDATA%\Programs\NTranslate\NTranslate.App.exe` verification.
- [ ] Make root wrapper accept strict required `-Version`; remove manifest and trust switch.
- [ ] Run all packaging script tests.

### Task 7: Remove obsolete MSIX path

**Files:**
- Delete: `windows/packaging/manifest/AppxManifest.xml`
- Delete: `windows/packaging/scripts/New-PackageLayout.ps1`
- Delete: `windows/packaging/scripts/Manage-DevelopmentCertificate.ps1`
- Delete: `windows/packaging/tests/Certificate.Tests.ps1`
- Delete: `windows/packaging/tests/Manifest.Tests.ps1`
- Delete MSIX-only square/store PNG assets; keep `NTranslate.ico`.

- [ ] Search all MSIX/cert references and classify migration-only matches.
- [ ] Delete obsolete files and references.
- [ ] Run solution build/tests and script tests.

### Task 8: Add GitHub Actions release

**Files:**
- Create: `.github/workflows/windows-release.yml`
- Create: `windows/packaging/tests/ReleaseWorkflow.Tests.ps1`

- [ ] Add failing static tests for `windows-latest`, locked restore, build/test/publish order, Inno compile, SHA-256, exact two assets, and no MSIX/cert/signing steps.
- [ ] Add release-published workflow and manual artifact build path; release upload gets only `contents: write`.
- [ ] Reuse repository packaging command where possible; run script tests.

### Task 9: Update docs

**Files:**
- Modify: `windows/README.md`
- Modify: `README.md`
- Modify release skill only where Windows artifact assumptions exist.

- [ ] Document per-user path, no admin/cert, SmartScreen flow, manual legacy MSIX uninstall, preserved app data, exact artifacts, local commands, and checksum trust limit.
- [ ] Keep macOS instructions unchanged.

### Task 10: Full verification

- [ ] Run `dotnet restore windows/NTranslate.slnx --locked-mode`.
- [ ] Run `dotnet build windows/NTranslate.slnx -c Release --no-restore`.
- [ ] Run `dotnet test windows/NTranslate.slnx -c Release --no-build --no-restore`.
- [ ] Run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File windows/packaging/scripts/Invoke-ScriptTests.ps1`.
- [ ] Run root installer with current version; verify installer, checksum, per-user install, smoke, and app launch.
- [ ] Audit remaining `TrustedPeople`, MakeAppx, SignTool, `.msix`, and `Add-AppxPackage` matches; permit only explicit legacy migration text/tests.
- [ ] Run `git diff --check` and inspect complete diff.
