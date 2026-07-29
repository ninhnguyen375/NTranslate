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
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw "Windows installer not found: $InstallerPath" }

[xml]$manifest = Get-Content -LiteralPath $ManifestPath -Raw
$identity = $manifest.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Identity"]')
$packageVersion = if ($null -ne $identity) { $identity.GetAttribute('Version') } else { '' }
if ($packageVersion -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') {
    throw 'Manifest Identity Version must be a valid four-part numeric version.'
}
if ($Matches[4] -ne '0') { throw 'Manifest Identity Version must use revision 0.' }
$version = "$($Matches[1]).$($Matches[2]).$($Matches[3])"

& $InvokeInstaller $InstallerPath $version $true
