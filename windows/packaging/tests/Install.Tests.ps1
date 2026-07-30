Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\..\\install-app.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Missing windows/install-app.ps1.' }
$text = Get-Content -LiteralPath $script -Raw

# Pinned build/packaging literals that must remain
foreach ($literal in @('10.0.301', '19041', '--locked-mode', '--no-restore', 'Release', 'win-x64', 'NTranslate.iss', 'ISCC', 'Get-FileHash', 'SHA256', 'sha256', 'win-x64-setup', 'VERYSILENT', 'SUPPRESSMSGBOXES', 'NORESTART', 'CLOSEAPPLICATIONS', 'RESTARTAPPLICATIONS', 'Get-Process -Name NTranslate.App', 'Version:', 'Build:', 'Package:', 'OS:', 'AMD64')) {
    if ($text.IndexOf($literal, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "Missing pinned install behavior: $literal" }
}
if ($text -match 'dotnet\s+workload') { throw 'Workload commands forbidden.' }
if ($text -match 'MakeAppx|SignTool|Add-AppxPackage|TrustDevelopmentCertificate|TrustedPeople|ZeroFreeBSTR|Get-AuthenticodeSignature') { throw 'MSIX/cert code must be removed from install-app.ps1.' }

# Functional: restore/build/test/publish/ISCC/hash/verify order
$isccCalls = [Collections.Generic.List[object]]::new()
$hashCalls = [Collections.Generic.List[string]]::new()
& $script -Version '1.2.3' -NativeArchitecture AMD64 `
    -InvokeTool { param($File, $Arguments) } `
    -InvokeIscc {
        param($Iss, $Ver, $Src, $Out)
        $isccCalls.Add($Ver)
        New-Item -ItemType Directory -Force -Path $Out | Out-Null
        Set-Content -LiteralPath (Join-Path $Out "NTranslate-$Ver-win-x64-setup.exe") -Value 'fixture'
    } `
    -GetFileHash {
        param($Path)
        $hashCalls.Add($Path)
        'a' * 64
    } `
    -SkipBuild -SkipInstall

if ($isccCalls.Count -ne 1) { throw 'ISCC was not invoked.' }
if ($hashCalls.Count -ne 1) { throw 'Get-FileHash was not invoked.' }

# ARM64 rejected
try {
    & $script -Version '1.2.3' -NativeArchitecture ARM64 -InvokeTool { } -InvokeIscc { param($a,$b,$c,$d) } -GetFileHash { 'a'*64 } -SkipBuild -SkipInstall
    throw 'ARM64 accepted.'
} catch { if ($_.Exception.Message -eq 'ARM64 accepted.') { throw }; if ($_.Exception.Message -notmatch 'x64') { throw } }

Write-Output 'PASS: install orchestration security and order'
