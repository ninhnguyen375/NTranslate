Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\scripts\Invoke-InstalledAppSmoke.ps1'
$resultsPath = Join-Path ([IO.Path]::GetTempPath()) ('ntranslate-smoke-' + [guid]::NewGuid().ToString('N'))
$fakeExe = Join-Path $resultsPath 'NTranslate.App.exe'
$launchCalls = [Collections.Generic.List[string]]::new()
$scenarioCalls = [Collections.Generic.List[string]]::new()
try {
    New-Item -ItemType Directory -Path $resultsPath | Out-Null
    Set-Content -LiteralPath $fakeExe -Value 'fixture'

    & $scriptPath -Version '1.0.0' -ResultsPath $resultsPath `
        -InstalledExe $fakeExe `
        -LaunchApp { param($Exe) $launchCalls.Add($Exe) } `
        -InvokeScenario { param($Name, $Executable, $ResultRoot) $scenarioCalls.Add($Name) }

    if ($launchCalls.Count -ne 2) { throw "Expected 2 launch calls; got $($launchCalls.Count)." }
    if ($launchCalls[0] -ne $fakeExe) { throw 'LaunchApp did not receive installed EXE path.' }
    foreach ($required in @('tray','manual-translation','copy','history','bookmark','settings-secret-exclusion','update-fixture','invalid-package-rejection','app-exit','log-redaction')) {
        if ($required -notin $scenarioCalls) { throw "Missing injected smoke scenario: $required" }
    }
    $report = Get-Content -LiteralPath (Join-Path $resultsPath 'installed-smoke.json') -Raw | ConvertFrom-Json
    if (@($report.Checks | Where-Object Status -ne 'PASS').Count -ne 0) { throw 'Expected all fixture checks to pass.' }
    if (@($report.Checks).Count -ne 14) { throw "Expected 14 named smoke checks; got $(@($report.Checks).Count)." }
    Write-Output 'PASS: installed smoke verifies EXE install and all required named scenarios without stopping Explorer.'
} finally {
    if (Test-Path -LiteralPath $resultsPath) { Remove-Item -LiteralPath $resultsPath -Recurse -Force -Confirm:$false }
}
