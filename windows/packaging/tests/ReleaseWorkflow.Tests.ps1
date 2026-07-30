Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$wf = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') '..') '.github\workflows\windows-release.yml'
if (-not (Test-Path -LiteralPath $wf -PathType Leaf)) { throw 'Missing .github/workflows/windows-release.yml.' }
$text = Get-Content -LiteralPath $wf -Raw

# Runner
if ($text -notmatch 'windows-latest') { throw 'Workflow must run on windows-latest.' }

# Triggers
if ($text -notmatch 'release:' -or $text -notmatch 'types:.*published') { throw 'Workflow must trigger on release published.' }
if ($text -notmatch 'workflow_dispatch') { throw 'Workflow must support manual dispatch.' }

# Build steps in required order
$restoreIdx   = $text.IndexOf('--locked-mode', [StringComparison]::OrdinalIgnoreCase)
$buildIdx     = $text.IndexOf('dotnet build', [StringComparison]::OrdinalIgnoreCase)
$testIdx      = $text.IndexOf('dotnet test', [StringComparison]::OrdinalIgnoreCase)
$publishIdx   = $text.IndexOf('dotnet publish', [StringComparison]::OrdinalIgnoreCase)
$isccIdx      = $text.IndexOf('ISCC', [StringComparison]::OrdinalIgnoreCase)
$hashIdx      = $text.IndexOf('sha256', [StringComparison]::OrdinalIgnoreCase)
if ($restoreIdx -lt 0) { throw 'Workflow must run locked restore.' }
if ($buildIdx   -lt 0) { throw 'Workflow must build solution.' }
if ($testIdx    -lt 0) { throw 'Workflow must run tests.' }
if ($publishIdx -lt 0) { throw 'Workflow must publish app.' }
if ($isccIdx    -lt 0) { throw 'Workflow must compile with ISCC.' }
if ($hashIdx    -lt 0) { throw 'Workflow must generate SHA-256 checksum.' }
if ($restoreIdx -gt $buildIdx)  { throw 'Restore must come before build.' }
if ($buildIdx   -gt $testIdx)   { throw 'Build must come before test.' }
if ($testIdx    -gt $publishIdx){ throw 'Test must come before publish.' }
if ($publishIdx -gt $isccIdx)   { throw 'Publish must come before ISCC.' }
if ($isccIdx    -gt $hashIdx)   { throw 'ISCC must come before SHA-256.' }

# Exact two release assets: setup EXE + .sha256 sidecar
if (($text | Select-String 'upload-release-asset|softprops/action-gh-release' -AllMatches).Matches.Count -lt 1) { throw 'Workflow must upload release assets.' }
if ($text -notmatch 'win-x64-setup\.exe') { throw 'Workflow must upload the setup EXE.' }
if ($text -notmatch 'win-x64-setup\.exe\.sha256') { throw 'Workflow must upload the SHA-256 sidecar.' }

# No MSIX/signing steps
if ($text -match 'MakeAppx|SignTool|Add-AppxPackage|TrustedPeople|\.msix') { throw 'Workflow must not contain MSIX or signing steps.' }

# Permissions: only contents write, not packages or id-token
if ($text -notmatch 'contents:\s*write') { throw 'Workflow must have contents: write permission for release upload.' }
if ($text -match 'packages:\s*write|id-token:\s*write') { throw 'Workflow must not request packages or id-token write permissions.' }

Write-Output 'PASS: release workflow policy'
