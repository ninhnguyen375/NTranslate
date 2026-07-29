Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$manifestPath = Join-Path $root 'packaging\manifest\AppxManifest.xml'
$layoutScript = Join-Path $root 'packaging\scripts\New-PackageLayout.ps1'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Missing canonical AppxManifest.xml.' }
[xml]$manifest = Get-Content -LiteralPath $manifestPath -Raw
$ns = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
$ns.AddNamespace('m', 'http://schemas.microsoft.com/appx/manifest/foundation/windows10')
$ns.AddNamespace('uap', 'http://schemas.microsoft.com/appx/manifest/uap/windows10')
$ns.AddNamespace('desktop', 'http://schemas.microsoft.com/appx/manifest/desktop/windows10')
$identity = $manifest.SelectSingleNode('/m:Package/m:Identity', $ns)
if ($identity.Name -ne 'NinhNguyen375.NTranslate') { throw 'Wrong package identity.' }
if ($identity.Publisher -ne 'CN=Ninh Nguyen') { throw 'Wrong publisher.' }
if ($identity.Version -ne '1.2.7.0') { throw 'Wrong pinned manifest version.' }
if ($identity.ProcessorArchitecture -ne 'x64') { throw 'Wrong architecture.' }
$target = $manifest.SelectSingleNode('/m:Package/m:Dependencies/m:TargetDeviceFamily', $ns)
if ($target.Name -ne 'Windows.Desktop' -or $target.MinVersion -ne '10.0.19045.0' -or $target.MaxVersionTested -ne '10.0.22621.0') { throw 'Wrong OS policy.' }
$application = $manifest.SelectSingleNode('/m:Package/m:Applications/m:Application', $ns)
if ($application.Executable -ne 'NTranslate.App.exe' -or $application.EntryPoint -ne 'Windows.FullTrustApplication') { throw 'Wrong full-trust entry point.' }
$capabilities = @($manifest.SelectNodes('/m:Package/m:Capabilities/*', $ns))
if ($capabilities.Count -ne 1 -or $capabilities[0].LocalName -ne 'Capability' -or $capabilities[0].Name -ne 'runFullTrust') { throw 'Capabilities exceed runFullTrust.' }

if (-not (Test-Path -LiteralPath $layoutScript -PathType Leaf)) { throw 'Missing layout script.' }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('ntranslate-layout-' + [guid]::NewGuid().ToString('N'))
$publish = Join-Path $temp 'publish'
$layout = Join-Path $temp 'layout'
try {
    New-Item -ItemType Directory -Path $publish | Out-Null
    Set-Content -LiteralPath (Join-Path $publish 'NTranslate.App.exe') -Value 'fixture'
    try { & $layoutScript -Version '2.3.4' -PublishPath $publish -LayoutPath $layout; throw 'Layout accepted missing compiled XAML resources.' } catch { if ($_.Exception.Message -eq 'Layout accepted missing compiled XAML resources.') { throw } }
    Set-Content -LiteralPath (Join-Path $publish 'NTranslate.App.pri') -Value 'fixture'
    & $layoutScript -Version '2.3.4' -PublishPath $publish -LayoutPath $layout
    if (-not (Test-Path -LiteralPath (Join-Path $layout 'NTranslate.App.pri') -PathType Leaf)) { throw 'Compiled XAML resources missing from layout.' }
    [xml]$generated = Get-Content -LiteralPath (Join-Path $layout 'AppxManifest.xml') -Raw
    $generatedIdentity = $generated.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Identity"]')
    if ($generatedIdentity.Version -ne '2.3.4.0') { throw 'Semantic version conversion failed.' }
    $resourcePaths = @(
        $generated.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Properties"]/*[local-name()="Logo"]').InnerText,
        $generated.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Applications"]/*[local-name()="Application"]/*[local-name()="VisualElements"]/@Square150x150Logo').Value,
        $generated.SelectSingleNode('/*[local-name()="Package"]/*[local-name()="Applications"]/*[local-name()="Application"]/*[local-name()="VisualElements"]/@Square44x44Logo').Value)
    foreach ($resourcePath in $resourcePaths) {
        if (-not (Test-Path -LiteralPath (Join-Path $layout $resourcePath) -PathType Leaf)) { throw "Manifest resource missing from layout: $resourcePath" }
    }
    try { & $layoutScript -Version '2.3' -PublishPath $publish -LayoutPath $layout; throw 'Malformed version accepted.' } catch { if ($_.Exception.Message -eq 'Malformed version accepted.') { throw } }
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'PASS: manifest and layout'
