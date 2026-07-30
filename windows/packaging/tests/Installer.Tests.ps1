Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$issPath = Join-Path (Join-Path $PSScriptRoot '..') 'NTranslate.iss'
if (-not (Test-Path -LiteralPath $issPath -PathType Leaf)) { throw 'Missing NTranslate.iss.' }
$iss = Get-Content -LiteralPath $issPath -Raw

if ($iss -notmatch 'PrivilegesRequired=lowest') { throw 'Installer must not require admin privileges.' }
if ($iss -notmatch '\{localappdata\}\\Programs\\NTranslate') { throw 'Installer must install per-user under LocalAppData\Programs\NTranslate.' }
if ($iss -notmatch 'ArchitecturesAllowed=x64compatible') { throw 'Installer must target x64.' }
if ($iss -notmatch 'ArchitecturesInstallIn64BitMode=x64compatible') { throw 'Installer must install in 64-bit mode.' }
if ($iss -notmatch '#define AppVersion') { throw 'Installer must define AppVersion.' }
if ($iss -notmatch 'OutputBaseFilename=NTranslate-\{#AppVersion\}-win-x64-setup') { throw 'Installer must produce the exact versioned setup filename.' }
if ($iss -notmatch '#define SourceDir') { throw 'Installer must define SourceDir.' }
if ($iss -notmatch '#define OutputDir') { throw 'Installer must define OutputDir.' }
if ($iss -notmatch '(?m)^AppId=\{\{[0-9A-Fa-f-]{36}\}$') { throw 'Installer must have a stable AppId.' }
if ($iss -notmatch 'CloseApplications=force') { throw 'Installer must close running applications.' }
if ($iss -notmatch 'RestartApplications=yes') { throw 'Installer must restart applications after install.' }
if ($iss -notmatch '\[Icons\]') { throw 'Installer must define Start Menu shortcuts.' }
if ($iss -notmatch 'Name: "\{autoprograms\}\\NTranslate"') { throw 'Installer must create a Start Menu shortcut.' }
if ($iss -notmatch 'Get-AppxPackage -Name NinhNguyen375\.NTranslate') { throw 'Installer must guard against a legacy MSIX install.' }
if ($iss -notmatch 'manually uninstall') { throw 'Installer must instruct manual MSIX uninstall.' }
if ($iss -match 'HKLM') { throw 'Installer must not touch HKLM registry keys.' }
if ($iss -match 'TrustedPeople|Cert:\\') { throw 'Installer must not reference certificate trust stores.' }
if ($iss -match 'Remove-AppxPackage') { throw 'Installer must not automatically remove the legacy MSIX package.' }

Write-Output 'PASS: per-user installer policy'
