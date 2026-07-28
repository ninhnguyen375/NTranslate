[CmdletBinding()]
param(
    [Parameter(Mandatory)] [ValidatePattern('^[A-Za-z0-9.-]+$')] [string] $PackageName,
    [Parameter(Mandatory)] [version] $ExpectedVersion,
    [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $ResultsPath,
    [scriptblock] $GetPackage = { param($Name) Get-AppxPackage -Name $Name -ErrorAction Stop },
    [scriptblock] $GetSignature = { param($Path) Get-AuthenticodeSignature -FilePath $Path },
    [scriptblock] $StartProcess = { param($FilePath, $ArgumentList) Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -PassThru },
    [scriptblock] $StopProcess = { param($Process) Stop-Process -Id $Process.Id -Force -ErrorAction Stop }
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Equal([object] $Expected, [object] $Actual, [string] $Message) {
    if ($Expected -ne $Actual) { throw "$Message Expected '$Expected', got '$Actual'." }
}

function Assert-SafePath([string] $Path) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath -eq $root) { throw 'ResultsPath cannot be a filesystem root.' }
    $fullPath
}

$resultsDirectory = Assert-SafePath $ResultsPath
New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null
$checks = [Collections.Generic.List[object]]::new()
$process = $null

function Invoke-Check([string] $Name, [scriptblock] $Action) {
    try {
        & $Action
        $script:checks.Add([pscustomobject]@{ Name = $Name; Status = 'PASS'; Detail = $null })
    }
    catch {
        $script:checks.Add([pscustomobject]@{ Name = $Name; Status = 'FAIL'; Detail = $_.Exception.Message })
    }
}

$package = $null
Invoke-Check 'identity-version-architecture' {
    $script:package = @(& $GetPackage $PackageName)
    Assert-Equal 1 $script:package.Count 'Exactly one installed package required.'
    $script:package = $script:package[0]
    Assert-Equal $PackageName $script:package.Name 'Package identity mismatch.'
    Assert-Equal $ExpectedVersion ([version]$script:package.Version) 'Package version mismatch.'
    Assert-Equal 'X64' $script:package.Architecture.ToString().ToUpperInvariant() 'Package architecture mismatch.'
}

Invoke-Check 'signature' {
    if ($null -eq $script:package) { throw 'Package lookup failed.' }
    $signature = & $GetSignature $script:package.InstallLocation.Path
    Assert-Equal 'Valid' $signature.Status.ToString() 'Installed package signature invalid.'
    Assert-Equal $script:package.Publisher $signature.SignerCertificate.Subject 'Signer subject does not match package publisher.'
}

Invoke-Check 'launch-and-exit' {
    if ($null -eq $script:package) { throw 'Package lookup failed.' }
    $appId = $script:package.PackageFamilyName + '!App'
    $script:process = & $StartProcess 'explorer.exe' "shell:AppsFolder\$appId"
    if ($null -eq $script:process) { throw 'Launcher returned no process handle.' }
    & $StopProcess $script:process
}

Invoke-Check 'log-redaction' {
    $sensitive = '(?i)(Bearer\s+[A-Za-z0-9._-]+|api[_-]?key\s*[:=]\s*\S+|sk-[A-Za-z0-9_-]{12,})'
    $files = @(Get-ChildItem -LiteralPath $resultsDirectory -File -Recurse -ErrorAction SilentlyContinue)
    foreach ($file in $files) {
        if ([IO.Path]::GetExtension($file.Name) -in '.json', '.log', '.txt') {
            $content = [IO.File]::ReadAllText($file.FullName)
            if ($content -match $sensitive) { throw "Sensitive value found in $($file.Name)." }
        }
    }
}

$report = [pscustomobject]@{
    PackageName = $PackageName
    ExpectedVersion = $ExpectedVersion.ToString()
    TimestampUtc = [DateTime]::UtcNow.ToString('o')
    Checks = $checks
}
$reportPath = Join-Path $resultsDirectory 'installed-smoke.json'
$report | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$failures = @($checks | Where-Object Status -eq 'FAIL')
Write-Output ("Installed smoke: {0} passed, {1} failed. Report: {2}" -f ($checks.Count - $failures.Count), $failures.Count, $reportPath)
if ($failures.Count -gt 0) { exit 1 }
