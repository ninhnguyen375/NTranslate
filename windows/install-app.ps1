[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')][string]$Version,
    [ValidateSet('Release')][string]$Configuration = 'Release',
    [ValidateSet('win-x64')][string]$Runtime = 'win-x64',
    [string]$CertificatePath,
    [securestring]$CertificatePassword,
    [switch]$TrustDevelopmentCertificate,
    [switch]$SkipBuild,
    [switch]$SkipInstall,
    [scriptblock]$InvokeTool = { param($File, $Arguments) & $File @Arguments; if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" } }
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$expectedSdk = '10.0.301'
$minimumBuild = 19045
$targetTested = '10.0.22621.0'
$identity = 'NinhNguyen375.NTranslate'
$root = $PSScriptRoot
$solution = Join-Path $root 'NTranslate.slnx'
$artifacts = Join-Path $root 'artifacts'
$publish = Join-Path $artifacts 'publish\win-x64'
$layout = Join-Path $artifacts 'layout\win-x64'
$package = Join-Path $artifacts "packages\NTranslate-$Version-win-x64.msix"
$plainPassword = [IntPtr]::Zero

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $InvokeTool $File $Arguments
}

try {
    $sdk = (& dotnet --version).Trim()
    if ($sdk -ne $expectedSdk) { throw "Required .NET SDK $expectedSdk; found $sdk." }
    $osBuild = [Environment]::OSVersion.Version.Build
    if ($osBuild -lt $minimumBuild) { throw "Windows build $minimumBuild or newer required; found $osBuild." }
    if ($Version.Split('.') | Where-Object { [uint64]$_ -gt 65535 }) { throw 'Version components must be between 0 and 65535.' }

    if (-not $SkipBuild) {
        Invoke-Checked dotnet @('restore', $solution, '--locked-mode')
        Invoke-Checked dotnet @('build', $solution, '-c', $Configuration, '--no-restore')
        Invoke-Checked dotnet @('test', $solution, '-c', $Configuration, '--no-build', '--no-restore')
        Invoke-Checked dotnet @('publish', (Join-Path $root 'src\NTranslate.App\NTranslate.App.csproj'), '-c', $Configuration, '-r', $Runtime, '--no-restore', '-o', $publish)
    }

    & (Join-Path $root 'packaging\scripts\New-PackageLayout.ps1') -Version $Version -PublishPath $publish -LayoutPath $layout
    New-Item -ItemType Directory -Path (Split-Path $package) -Force | Out-Null
    $sdkTools = Join-Path $env:USERPROFILE '.nuget\packages\microsoft.windows.sdk.buildtools'
    $toolRoot = Get-ChildItem -LiteralPath $sdkTools -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($null -eq $toolRoot) { throw 'Restored Microsoft.Windows.SDK.BuildTools package not found.' }
    $makeAppx = Join-Path $toolRoot.FullName 'bin\10.0.26100.0\x64\MakeAppx.exe'
    $signTool = Join-Path $toolRoot.FullName 'bin\10.0.26100.0\x64\SignTool.exe'
    foreach ($tool in @($makeAppx, $signTool)) { if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "Pinned packaging tool missing: $tool" } }

    Invoke-Checked $makeAppx @('pack', '/o', '/d', $layout, '/p', $package)
    if ([string]::IsNullOrWhiteSpace($CertificatePath)) {
        $certificateResult = & (Join-Path $root 'packaging\scripts\Manage-DevelopmentCertificate.ps1') -Password $CertificatePassword -Trust:$TrustDevelopmentCertificate
        $CertificatePath = Join-Path $certificateResult.OutputPath 'NTranslate-Development.pfx'
    }
    if ($null -eq $CertificatePassword) { throw 'CertificatePassword required for PFX signing.' }
    $plainPassword = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($CertificatePassword)
    $passwordText = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($plainPassword)
    Invoke-Checked $signTool @('sign', '/fd', 'sha256', '/f', $CertificatePath, '/p', $passwordText, $package)
    $signature = Get-AuthenticodeSignature -LiteralPath $package
    if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -ne 'CN=Ninh Nguyen') { throw 'Signed package verification failed.' }

    if (-not $SkipInstall) {
        Add-AppxPackage -Path $package -ForceApplicationShutdown
        $installed = Get-AppxPackage -Name $identity
        if ($null -eq $installed -or $installed.Version.ToString() -ne "$Version.0") { throw 'Installed package verification failed.' }
        Start-Process explorer.exe "shell:AppsFolder\NinhNguyen375.NTranslate_App"
    }

    Write-Output "Version: $Version"
    Write-Output "Build: $Version.0"
    Write-Output "Package: $package"
    Write-Output "Identity: $identity"
    Write-Output "OS: $([Environment]::OSVersion.Version)"
    Write-Output "TargetTested: $targetTested"
} finally {
    if ($plainPassword -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($plainPassword) }
    $passwordText = $null
}
