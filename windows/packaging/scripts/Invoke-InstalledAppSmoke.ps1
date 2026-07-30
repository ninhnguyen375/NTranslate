[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$')][string]$Version,
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ResultsPath,
    [string]$InstalledExe = (Join-Path $env:LOCALAPPDATA 'Programs\NTranslate\NTranslate.App.exe'),
    [scriptblock]$LaunchApp = { param($Exe) Start-Process -FilePath $Exe },
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

Invoke-Check 'installed-exe-exists' {
    if (-not (Test-Path -LiteralPath $InstalledExe -PathType Leaf)) { throw "Installed EXE not found: $InstalledExe" }
}
Invoke-Check 'launch' { & $LaunchApp $InstalledExe }
Invoke-Check 'second-launch' { & $LaunchApp $InstalledExe }
foreach ($name in @('tray','manual-translation','copy','history','bookmark','settings-secret-exclusion','update-fixture','invalid-package-rejection','app-exit','log-redaction')) {
    Invoke-Check $name { & $InvokeScenario $name $InstalledExe $fullResults }
}
Invoke-Check 'report-secret-scan' {
    $sensitive = '(?i)(Bearer\s+[A-Za-z0-9._-]+|api[_-]?key\s*[:=]\s*\S+|sk-[A-Za-z0-9_-]{12,})'
    foreach ($file in @(Get-ChildItem -LiteralPath $fullResults -File -Recurse -ErrorAction SilentlyContinue)) {
        if ([IO.Path]::GetExtension($file.Name) -in '.json','.log','.txt') {
            if ([IO.File]::ReadAllText($file.FullName) -match $sensitive) { throw "Sensitive value found in $($file.Name)." }
        }
    }
}
$report = [pscustomobject]@{Version=$Version;TimestampUtc=[DateTime]::UtcNow.ToString('o');Checks=$checks}
$reportPath = Join-Path $fullResults 'installed-smoke.json'
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$failures = @($checks | Where-Object Status -eq 'FAIL')
Write-Output ("Installed smoke: {0} passed, {1} failed. Report: {2}" -f ($checks.Count-$failures.Count),$failures.Count,$reportPath)
if ($failures.Count -gt 0) { exit 1 }
