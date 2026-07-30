[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')][string]$Version,
    [string]$InstallerPath = (Join-Path $PSScriptRoot 'windows\install-app.ps1'),
    [scriptblock]$InvokeInstaller = {
        param($Path, $Version)
        & $Path -Version $Version
    }
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
if (-not (Test-Path -LiteralPath $InstallerPath -PathType Leaf)) { throw "Windows installer not found: $InstallerPath" }

& $InvokeInstaller $InstallerPath $Version
