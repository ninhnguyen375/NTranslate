Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\..\..\install-app.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Missing root install-app.ps1.' }

$text = Get-Content -LiteralPath $script -Raw
if ($text -match 'AppxManifest|TrustDevelopmentCertificate|TrustedPeople') { throw 'Root wrapper must not reference MSIX manifest or certificate trust.' }

$calls = [Collections.Generic.List[object]]::new()

& $script -Version '1.2.3' -InstallerPath (Join-Path $PSScriptRoot '..\..\..\windows\install-app.ps1') -InvokeInstaller {
    param($Path, $Version)
    $calls.Add([pscustomobject]@{ Path = $Path; Version = $Version })
}

if ($calls.Count -ne 1) { throw "Expected one child invocation; found $($calls.Count)." }
if ($calls[0].Version -ne '1.2.3') { throw "Wrong semantic version: $($calls[0].Version)" }

# Invalid version rejected
try {
    & $script -Version '1.2.3.4' -InstallerPath (Join-Path $PSScriptRoot '..\..\..\windows\install-app.ps1') -InvokeInstaller { throw 'Installer must not run.' }
    throw 'Four-part version accepted.'
} catch { if ($_.Exception.Message -eq 'Four-part version accepted.' -or $_.Exception.Message -notmatch 'ParameterBinding|Pattern') { throw } }

Write-Output 'PASS: root Windows install wrapper'
