# NTranslate for Windows

Native Windows tray app that translates selected text with a global hotkey. Calls an OpenAI-compatible chat/TTS API and shows a popup near the cursor.

Built with .NET 10 and WinUI 3 (Windows App SDK), packaged as an MSIX, and deployed via App Installer.

## Prerequisites

- Windows 10 build 19045 or later (x64)
- [9router](https://github.com/decolua/9router) running locally (recommended), or any OpenAI-compatible chat + speech API

## Installation

Download the latest `NTranslate-*-win-x64.msix` from [Releases](https://github.com/ninhnguyen375/NTranslate/releases) and double-click to install via Windows App Installer.

If this is a local development build or unsigned test build, you may need to trust the certificate first (see Development below). Official releases will be properly signed.

## Configuration

Settings are stored in `%LOCALAPPDATA%\NTranslate\config.json`. The app will create this with defaults pointing to 9router on first launch.

Right-click the tray icon and select **Settings...** to view the configuration folder, or edit the JSON directly. After editing, right-click the tray icon and select **Reload Config**.

## Development

Build requirements:
- .NET SDK 10.0.301
- PowerShell 5.1

NTranslate for Windows uses a strict no-Visual-Studio-workloads build process to ensure clean, predictable CLI builds.

Crash diagnostics redact structured secret/content fields and use fixed UTF-8 ceilings: message 8 KiB, stack trace 64 KiB, serialized file 80 KiB. Only newest 10 crash files are retained.

### Build and Test

```powershell
# Restore exact package versions
dotnet restore .\windows\NTranslate.slnx --locked-mode

# Build and run tests
dotnet build .\windows\NTranslate.slnx -c Release --no-restore
dotnet test .\windows\NTranslate.slnx -c Release --no-build --no-restore
```

### Packaging and Installation

The `install-app.ps1` script handles full build, packaging, self-signing, and installation.

`Add-AppxPackage` owns transactional behavior until deployment commits. After commit, identity verification or launch failure leaves new package installed because script does not retain prior MSIX for downgrade. Retry launch from Start. To recover by uninstalling, run `Get-AppxPackage -Name NinhNguyen375.NTranslate | Remove-AppxPackage`, then reinstall known-good package.

> **Security Warning:** The script will create a self-signed code signing certificate and add it to your `CurrentUser\TrustedPeople` store to allow App Installer to work. Only do this on development machines. There is no signature-disable workaround for MSIX.

```powershell
# Package, sign with local cert, and install
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\install-app.ps1 -Version 1.0.0 -TrustDevelopmentCertificate
```

The script manages the certificate under `%LOCALAPPDATA%\NTranslate\Signing`.

### Automated Smoke Tests

After installation, run the UI automation tests to verify package behavior:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-InstalledAppSmoke.ps1 -PackageName NinhNguyen375.NTranslate -PackagePath .\windows\artifacts\packages\NTranslate-1.0.0-win-x64.msix -ExpectedVersion 1.0.0.0 -ResultsPath .\windows\artifacts\smoke
```

## Accessibility

NTranslate for Windows implements UI Automation (UIA) standards:

- All interactive controls have accessible names
- Logical tab progression through the UI
- No color-only status indicators
- Dialogs announce their presence and initial focus is safe
- Full keyboard operability

Use tools like Accessibility Insights for Windows to verify the application tree.

## Release Process

The build system creates an MSIX package signed with Authenticode.

To inspect a generated package signature:
```powershell
Get-AuthenticodeSignature .\windows\artifacts\packages\NTranslate-1.0.0-win-x64.msix | Select-Object Status, StatusMessage, SignerCertificate
```

To completely remove the app and its data:
```powershell
Get-AppxPackage -Name NinhNguyen375.NTranslate | Remove-AppxPackage
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\NTranslate"
```