Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$wf = Join-Path (Join-Path (Join-Path (Join-Path $PSScriptRoot '..') '..') '..') '.github\workflows\windows-release.yml'
if (-not (Test-Path -LiteralPath $wf -PathType Leaf)) { throw 'Missing .github/workflows/windows-release.yml.' }
$text = Get-Content -LiteralPath $wf -Raw

# Runner
if ($text -notmatch 'windows-latest') { throw 'Workflow must run on windows-latest.' }

# Triggers and platform tag isolation
if ($text -notmatch "tags:\s*\r?\n\s*- 'windows-v\*'") { throw 'Workflow must trigger only on windows-v* tags.' }
if ($text -match 'types:.*published') { throw 'Workflow must not depend on release events from the default branch.' }
if ($text -notmatch 'workflow_dispatch') { throw 'Workflow must support manual dispatch.' }
if ($text -notmatch "-replace '\^windows-v'") { throw 'Workflow must parse only windows-v<version> tags.' }
if ($text -notmatch 'gh release view') { throw 'Workflow must check for an existing Windows release.' }
if ($text -notmatch 'gh release create') { throw 'Workflow must create a missing Windows release.' }
if ($text -notmatch 'gh release upload') { throw 'Workflow must upload Windows release assets.' }
if ($text -notmatch '--clobber') { throw 'Workflow must replace same-named Windows assets safely.' }
if ($text -notmatch 'TAG=windows-v\$v') { throw 'Workflow must target tag windows-v<version>.' }
if ($text -match 'macos-v') { throw 'Windows workflow must not target macOS tags.' }

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
if ($text -notmatch 'gh release upload') { throw 'Workflow must upload release assets.' }
if ($text -notmatch 'win-x64-setup\.exe') { throw 'Workflow must upload the setup EXE.' }
if ($text -notmatch '\$sha\s*=\s*"\$exe\.sha256"' -or $text -notmatch 'gh release upload \$tag \$exe \$sha') { throw 'Workflow must upload the SHA-256 sidecar.' }

# No MSIX/signing steps
if ($text -match 'MakeAppx|SignTool|Add-AppxPackage|TrustedPeople|\.msix') { throw 'Workflow must not contain MSIX or signing steps.' }

# Permissions: only contents write, not packages or id-token
if ($text -notmatch 'contents:\s*write') { throw 'Workflow must have contents: write permission for release upload.' }
if ($text -match 'packages:\s*write|id-token:\s*write') { throw 'Workflow must not request packages or id-token write permissions.' }

Write-Output 'PASS: release workflow policy'
