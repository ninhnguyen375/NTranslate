# NTranslate for Windows

Native Windows tray app that translates selected text with a global hotkey. Calls an OpenAI-compatible chat/TTS API and shows a popup near the cursor.

Built with .NET 10 and WinUI 3 (Windows App SDK), installed per-user with no admin rights required.

## Prerequisites

- Windows 10 build 19041 or later (x64)
- [9router](https://github.com/decolua/9router) running locally (recommended), or any OpenAI-compatible chat + speech API

## Installation

Download the latest `NTranslate-<version>-win-x64-setup.exe` and matching `NTranslate-<version>-win-x64-setup.exe.sha256` from [Releases](https://github.com/ninhnguyen375/NTranslate/releases).

**Verify the checksum before running:**

```powershell
$name = 'NTranslate-1.2.14-win-x64-setup.exe'
$expected = (Get-Content "$name.sha256").Split(' ')[0]
$actual   = (Get-FileHash -Algorithm SHA256 $name).Hash.ToLowerInvariant()
if ($expected -ne $actual) { throw 'Checksum mismatch — do not run this file.' }
```

Run the installer. No administrator rights required. The app installs to `%LOCALAPPDATA%\Programs\NTranslate`.

> **SmartScreen warning:** Because the installer is not commercially code-signed, Windows may show a SmartScreen dialog. Click **More info → Run anyway** to proceed. Verify the SHA-256 checksum above before bypassing this warning.

> **Checksum trust limit:** SHA-256 confirms the downloaded file matches what GitHub Releases served. It does not guarantee the build pipeline itself was not compromised. For a stronger guarantee, build from source locally (see Development below).

## Migrating from the MSIX version

The new per-user EXE installer replaces the previous MSIX package. They cannot coexist.

**Before running the EXE installer**, uninstall the old MSIX package:

1. Open **Settings → Apps → Installed apps**
2. Search for **NTranslate**
3. Click the three-dot menu → **Uninstall**

Your translation history and settings in `%LOCALAPPDATA%\NTranslate\` are preserved across the migration.

## Uninstalling

Use **Settings → Apps → Installed apps → NTranslate → Uninstall**, or run the uninstaller at:

```
%LOCALAPPDATA%\Programs\NTranslate\unins000.exe
```

To also remove app data:

```powershell
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\NTranslate"
```

## Configuration

Settings are stored in `%LOCALAPPDATA%\NTranslate\config.json`. The app creates this with defaults pointing to 9router on first launch.

Right-click the tray icon and select **Settings...** to configure the API key, model, and languages.

## Development

Build requirements:

- .NET SDK 10.0.301
- PowerShell 5.1
- [Inno Setup 6](https://jrsoftware.org/isinfo.php) (for local installer builds)

NTranslate for Windows uses a strict no-Visual-Studio-workloads build process for clean, predictable CLI builds.

Crash diagnostics redact structured secret/content fields and use fixed UTF-8 ceilings: message 8 KiB, stack trace 64 KiB, serialized file 80 KiB. Only newest 10 crash files are retained.

### Build and Test

```powershell
dotnet restore .\windows\NTranslate.slnx --locked-mode
dotnet build   .\windows\NTranslate.slnx -c Release --no-restore
dotnet test    .\windows\NTranslate.slnx -c Release --no-build --no-restore
```

### Local build and install

```powershell
.\install-app.ps1 -Version 1.2.14
```

This runs restore → build → test → publish → ISCC compile → SHA-256 sidecar → silent per-user install → launch verification.

The installer places the app in `%LOCALAPPDATA%\Programs\NTranslate`. No administrator rights, no certificate trust stores, no HKLM writes.

### Automated Smoke Tests

After installation, verify the installed app:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-InstalledAppSmoke.ps1 -Version 1.2.14 -ResultsPath .\windows\artifacts\smoke
```

## Accessibility

NTranslate for Windows implements UI Automation (UIA) standards:

- All interactive controls have accessible names
- Logical tab progression through the UI
- No color-only status indicators
- Dialogs announce their presence and initial focus is safe
- Full keyboard operability

Use Accessibility Insights for Windows to verify the application tree.

## Release Process

GitHub Actions builds and uploads `NTranslate-<version>-win-x64-setup.exe` and its `.sha256` sidecar on each published release. No manual signing step is required.
