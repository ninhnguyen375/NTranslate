Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\..\install-app.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Missing windows/install-app.ps1.' }
$text = Get-Content -LiteralPath $script -Raw
foreach ($literal in @('10.0.301', '19045', '--locked-mode', '--no-restore', 'Release', 'win-x64', 'MakeAppx.exe', 'SignTool.exe', 'Add-AppxPackage', '-ForceApplicationShutdown', 'shell:AppsFolder\NinhNguyen375.NTranslate_App', 'Version:', 'Build:', 'Package:', 'Identity:', 'OS:', 'TargetTested:', '10.0.22621.0')) {
    if ($text.IndexOf($literal, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "Missing pinned install behavior: $literal" }
}
if ($text -match 'dotnet\s+workload') { throw 'Workload commands forbidden.' }
if ($text -notmatch 'ZeroFreeBSTR') { throw 'Plaintext password buffer must be zeroed.' }
if ($text -notmatch 'TrustDevelopmentCertificate') { throw 'Explicit trust gate missing.' }
if ($text -notmatch 'Get-AuthenticodeSignature') { throw 'Signature verification missing.' }
if ($text -notmatch 'Get-AppxPackage') { throw 'Installed package query missing.' }

Write-Output 'PASS: install orchestration security and order'
