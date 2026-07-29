Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script = Join-Path $PSScriptRoot '..\..\install-app.ps1'
if (-not (Test-Path -LiteralPath $script -PathType Leaf)) { throw 'Missing windows/install-app.ps1.' }
$text = Get-Content -LiteralPath $script -Raw
foreach ($literal in @('10.0.301', '19045', '--locked-mode', '--no-restore', 'Release', 'win-x64', 'MakeAppx.exe', 'SignTool.exe', 'Add-AppxPackage', '-ForceApplicationShutdown', 'Get-AppxPackageManifest', 'PackageFamilyName', "!' + `$application.Id", 'Get-Process -Name NTranslate.App', 'Version:', 'Build:', 'Package:', 'Identity:', 'OS:', 'TargetTested:', '10.0.22621.0', '10.0.26100.6584', '/sha1', 'AMD64', 'Add-AppxPackage owns transactional deployment before commit', 'Get-AppxPackage -Name NinhNguyen375.NTranslate | Remove-AppxPackage')) {
    if ($text.IndexOf($literal, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw "Missing pinned install behavior: $literal" }
}
if ($text -match 'dotnet\s+workload') { throw 'Workload commands forbidden.' }
if ($text -notmatch 'ZeroFreeBSTR') { throw 'Plaintext password buffer must be zeroed.' }
if ($text -notmatch 'TrustDevelopmentCertificate') { throw 'Explicit trust gate missing.' }
if ($text -notmatch 'Get-AuthenticodeSignature') { throw 'Signature verification missing.' }
if ($text -notmatch 'Get-AppxPackage') { throw 'Installed package query missing.' }

$invokeCalls = [Collections.Generic.List[object]]::new()
& $script -Version '1.2.3' -SkipBuild -SkipInstall -NativeArchitecture AMD64 -InvokeTool {
    param($File, $Arguments)
    $invokeCalls.Add([pscustomobject]@{ File = $File; Arguments = @($Arguments) })
} -GetSignature { [pscustomobject]@{ Status = 'Valid'; SignerCertificate = [pscustomobject]@{ Subject = 'CN=Ninh Nguyen'; Thumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' } } } -InvokeLayout { } -ResolveTool { param($Name) "C:\fixture\$Name" } -GetDevelopmentCertificate { [pscustomobject]@{ Thumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' } }
$sign = @($invokeCalls | Where-Object { $_.File -like '*SignTool.exe' })
if ($sign.Count -ne 1 -or '/sha1' -notin $sign[0].Arguments -or '/f' -in $sign[0].Arguments -or '/p' -in $sign[0].Arguments) { throw 'Generated development certificate must sign by thumbprint without PFX password.' }

& $script -Version '1.2.3' -SkipBuild -SkipInstall -NativeArchitecture AMD64 -InvokeTool { } -GetSignature {
  [pscustomobject]@{
    Status = 'UnknownError'
    SignerCertificate = [pscustomobject]@{ Subject = 'CN=Ninh Nguyen'; Thumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' }
  }
} -InvokeLayout { } -ResolveTool { param($Name) "C:\fixture\$Name" } -GetDevelopmentCertificate {
  [pscustomobject]@{ Thumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' }
}

try { & $script -Version '1.2.3' -SkipBuild -SkipInstall -NativeArchitecture ARM64; throw 'ARM64 accepted.' } catch { if ($_.Exception.Message -eq 'ARM64 accepted.') { throw }; if ($_.Exception.Message -notmatch 'x64') { throw } }

Write-Output 'PASS: install orchestration security and order'
