Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\scripts\Invoke-InstalledAppSmoke.ps1'
$resultsPath = Join-Path ([IO.Path]::GetTempPath()) ('ntranslate-smoke-' + [guid]::NewGuid().ToString('N'))
$launcherCalls = [Collections.Generic.List[string]]::new()
$state = [pscustomobject]@{ Stopped = $false }

try {
    & $scriptPath `
        -PackageName 'NinhNguyen375.NTranslate' `
        -ExpectedVersion '1.0.0.0' `
        -ResultsPath $resultsPath `
        -GetPackage {
            [pscustomobject]@{
                Name = 'NinhNguyen375.NTranslate'
                Version = [version]'1.0.0.0'
                Architecture = 'X64'
                Publisher = 'CN=Ninh Nguyen'
                PackageFamilyName = 'NinhNguyen375.NTranslate_test'
                InstallLocation = [pscustomobject]@{ Path = 'C:\Program Files\WindowsApps\fixture' }
            }
        } `
        -GetSignature {
            [pscustomobject]@{
                Status = 'Valid'
                SignerCertificate = [pscustomobject]@{ Subject = 'CN=Ninh Nguyen' }
            }
        } `
        -StartProcess {
            param($FilePath, $ArgumentList)
            $launcherCalls.Add("$FilePath|$ArgumentList")
            [pscustomobject]@{ Id = 42 }
        } `
        -StopProcess {
            param($Process)
            if ($Process.Id -ne 42) { throw 'Unexpected process.' }
            $state.Stopped = $true
        }

    if ($launcherCalls.Count -ne 1) { throw 'Expected one injected launch.' }
    if ($launcherCalls[0] -ne 'explorer.exe|shell:AppsFolder\NinhNguyen375.NTranslate_test!App') { throw 'Unsafe or unexpected launch arguments.' }
    if (-not $state.Stopped) { throw 'Injected process was not stopped.' }

    $report = Get-Content -LiteralPath (Join-Path $resultsPath 'installed-smoke.json') -Raw | ConvertFrom-Json
    if (@($report.Checks | Where-Object Status -ne 'PASS').Count -ne 0) { throw 'Expected all fixture checks to pass.' }
    if (@($report.Checks).Count -ne 4) { throw 'Expected four smoke checks.' }
    Write-Output 'PASS: installed smoke uses injected package, signature, launch, and stop tools.'
}
finally {
    if (Test-Path -LiteralPath $resultsPath) { Remove-Item -LiteralPath $resultsPath -Recurse -Force -Confirm:$false }
}
