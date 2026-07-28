Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$xamlFiles = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\..\src\NTranslate.App') -Filter '*.xaml' -File -Recurse)
if ($xamlFiles.Count -eq 0) { throw 'No app XAML files found.' }

foreach ($file in $xamlFiles) {
    [xml] $document = Get-Content -LiteralPath $file.FullName -Raw
    $namedIds = @{}
    $interactive = @($document.SelectNodes("//*[local-name()='Button' or local-name()='ToggleButton' or local-name()='ComboBox' or local-name()='TextBox']"))
    foreach ($control in $interactive) {
        $name = $control.GetAttribute('Name', 'http://schemas.microsoft.com/winfx/2006/xaml')
        $automationName = $control.GetAttribute('AutomationProperties.Name')
        if ([string]::IsNullOrWhiteSpace($name)) { throw "$($file.Name): interactive control lacks x:Name." }
        if ([string]::IsNullOrWhiteSpace($automationName)) { throw "$($file.Name): $name lacks AutomationProperties.Name." }
        if ($namedIds.ContainsKey($name)) { throw "$($file.Name): duplicate x:Name '$name'." }
        $namedIds[$name] = $true
        if ($control.GetAttribute('IsTabStop') -eq 'False') { throw "$($file.Name): $name cannot opt out of keyboard focus." }
    }

    $liveRegions = @($document.SelectNodes("//*[@AutomationProperties.LiveSetting]"))
    foreach ($region in $liveRegions) {
        if ($region.GetAttribute('AutomationProperties.LiveSetting') -notin 'Polite', 'Assertive') {
            throw "$($file.Name): invalid live-region setting."
        }
    }
}

Write-Output ("PASS: {0} XAML file(s), interactive names unique, keyboard focus retained, live regions valid." -f $xamlFiles.Count)
