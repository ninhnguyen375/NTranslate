Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\scripts\Invoke-InstalledAppSmoke.ps1'
$resultsPath = Join-Path ([IO.Path]::GetTempPath()) ('ntranslate-smoke-' + [guid]::NewGuid().ToString('N'))
$packagePath = Join-Path $resultsPath 'NTranslate.msix'
$state = [pscustomobject]@{ SignaturePath = $null }
$launchCalls = [Collections.Generic.List[string]]::new()
$scenarioCalls = [Collections.Generic.List[string]]::new()
try {
    New-Item -ItemType Directory -Path $resultsPath | Out-Null
    Set-Content -LiteralPath $packagePath -Value 'fixture'
    & $scriptPath -PackageName 'NinhNguyen375.NTranslate' -PackagePath $packagePath -ExpectedVersion '1.0.0.0' -ResultsPath $resultsPath `
        -GetPackage { [pscustomobject]@{ Name='NinhNguyen375.NTranslate'; Version=[version]'1.0.0.0'; Architecture='X64'; Publisher='CN=Ninh Nguyen'; PackageFamilyName='NinhNguyen375.NTranslate_test'; InstallLocation=[pscustomobject]@{ Path='C:\Program Files\WindowsApps\fixture' } } } `
        -GetSignature { param($Path) $state.SignaturePath=$Path; [pscustomobject]@{ Status='Valid'; SignerCertificate=[pscustomobject]@{ Subject='CN=Ninh Nguyen' } } } `
        -GetExecutable { param($Root) 'C:\Program Files\WindowsApps\fixture\NTranslate.App.exe' } `
        -ActivateApp { param($AppId) $launchCalls.Add($AppId) } `
        -InvokeScenario { param($Name, $Executable, $ResultRoot) $scenarioCalls.Add($Name) }

    if ($state.SignaturePath -ne $packagePath) { throw 'Signature callback did not receive generated MSIX path.' }
    if ($launchCalls.Count -ne 2 -or $launchCalls[0] -ne 'NinhNguyen375.NTranslate_test!App') { throw 'AppsFolder activation missing.' }
    foreach ($required in @('tray','manual-translation','copy','history','bookmark','settings-secret-exclusion','update-fixture','invalid-package-rejection','app-exit','log-redaction')) {
        if ($required -notin $scenarioCalls) { throw "Missing injected smoke scenario: $required" }
    }
    $report = Get-Content -LiteralPath (Join-Path $resultsPath 'installed-smoke.json') -Raw | ConvertFrom-Json
    if (@($report.Checks | Where-Object Status -ne 'PASS').Count -ne 0) { throw 'Expected all fixture checks to pass.' }
    if (@($report.Checks).Count -ne 14) { throw 'Expected fourteen named smoke checks.' }
    Write-Output 'PASS: installed smoke verifies MSIX and all required named scenarios without stopping Explorer.'
} finally {
    if (Test-Path -LiteralPath $resultsPath) { Remove-Item -LiteralPath $resultsPath -Recurse -Force -Confirm:$false }
}
