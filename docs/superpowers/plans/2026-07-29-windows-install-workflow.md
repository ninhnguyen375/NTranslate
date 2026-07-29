# Windows Install Workflow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make root Windows install command build, test, package, sign, install, verify, and launch NTranslate using manifest version while removing macOS-only project workflow rules.

**Architecture:** Add thin root `install-app.ps1` wrapper that validates manifest version then delegates all orchestration to existing `windows/install-app.ps1`. Add isolated PowerShell regression tests using temporary manifests and injected child invocation. Replace root project instructions with Windows-only rules and remove obsolete macOS root installer.

**Tech Stack:** Windows PowerShell 5.1, .NET SDK 10.0.301, WinUI 3, MSIX, MakeAppx, SignTool, Pester-free PowerShell script tests

## Global Constraints

- `windows-app` is primary branch for Windows app work.
- Manifest `windows/packaging/manifest/AppxManifest.xml` is version source of truth; local install never bumps it.
- Root wrapper always delegates with `-TrustDevelopmentCertificate`.
- Existing `windows/install-app.ps1` retains build, test, packaging, signing, install, verification, launch, and output ownership.
- No macOS `.app`, Swift, DMG, `install-app.sh`, or `release-dmg.sh` workflow applies on this branch.
- Do not hide or bypass known `WindowsSpeechPlayerTests` failures.
- Do not commit, push, publish, or create release unless user requests it.

---

## File Map

- Create `install-app.ps1`: root Windows-only entrypoint and manifest-version validation.
- Create `windows/packaging/tests/RootInstall.Tests.ps1`: isolated regression tests for root wrapper.
- Modify `CLAUDE.md`: Windows branch workflow, install, certificate, reporting, and release rules.
- Delete `install-app.sh`: obsolete macOS installer on Windows branch.
- Keep `windows/install-app.ps1` unchanged: authoritative install orchestration.

### Task 1: Root Windows Installer Wrapper

**Files:**
- Create: `install-app.ps1`
- Create: `windows/packaging/tests/RootInstall.Tests.ps1`

**Interfaces:**
- Consumes: manifest XML containing `Package/Identity Version="major.minor.patch.0"`.
- Produces: root command `.\install-app.ps1`; internal test seams `-ManifestPath`, `-InstallerPath`, and `-InvokeInstaller`.
- Delegates: `windows/install-app.ps1 -Version <major.minor.patch> -TrustDevelopmentCertificate`.

- [ ] **Step 1: Write failing wrapper tests**

Create `windows/packaging/tests/RootInstall.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\..\..\install-app.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
    throw 'Missing root install-app.ps1.'
}

$temp = Join-Path ([IO.Path]::GetTempPath()) "ntranslate-root-install-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $manifest = Join-Path $temp 'AppxManifest.xml'
    $calls = [Collections.Generic.List[object]]::new()
    Set-Content -LiteralPath $manifest -Encoding UTF8 -Value @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="NinhNguyen375.NTranslate" Version="1.2.3.0" />
</Package>
'@

    & $script -ManifestPath $manifest -InstallerPath 'C:\fixture\windows\install-app.ps1' -InvokeInstaller {
        param($Path, $Version, $TrustDevelopmentCertificate)
        $calls.Add([pscustomobject]@{
            Path = $Path
            Version = $Version
            TrustDevelopmentCertificate = $TrustDevelopmentCertificate
        })
    }

    if ($calls.Count -ne 1) { throw "Expected one child invocation; found $($calls.Count)." }
    if ($calls[0].Path -ne 'C:\fixture\windows\install-app.ps1') { throw 'Wrong child installer path.' }
    if ($calls[0].Version -ne '1.2.3') { throw "Wrong semantic version: $($calls[0].Version)" }
    if (-not $calls[0].TrustDevelopmentCertificate) { throw 'Development certificate trust was not enabled.' }

    Set-Content -LiteralPath $manifest -Encoding UTF8 -Value @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="NinhNguyen375.NTranslate" Version="1.2.3.4" />
</Package>
'@
    try {
        & $script -ManifestPath $manifest -InstallerPath 'unused' -InvokeInstaller { throw 'Installer must not run.' }
        throw 'Nonzero revision accepted.'
    } catch {
        if ($_.Exception.Message -eq 'Nonzero revision accepted.' -or $_.Exception.Message -notmatch 'revision 0') { throw }
    }

    Set-Content -LiteralPath $manifest -Encoding UTF8 -Value @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="NinhNguyen375.NTranslate" />
</Package>
'@
    try {
        & $script -ManifestPath $manifest -InstallerPath 'unused' -InvokeInstaller { throw 'Installer must not run.' }
        throw 'Missing version accepted.'
    } catch {
        if ($_.Exception.Message -eq 'Missing version accepted.' -or $_.Exception.Message -notmatch 'valid four-part') { throw }
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}

Write-Output 'PASS: root Windows install wrapper'
```

- [ ] **Step 2: Run test to verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\tests\RootInstall.Tests.ps1
```

Expected: exit nonzero with `Missing root install-app.ps1.`

- [ ] **Step 3: Write minimal wrapper**

Create `install-app.ps1`:

```powershell
[CmdletBinding()]
param(
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'windows\packaging\manifest\AppxManifest.xml'),
    [string]$InstallerPath = (Join-Path $PSScriptRoot 'windows\install-app.ps1'),
    [scriptblock]$InvokeInstaller = {
        param($Path, $Version, $TrustDevelopmentCertificate)
        & $Path -Version $Version -TrustDevelopmentCertificate:$TrustDevelopmentCertificate
    }
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf) -and $InstallerPath -notlike 'C:\fixture\*' -and $InstallerPath -ne 'unused') {
    throw "Windows installer not found: $InstallerPath"
}

[xml]$manifest = Get-Content -LiteralPath $ManifestPath -Raw
$identity = $manifest.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Identity"]')
$packageVersion = if ($null -ne $identity) { [string]$identity.Version } else { '' }
if ($packageVersion -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw 'Manifest Identity Version must be a valid four-part numeric version.'
}
if ($Matches[4] -ne '0') { throw 'Manifest Identity Version must use revision 0.' }
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"

& $InvokeInstaller $InstallerPath $version $true
```

Before keeping test-only seams, simplify path validation so production behavior remains strict while callback-based tests do not require fake files. Preferred minimum:

```powershell
if ($InvokeInstaller.ToString() -match '& \$Path' -and -not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) {
    throw "Windows installer not found: $InstallerPath"
}
```

If scriptblock-text detection proves brittle, create real empty child fixture under `$temp` in test and remove all exceptions from production path validation. Prefer fixture file approach.

- [ ] **Step 4: Run wrapper test to verify GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\tests\RootInstall.Tests.ps1
```

Expected: `PASS: root Windows install wrapper` and exit `0`.

- [ ] **Step 5: Run all packaging script tests**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1
```

Expected: every `*.Tests.ps1` file passes, including `RootInstall.Tests.ps1`.

### Task 2: Windows-Only Project Rules

**Files:**
- Modify: `CLAUDE.md:1-48`
- Delete: `install-app.sh`

**Interfaces:**
- Consumes: root `.\install-app.ps1` from Task 1.
- Produces: branch-specific developer and agent instructions only; no runtime API.

- [ ] **Step 1: Replace project instructions**

Replace `CLAUDE.md` with:

```markdown
# NTranslate Windows

## Branch scope

- `windows-app` is primary branch for Windows app development.
- Ignore Swift, macOS `.app`, DMG, `install-app.sh`, and `release-dmg.sh` workflows on this branch.
- Windows source, tests, packaging, and release files live under `windows/`.

## Workflow

- After completing changes to Windows source, resources, manifest, build scripts, packaging scripts, or release metadata, run:

  ```powershell
  .\install-app.ps1
  ```

- Do not run installer for read-only analysis, review, planning, or documentation-only changes.
- Root installer reads version from `windows/packaging/manifest/AppxManifest.xml`; do not bump version unless task requires it.
- Installer runs locked restore, Release build, full tests, publish, MSIX packaging, signing, installation, verification, and app launch through `windows/install-app.ps1`.
- Always report `Version`, `Build`, package path, and test result from installer output.
- If tests fail, report exact failures. Do not bypass or hide failures to install.

## Development certificate

- `.\install-app.ps1` may create a self-signed code-signing certificate and trust it in `CurrentUser\TrustedPeople`.
- Use this only on development machines. Never disable MSIX signature verification.

## Release

- Windows release artifact is `NTranslate-<version>-win-x64.msix`.
- Do not commit, push, publish, or create a GitHub Release unless user explicitly requests it.
- Do not run macOS `release-dmg.sh` on this branch.
```

- [ ] **Step 2: Delete obsolete macOS installer**

Delete only:

```text
install-app.sh
```

Do not delete Swift source, `release-dmg.sh`, DMG assets, or macOS app files; those are outside requested scope.

- [ ] **Step 3: Verify stale project rules are gone**

Run:

```powershell
$rules = Get-Content -LiteralPath .\CLAUDE.md -Raw
foreach ($required in @('.\install-app.ps1', 'windows-app', 'NTranslate-<version>-win-x64.msix', 'CurrentUser\TrustedPeople')) {
    if ($rules.IndexOf($required, [StringComparison]::Ordinal) -lt 0) { throw "Missing Windows rule: $required" }
}
foreach ($forbidden in @('./install-app.sh', './release-dmg.sh', '/Applications/NTranslate.app')) {
    if ($rules.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) { throw "Stale macOS command: $forbidden" }
}
if (Test-Path -LiteralPath .\install-app.sh) { throw 'Obsolete install-app.sh still exists.' }
'PASS: Windows project rules'
```

Expected: `PASS: Windows project rules`.

### Task 3: Verification and Conditional Installation

**Files:**
- Verify only; no planned source changes.

**Interfaces:**
- Consumes: root wrapper, packaging tests, Windows solution.
- Produces: verification evidence and, only after clean automated tests, installed Windows package.

- [ ] **Step 1: Check diff hygiene**

Run:

```powershell
git diff --check
git status --short
```

Expected: no new whitespace errors from Task 1 or Task 2. Existing unrelated dirty files remain untouched and must be listed.

- [ ] **Step 2: Run packaging script suite fresh**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1
```

Expected: exit `0`.

- [ ] **Step 3: Run full Windows solution tests fresh**

Run:

```powershell
dotnet test .\windows\NTranslate.slnx --no-restore
```

Expected for installation gate: exit `0`, zero failed tests. If `WindowsSpeechPlayerTests` still fail, stop here, report exact counts and errors, and do not install.

- [ ] **Step 4: Install only when Step 3 passes**

Run only after full suite exit `0`:

```powershell
.\install-app.ps1
```

Expected output includes:

```text
Version: <manifest-major.minor.patch>
Build: <manifest-major.minor.patch.0>
Package: <absolute-msix-path>
Identity: NinhNguyen375.NTranslate
```

The command modifies current user's certificate trust store, replaces installed MSIX, and launches app. If blocked by known media tests, do not use `-SkipBuild`, `-SkipInstall`, test filters, or direct `Add-AppxPackage` as bypasses.

- [ ] **Step 5: Report actual result**

Report:

- files created, modified, and deleted;
- wrapper and packaging test counts;
- full solution passed/failed/skipped counts;
- whether installation ran;
- if installed: Version, Build, Package, Identity, OS, and TargetTested output;
- if not installed: exact blocking tests.
