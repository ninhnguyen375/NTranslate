[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$tests = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..\tests') -Filter '*.Tests.ps1' | Sort-Object Name)
if ($tests.Count -eq 0) { throw 'No script tests found.' }

$passed = 0
foreach ($test in $tests) {
    & $test.FullName
    $passed++
}

Write-Output "PASS: $passed script test files"
