[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')][string]$Version,
    [ValidateSet('Release')][string]$Configuration = 'Release',
    [ValidateSet('win-x64')][string]$Runtime = 'win-x64',
    [switch]$SkipBuild,
    [switch]$SkipInstall,
    [string]$NativeArchitecture = $env:PROCESSOR_ARCHITECTURE,
    [string]$IsccPath = 'C:\Users\ninhn\AppData\Local\Programs\Inno Setup 6\ISCC.exe',
    [scriptblock]$InvokeTool = { param($File, $Arguments) & $File @Arguments; if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" } },
    [scriptblock]$InvokeIscc = $null,
    [scriptblock]$GetFileHash = { param($Path) (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() },
    [scriptblock]$InvokeInstaller = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$expectedSdk = '10.0.301'
$minimumBuild = 19041
$root = $PSScriptRoot
$solution = Join-Path $root 'NTranslate.slnx'
$artifacts = Join-Path $root 'artifacts'
$publish = Join-Path $artifacts 'publish\win-x64'
$installerName = "NTranslate-$Version-win-x64-setup.exe"
$setupExe = Join-Path $artifacts "packages\$installerName"
$checksumFile = "$setupExe.sha256"
$installedExe = Join-Path $env:LOCALAPPDATA 'Programs\NTranslate\NTranslate.App.exe'
$issScript = Join-Path $root 'packaging\NTranslate.iss'

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $InvokeTool $File $Arguments
}

if ($NativeArchitecture -notin @('AMD64', 'x64')) { throw "Native x64/AMD64 host required; found $NativeArchitecture." }
$sdk = (& dotnet --version).Trim()
if ($sdk -ne $expectedSdk) { throw "Required .NET SDK $expectedSdk; found $sdk." }
$osBuild = [Environment]::OSVersion.Version.Build
if ($osBuild -lt $minimumBuild) { throw "Windows build $minimumBuild or newer required; found $osBuild." }

if (-not $SkipBuild) {
    Invoke-Checked dotnet @('restore', $solution, '--locked-mode')
    Invoke-Checked dotnet @('build', $solution, '-c', $Configuration, '--no-restore')
    Invoke-Checked dotnet @('test', $solution, '-c', $Configuration, '--no-build', '--no-restore')
    Invoke-Checked dotnet @('publish', (Join-Path $root 'src\NTranslate.App\NTranslate.App.csproj'), '-c', $Configuration, '-r', $Runtime, '--no-restore', '-o', $publish)
}

New-Item -ItemType Directory -Path (Split-Path $setupExe) -Force | Out-Null

if ($null -ne $InvokeIscc) {
    & $InvokeIscc $issScript $Version $publish (Split-Path $setupExe)
} else {
    if (-not (Test-Path -LiteralPath $IsccPath -PathType Leaf)) { throw "Inno Setup compiler not found at: $IsccPath" }
    Invoke-Checked $IsccPath @("/DAppVersion=$Version", "/DSourceDir=$publish", "/DOutputDir=$(Split-Path $setupExe)", $issScript)
}

if (-not (Test-Path -LiteralPath $setupExe -PathType Leaf)) { throw "Setup EXE not produced: $setupExe" }
$hash = & $GetFileHash $setupExe
Set-Content -LiteralPath $checksumFile -Encoding ASCII -Value "$hash *$installerName"
Write-Output "Checksum: $checksumFile"

if (-not $SkipInstall) {
    if ($null -ne $InvokeInstaller) {
        & $InvokeInstaller $setupExe
    } else {
        & $setupExe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS
        if ($LASTEXITCODE -ne 0) { throw "Installer failed with exit code $LASTEXITCODE." }
    }
    if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) { throw "Installed EXE not found: $installedExe" }
    Start-Process -FilePath $installedExe
    $launched = 1..20 | ForEach-Object {
        Start-Sleep -Milliseconds 250
        Get-Process -Name NTranslate.App -ErrorAction SilentlyContinue
    } | Select-Object -First 1
    if ($null -eq $launched) { throw 'Application process did not stay running after launch.' }
}

Write-Output "Version: $Version"
Write-Output "Build: $Version.0"
Write-Output "Package: $setupExe"
Write-Output "Checksum: $checksumFile"
Write-Output "OS: $([Environment]::OSVersion.Version)"
