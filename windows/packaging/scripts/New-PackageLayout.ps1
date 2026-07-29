[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][string]$PublishPath,
    [Parameter(Mandatory)][string]$LayoutPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$') { throw "Version must be strict semantic version: $Version" }
$parts = $Version.Split('.')
if ($parts | Where-Object { [uint64]$_ -gt 65535 }) { throw 'Version components must be between 0 and 65535.' }
if (-not (Test-Path -LiteralPath (Join-Path $PublishPath 'NTranslate.App.exe') -PathType Leaf)) { throw 'Publish output lacks NTranslate.App.exe.' }
if (-not (Test-Path -LiteralPath (Join-Path $PublishPath 'NTranslate.App.pri') -PathType Leaf)) { throw 'Publish output lacks compiled XAML resources NTranslate.App.pri.' }

$manifestSource = Join-Path $PSScriptRoot '..\manifest\AppxManifest.xml'
$assetsSource = Join-Path $PSScriptRoot '..\Assets'
if (-not (Test-Path -LiteralPath $manifestSource -PathType Leaf)) { throw 'Canonical manifest missing.' }
if (-not (Test-Path -LiteralPath $assetsSource -PathType Container)) { throw 'Canonical package assets missing.' }

if (Test-Path -LiteralPath $LayoutPath) { Remove-Item -LiteralPath $LayoutPath -Recurse -Force }
New-Item -ItemType Directory -Path $LayoutPath | Out-Null
Copy-Item -Path (Join-Path $PublishPath '*') -Destination $LayoutPath -Recurse -Force
Copy-Item -LiteralPath $assetsSource -Destination $LayoutPath -Recurse -Force
[xml]$manifest = Get-Content -LiteralPath $manifestSource -Raw
$identity = $manifest.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Identity"]')
$identity.Version = "$Version.0"
$manifest.Save((Join-Path $LayoutPath 'AppxManifest.xml'))
