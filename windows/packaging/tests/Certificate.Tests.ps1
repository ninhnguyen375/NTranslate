Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\scripts\Manage-DevelopmentCertificate.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Missing certificate script.' }
$text = Get-Content -LiteralPath $script -Raw
foreach ($literal in @('CN=Ninh Nguyen', '3072', 'sha256', 'CodeSigningCert', 'Cert:\CurrentUser\My', 'Cert:\CurrentUser\TrustedPeople')) {
    if ($text.IndexOf($literal, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "Missing pinned certificate policy: $literal" }
}
if ($text -match 'Write-(Output|Host|Verbose|Debug)[^\r\n]*(Password|SecureString)') { throw 'Script may expose password material.' }
if ($text -notmatch 'HasPrivateKey') { throw 'Script must reject certificates without private keys.' }
if ($text -notmatch 'Remove-Item[^\r\n]*Thumbprint|Join-Path[^\r\n]*Thumbprint') { throw 'Cleanup must target exact thumbprint.' }
if ($text -notmatch 'Get-AuthenticodeSignature') { throw 'Signed package signer must be validated.' }

Write-Output 'PASS: development certificate security policy'
