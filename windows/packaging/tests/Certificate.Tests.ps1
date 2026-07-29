Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\scripts\Manage-DevelopmentCertificate.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Missing certificate script.' }
$text = Get-Content -LiteralPath $script -Raw
foreach ($literal in @('CN=Ninh Nguyen', '3072', 'sha256', 'CodeSigningCert', 'Cert:\CurrentUser\My', 'Cert:\CurrentUser\TrustedPeople', 'Cert:\LocalMachine\TrustedPeople')) {
    if ($text.IndexOf($literal, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "Missing pinned certificate policy: $literal" }
}
if ($text -match 'Write-(Output|Host|Verbose|Debug)[^\r\n]*(Password|SecureString)') { throw 'Script may expose password material.' }
if ($text -notmatch 'HasPrivateKey') { throw 'Script must reject certificates without private keys.' }
if ($text -notmatch 'Remove-Item[^\r\n]*Thumbprint|Join-Path[^\r\n]*Thumbprint') { throw 'Cleanup must target exact thumbprint.' }
if (($text.Split('Join-Path $', [StringSplitOptions]::None).Length - 1) -lt 3) { throw 'Cleanup must cover personal, trusted people, and root stores.' }
if ($text -notmatch 'Get-AuthenticodeSignature') { throw 'Signed package signer must be validated.' }
if ($text -notmatch 'LocalMachine\\TrustedPeople') { throw 'Development signer must be trusted for AppX deployment at machine scope.' }
if ($text -notmatch 'Start-Process[^\r\n]*-Verb RunAs') { throw 'Machine trust must request explicit elevation.' }
if ($text -match '\.ExitCode|-PassThru') { throw 'Elevated trust must verify certificate-store postconditions instead of reading process state.' }
if ($text -match 'CurrentUser\\Root') { throw 'Development signer must not become a current-user root CA.' }

& $script | Out-Null

Write-Output 'PASS: development certificate security policy'
