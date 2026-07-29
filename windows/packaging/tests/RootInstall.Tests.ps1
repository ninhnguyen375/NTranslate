Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\..\..\install-app.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Missing root install-app.ps1.' }

$temp = Join-Path ([IO.Path]::GetTempPath()) "ntranslate-root-install-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temp | Out-Null
try {
    $manifest = Join-Path $temp 'AppxManifest.xml'
    $installer = Join-Path $temp 'install-app.ps1'
    New-Item -ItemType File -Path $installer | Out-Null
    $calls = [Collections.Generic.List[object]]::new()
    Set-Content -LiteralPath $manifest -Encoding UTF8 -Value @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="NinhNguyen375.NTranslate" Version="1.2.3.0" />
</Package>
'@

    & $script -ManifestPath $manifest -InstallerPath $installer -InvokeInstaller {
        param($Path, $Version, $TrustDevelopmentCertificate)
        $calls.Add([pscustomobject]@{
            Path = $Path
            Version = $Version
            TrustDevelopmentCertificate = $TrustDevelopmentCertificate
        })
    }

    if ($calls.Count -ne 1) { throw "Expected one child invocation; found $($calls.Count)." }
    if ($calls[0].Path -ne $installer) { throw 'Wrong child installer path.' }
    if ($calls[0].Version -ne '1.2.3') { throw "Wrong semantic version: $($calls[0].Version)" }
    if (-not $calls[0].TrustDevelopmentCertificate) { throw 'Development certificate trust was not enabled.' }

    Set-Content -LiteralPath $manifest -Encoding UTF8 -Value @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="NinhNguyen375.NTranslate" Version="1.2.3.4" />
</Package>
'@
    try {
        & $script -ManifestPath $manifest -InstallerPath $installer -InvokeInstaller { throw 'Installer must not run.' }
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
        & $script -ManifestPath $manifest -InstallerPath $installer -InvokeInstaller { throw 'Installer must not run.' }
        throw 'Missing version accepted.'
    } catch {
        if ($_.Exception.Message -eq 'Missing version accepted.' -or $_.Exception.Message -notmatch 'valid four-part') { throw }
    }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}

Write-Output 'PASS: root Windows install wrapper'
