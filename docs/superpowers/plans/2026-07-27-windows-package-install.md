# Windows Package, Update, and Installation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add verified GitHub updates, signed x64 MSIX packaging, local certificate workflow, installation, accessibility checks, docs, and installed-app smoke tests.

**Architecture:** Core parses/releases/selects updates. Platform verifies MSIX and invokes App Installer. PowerShell builds/tests/packages/signs/installs without Visual Studio workloads. Installed smoke tests verify package behavior.

**Tech Stack:** .NET SDK 10.0.301, WinUI 3, Windows App SDK, PowerShell 5.1, Windows SDK Build Tools, MakeAppx, SignTool, GitHub Releases API

## Global Constraints

- Host/support floor: Windows 10 22H2 build 19045+, x64.
- Target `net10.0-windows10.0.19041.0`; MSIX MinVersion `10.0.19045.0`.
- Package identity `NinhNguyen375.NTranslate`; publisher `CN=Ninh Nguyen`.
- Asset `NTranslate-<semver>-win-x64.msix`.
- No workload install, elevation script, signature bypass, private key/PFX/password/build output in git.
- Updater verifies signature, identity, publisher, architecture, and version before App Installer handoff.
- Self-signed trust only CurrentUser TrustedPeople and only when explicit install script switch is used.

---

### Task 1: Pin Windows toolchain

- [ ] Add `windows/global.json` locking `10.0.301`, central package versions, lock files, common target/RID/warnings settings. Resolve highest stable package versions with `dotnet package search`; commit literal versions.
- [ ] Generate lock files with one unlocked restore, then verify `dotnet restore .\windows\NTranslate.slnx --locked-mode` and Release build work while workload list remains empty.
- [ ] Add install-script guard rejecting other SDKs; never invoke workloads.
- [ ] Commit `build(windows): pin SDK and package toolchain`.

### Task 2: Add semantic version and asset policy

```csharp
public readonly record struct SemanticVersion(int Major, int Minor, int Patch) : IComparable<SemanticVersion>;
public sealed record GitHubAsset(string Name, Uri DownloadUrl);
public sealed record GitHubRelease(string Tag, string Notes, bool Draft, bool Prerelease, IReadOnlyList<GitHubAsset> Assets);
public sealed record WindowsUpdate(SemanticVersion Version, string Tag, string Notes, Uri DownloadUrl, string AssetName);
```

- [ ] Write tests accepting `1.2.3`, `v1.2.3`; rejecting incomplete/four-part/prerelease/malformed; numeric compare; exact case-sensitive x64 filename; reject draft/prerelease/same/older/multiple/mismatch.
- [ ] Run; expect FAIL.
- [ ] Implement strict parser/selector; filename version must equal tag.
- [ ] Run; expect PASS.
- [ ] Commit `feat(windows): add release version and asset policy`.

### Task 3: Add GitHub release/download client

- [ ] Write stub-handler tests for exact GitHub headers/API URL, JSON parsing, missing body, non-2xx sanitized error, invalid JSON/URL/host, `.partial` atomic download, cancellation cleanup/preservation.
- [ ] Run; expect FAIL.
- [ ] Implement `ResponseHeadersRead`; only HTTPS GitHub/object hosts; stream to partial, flush, atomic final replace after success.
- [ ] Run; expect PASS.
- [ ] Commit `feat(windows): fetch and download GitHub releases`.

### Task 4: Add MSIX verifier and update UI

```csharp
public sealed record VerifiedMsixPackage(string Path, string IdentityName, string Publisher, SemanticVersion Version, string Architecture);
public interface IMsixPackageVerifier { Task<VerifiedMsixPackage> VerifyAsync(string packagePath, CancellationToken token); }
```

- [ ] Write tests for missing/wrong extension/reparse/unsigned/invalid ZIP/missing or duplicate manifest/wrong identity/publisher/arch/version and valid signed generated fixture.
- [ ] Run; expect FAIL.
- [ ] Verify WinTrust first, then bounded ZIP `AppxManifest.xml` with DTD prohibited. Require exact constants.
- [ ] Add coordinator tests for silent/manual states, duplicate prevention, cancellation idle, verified-only Install. Implement plain-text release notes and `Process.Start(...UseShellExecute=true)` MSIX handoff; no `Add-AppxPackage` inside app.
- [ ] Run full tests; expect PASS.
- [ ] Commit `feat(windows): add verified App Installer update flow`.

### Task 5: Define MSIX manifest/layout

- [ ] Add one canonical manifest with identity/publisher, `1.0.0.0`, x64, Windows.Desktop MinVersion 19045, tested 22621, full-trust desktop executable, least capabilities.
- [ ] Link manifest from App project; do not duplicate content. Add deterministic publish/layout/package paths and strict semver-to-four-part conversion.
- [ ] Extend `.gitignore` for artifacts/bin/obj/certificates/PFX/CER/MSIX.
- [ ] Verify `dotnet publish` produces `NTranslate.App.exe`; validate manifest before packaging.
- [ ] Commit `build(windows): define x64 MSIX package`.

### Task 6: Add development certificate scripts

- [ ] Write PowerShell tests: create/reuse correct cert, ignore wrong/missing-private-key cert, import public cert to CurrentUser TrustedPeople, cleanup exact thumbprint, no password output, valid signed package signer.
- [ ] Implement RSA 3072 SHA-256 Code Signing cert subject `CN=Ninh Nguyen` under CurrentUser My. Store output under `%LOCALAPPDATA%\NTranslate\Signing`; accept `SecureString`; export public CER. Trust only with explicit switch.
- [ ] Run tests; expect PASS and cleanup.
- [ ] Commit `build(windows): manage local MSIX signing certificate`.

### Task 7: Add `windows/install-app.ps1`

Parameters: semantic version, Release, win-x64, optional cert/PFX/SecureString, `TrustDevelopmentCertificate`, diagnostic-only skip switches.

- [ ] Write injected-tool script tests for command order, fail-fast, SDK/OS guards, password redaction, no workload command, exact final output.
- [ ] Implement sequence: locked restore, build, tests, publish, clean layout, manifest version, resolve MakeAppx/SignTool from restored SDK Build Tools package, pack, sign, verify, trust gate, `Add-AppxPackage -ForceApplicationShutdown`, query package, launch AppsFolder.
- [ ] Zero unmanaged plaintext password buffer in `finally`.
- [ ] Print `Version`, `Build`, `Package`, `Identity`, `OS`, `TargetTested`.
- [ ] Run script tests; expect PASS.
- [ ] Commit `build(windows): package sign and install MSIX`.

### Task 8: Add accessibility and installed smoke tests

- [ ] Add XAML checks: all icon buttons named/tooltipped/focusable; labels; assertive validation/polite result; logical tabs; theme resources; no color-only state; shortcuts; safe initial dialog focus.
- [ ] Add installed UIA tests for named controls, unique automation IDs, Tab progression, keyboard actions, update dialog states.
- [ ] Add isolated smoke fixture for package/version/signature/launch/tray/single instance/manual translation fixture/copy/history/bookmark/settings secret exclusion/mock update/invalid package rejection/exit/log redaction.
- [ ] Run against installed package; expect automated smoke/accessibility PASS. Keep real selection/image/TTS/multi-monitor/high-contrast/text-scale/live API/GitHub checks manual and report exact PASS/FAIL/BLOCKED.
- [ ] Commit `test(windows): add installed MSIX smoke suite`.

### Task 9: Document Windows install/release

- [ ] Update top README as platform index without removing macOS instructions.
- [ ] Add Windows README, installation, release, accessibility matrix. Include self-signed CER import to CurrentUser TrustedPeople, uninstall, Authenticode inspection, certificate thumbprint warning, and no signature-disable workaround.
- [ ] Commit `docs(windows): document MSIX install release and accessibility`.

## Final Verification and Installation

```powershell
dotnet --info
dotnet workload list
dotnet restore .\windows\NTranslate.slnx --locked-mode
dotnet build .\windows\NTranslate.slnx -c Release --no-restore
dotnet test .\windows\NTranslate.slnx -c Release --no-build --no-restore
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\install-app.ps1 -Version 1.0.0 -TrustDevelopmentCertificate
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-InstalledAppSmoke.ps1 -PackageName NinhNguyen375.NTranslate -ExpectedVersion 1.0.0.0 -ResultsPath .\windows\artifacts\smoke
Get-AppxPackage -Name NinhNguyen375.NTranslate | Select-Object Name,Version,Architecture,Publisher,PackageFullName
Get-AuthenticodeSignature .\windows\artifacts\packages\NTranslate-1.0.0-win-x64.msix | Select-Object Status,StatusMessage,@{Name='Subject';Expression={$_.SignerCertificate.Subject}},@{Name='Thumbprint';Expression={$_.SignerCertificate.Thumbprint}}
```

Expected: SDK 10.0.301, workload list empty, zero build/test failure, x64 package publisher exact, signature Valid, package installed/updated, launch and automated smoke pass. Windows 11 visual check remains `BLOCKED: host is Windows 10 build 19045` until run on Windows 11.
