[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9.-]+$')][string]$PackageName,
    [Parameter(Mandatory)][ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$PackagePath,
    [Parameter(Mandatory)][version]$ExpectedVersion,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ResultsPath,
    [scriptblock]$GetPackage = { param($Name) Get-AppxPackage -Name $Name -ErrorAction Stop },
    [scriptblock]$GetSignature = { param($Path) Get-AuthenticodeSignature -FilePath $Path },
    [scriptblock]$GetExecutable = { param($Root) Get-ChildItem -LiteralPath $Root -Filter 'NTranslate.App.exe' -File -Recurse | Select-Object -First 1 -ExpandProperty FullName },
    [scriptblock]$ActivateApp = { param($AppId) Start-Process explorer.exe "shell:AppsFolder\$AppId" },
    [scriptblock]$InvokeScenario = { param($Name, $Executable, $ResultRoot) throw "Smoke scenario '$Name' requires UI automation fixture." }
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$fullResults = [IO.Path]::GetFullPath($ResultsPath)
if ($fullResults -eq [IO.Path]::GetPathRoot($fullResults)) { throw 'ResultsPath cannot be a filesystem root.' }
New-Item -ItemType Directory -Path $fullResults -Force | Out-Null
$checks = [Collections.Generic.List[object]]::new()
function Invoke-Check([string]$Name, [scriptblock]$Action) {
    try { & $Action; $script:checks.Add([pscustomobject]@{Name=$Name;Status='PASS';Detail=$null}) }
    catch { $script:checks.Add([pscustomobject]@{Name=$Name;Status='FAIL';Detail=$_.Exception.Message}) }
}
function Assert-Equal($Expected, $Actual, [string]$Message) { if ($Expected -ne $Actual) { throw "$Message Expected '$Expected', got '$Actual'." } }

$package = $null
$executable = $null
Invoke-Check 'identity-version-signature' {
    $script:package = @(& $GetPackage $PackageName)
    Assert-Equal 1 $script:package.Count 'Exactly one installed package required.'
    $script:package = $script:package[0]
    Assert-Equal $PackageName $script:package.Name 'Package identity mismatch.'
    Assert-Equal $ExpectedVersion ([version]$script:package.Version) 'Package version mismatch.'
    Assert-Equal 'X64' $script:package.Architecture.ToString().ToUpperInvariant() 'Package architecture mismatch.'
    $signature = & $GetSignature $PackagePath
    Assert-Equal 'Valid' $signature.Status.ToString() 'MSIX signature invalid.'
    Assert-Equal $script:package.Publisher $signature.SignerCertificate.Subject 'Signer subject mismatch.'
    $script:executable = & $GetExecutable $script:package.InstallLocation.Path
    if ([string]::IsNullOrWhiteSpace($script:executable)) { throw 'NTranslate.App.exe not found in installed package.' }
}
Invoke-Check 'launch' { & $ActivateApp ($script:package.PackageFamilyName + '!App') }
Invoke-Check 'second-launch' { & $ActivateApp ($script:package.PackageFamilyName + '!App') }
foreach ($name in @('tray','manual-translation','copy','history','bookmark','settings-secret-exclusion','update-fixture','invalid-package-rejection','app-exit','log-redaction')) {
    Invoke-Check $name { & $InvokeScenario $name $script:executable $fullResults }
}
Invoke-Check 'report-secret-scan' {
    $sensitive = '(?i)(Bearer\s+[A-Za-z0-9._-]+|api[_-]?key\s*[:=]\s*\S+|sk-[A-Za-z0-9_-]{12,})'
    foreach ($file in @(Get-ChildItem -LiteralPath $fullResults -File -Recurse -ErrorAction SilentlyContinue)) {
        if ([IO.Path]::GetExtension($file.Name) -in '.json','.log','.txt') {
            if ([IO.File]::ReadAllText($file.FullName) -match $sensitive) { throw "Sensitive value found in $($file.Name)." }
        }
    }
}
$report = [pscustomobject]@{PackageName=$PackageName;ExpectedVersion=$ExpectedVersion.ToString();TimestampUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks}
$reportPath = Join-Path $fullResults 'installed-smoke.json'
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$failures = @($checks | Where-Object Status -eq 'FAIL')
Write-Output ("Installed smoke: {0} passed, {1} failed. Report: {2}" -f ($checks.Count-$failures.Count),$failures.Count,$reportPath)
if ($failures.Count -gt 0) { exit 1 }
