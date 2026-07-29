[CmdletBinding(DefaultParameterSetName='Get')]
param(
    [Parameter(ParameterSetName='Get')][securestring]$Password,
    [Parameter(ParameterSetName='Get')][switch]$Trust,
    [Parameter(Mandatory, ParameterSetName='Remove')][string]$RemoveThumbprint,
    [Parameter(Mandatory, ParameterSetName='Verify')][string]$VerifyPackage
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$subject = 'CN=Ninh Nguyen'
$myStore = 'Cert:\CurrentUser\My'
$trustedStore = 'Cert:\CurrentUser\TrustedPeople'
$machineTrustedStore = 'Cert:\LocalMachine\TrustedPeople'
$output = Join-Path $env:LOCALAPPDATA 'NTranslate\Signing'

if ($PSCmdlet.ParameterSetName -eq 'Remove') {
    if ($RemoveThumbprint -notmatch '^[0-9A-Fa-f]{40}$') { throw 'Invalid certificate thumbprint.' }
    $certificatePath = Join-Path $myStore $RemoveThumbprint
    $trustedPath = Join-Path $trustedStore $RemoveThumbprint
    $machineTrustedPath = Join-Path $machineTrustedStore $RemoveThumbprint
    if (Test-Path -LiteralPath $certificatePath) { Remove-Item -LiteralPath $certificatePath -Force }
    if (Test-Path -LiteralPath $trustedPath) { Remove-Item -LiteralPath $trustedPath -Force }
    if (Test-Path -LiteralPath $machineTrustedPath) {
        Start-Process certutil.exe -Verb RunAs -Wait -ArgumentList @('-delstore', 'TrustedPeople', $RemoveThumbprint)
        if (Test-Path -LiteralPath $machineTrustedPath) { throw 'Removing machine-trusted development certificate failed.' }
    }
    return
}

if ($PSCmdlet.ParameterSetName -eq 'Verify') {
    $signature = Get-AuthenticodeSignature -LiteralPath $VerifyPackage
    if ($signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or $signature.SignerCertificate.Subject -ne $subject) {
        throw 'Package signature is not valid for pinned publisher.'
    }
    return $signature.SignerCertificate
}

$certificate = Get-ChildItem -Path $myStore | Where-Object {
    $_.Subject -eq $subject -and $_.HasPrivateKey -and $_.NotAfter -gt (Get-Date).AddDays(1) -and
    @($_.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -contains '1.3.6.1.5.5.7.3.3'
} | Sort-Object NotAfter -Descending | Select-Object -First 1
if ($null -eq $certificate) {
    $certificate = New-SelfSignedCertificate -Subject $subject -Type CodeSigningCert -KeyAlgorithm RSA -KeyLength 3072 -HashAlgorithm sha256 -KeyExportPolicy Exportable -CertStoreLocation $myStore
}

New-Item -ItemType Directory -Path $output -Force | Out-Null
$cerPath = Join-Path $output 'NTranslate-Development.cer'
Export-Certificate -Cert $certificate -FilePath $cerPath -Force | Out-Null
if ($null -ne $Password) {
    $pfxPath = Join-Path $output 'NTranslate-Development.pfx'
    Export-PfxCertificate -Cert $certificate -FilePath $pfxPath -Password $Password -CryptoAlgorithmOption AES256_SHA256 -Force | Out-Null
}
if ($Trust) {
    Import-Certificate -FilePath $cerPath -CertStoreLocation $trustedStore | Out-Null
    $machineTrustedPath = Join-Path $machineTrustedStore $certificate.Thumbprint
    if (-not (Test-Path -LiteralPath $machineTrustedPath)) {
        Start-Process certutil.exe -Verb RunAs -Wait -ArgumentList @('-addstore', 'TrustedPeople', $cerPath)
        if (-not (Test-Path -LiteralPath $machineTrustedPath)) { throw 'Trusting development certificate failed.' }
    }
}

[pscustomobject]@{ Thumbprint = $certificate.Thumbprint; Certificate = $certificate; CerPath = $cerPath; OutputPath = $output }
