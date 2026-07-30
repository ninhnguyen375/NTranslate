# Windows Per-User EXE Installer Design

## Goal

Replace Windows MSIX distribution with unsigned Inno Setup EXE distribution. Installation requires neither administrator elevation nor manual certificate trust. GitHub Releases remains update source.

## Release artifacts

Each Windows release contains exactly these installer artifacts:

- `NTranslate-<version>-win-x64-setup.exe`
- `NTranslate-<version>-win-x64-setup.exe.sha256`

GitHub Actions restores, tests, publishes `win-x64`, compiles Inno Setup installer, computes SHA-256 sidecar, and uploads both assets. Installer remains unsigned initially, so release documentation must explain possible SmartScreen `More info` / `Run anyway` flow.

## Installer

Inno Setup uses `PrivilegesRequired=lowest` and installs under `{localappdata}\Programs\NTranslate`. It creates per-user Start Menu and uninstall entries and writes no machine-wide registry or certificate stores.

Before installation, installer checks current user for package identity `NinhNguyen375.NTranslate`. If legacy MSIX exists, installation stops and tells user to uninstall it in Windows Settings, then rerun setup. Installer does not remove config, credentials, or history.

Installer closes a running NTranslate process during update, replaces installed files, and launches NTranslate after successful interactive or silent installation. App data remains in existing per-user locations.

## In-app update

Existing GitHub release selection changes from `.msix` to matching setup EXE plus checksum sidecar. Update flow:

1. Select newer stable release containing exact versioned setup and checksum asset names.
2. Download both files from allowed GitHub HTTPS hosts into bounded temporary storage.
3. Parse checksum sidecar as one SHA-256 digest for exact setup filename.
4. Hash downloaded setup and compare digest without data-dependent early exit.
5. Launch setup with silent per-user update arguments and request restart after success.
6. Exit running app so installer can replace files.

Missing, malformed, mismatched, oversized, or unsafe assets fail closed. UI reports update failure without launching installer.

SHA-256 protects download integrity and accidental asset replacement. GitHub account/release control remains trust root; this design does not claim protection after repository compromise.

## Migration and removal

MSIX packaging, development certificate management, MSIX verifier, and MSIX release assets leave supported release path. Legacy MSIX users manually uninstall before first EXE installation. Source files may remain only where required for an explicit compatibility test; otherwise obsolete packaging code and tests are deleted.

Root `install-app.ps1` becomes local EXE build/install verification and must not touch TrustedPeople. Project branch policy still requires it after Windows packaging changes.

## Verification

Automated checks cover:

- Inno script per-user policy, paths, legacy MSIX guard, close/restart behavior.
- Exact release asset selection for setup and checksum.
- Checksum parsing, filename binding, mismatch rejection, and successful verification.
- Safe GitHub URL and download-size boundaries.
- Updater process path and silent arguments.
- GitHub Actions artifact names and build order.
- Script tests, full .NET tests, installer compilation, per-user install, installed smoke checks, and launch.

## Deliberate limits

- No custom rollback layer; Inno Setup owns installation replacement behavior.
- No machine-wide install mode.
- No portable ZIP artifact.
- No automatic legacy MSIX removal.
- No public code-signing certificate yet; add signing when certificate or Microsoft Trusted Signing becomes available.
