# NTranslate Windows

## Branch scope

- `windows-app` is primary branch for Windows app development.
- `windows-app` is permanently separate from `main`; never merge it into `main` and never create a PR targeting `main`.
- Keep Windows commits and releases on `windows-app` or branches explicitly based on and targeting `windows-app`.
- Do not merge, rebase, or cherry-pick between `windows-app` and `main` unless user explicitly requests a specific operation.
- Ignore Swift, macOS `.app`, DMG, `install-app.sh`, and `release-dmg.sh` workflows on this branch.
- Windows source, tests, packaging, and release files live under `windows/`.

## Workflow

- After completing changes to Windows source, resources, manifest, build scripts, packaging scripts, or release metadata, run:

  ```powershell
  .\install-app.ps1
  ```

- Do not run installer for read-only analysis, review, planning, or documentation-only changes.
- Root installer reads version from `windows/packaging/manifest/AppxManifest.xml`; do not bump version unless task requires it.
- Before installation, ensure manifest version is greater than installed MSIX version; Windows rejects package downgrades with `0x80073D06`.
- When version bump is approved, update manifest and its pinned expectation in `windows/packaging/tests/Manifest.Tests.ps1` together.
- Installer runs locked restore, Release build, full tests, publish, MSIX packaging, signing, installation, verification, and app launch through `windows/install-app.ps1`.
- Before installation, run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1` and `dotnet test .\windows\NTranslate.slnx --no-restore`.
- Always report `Version`, `Build`, package path, and test result from installer output.
- If tests fail, report exact failures. Do not bypass or hide failures to install.
- For tray interaction fixes, `PostMessage` is not representative of Explorer callback delivery. Test dispatch through the window procedure with `SendMessage`, then verify the installed app. Do not claim physical tray clicks work until user confirmation or observed Explorer interaction.
- For post-install Application Event Log checks, set baseline after `Add-AppxPackage -ForceApplicationShutdown`; shutdown events from replaced process do not describe newly launched process.

## Development certificate

- `.\install-app.ps1` may create a self-signed code-signing certificate and trust it in `CurrentUser\TrustedPeople` and `LocalMachine\TrustedPeople`.
- Machine trust requires UAC elevation and affects every user until exact certificate thumbprint is removed. Use this only on development machines. Never disable MSIX signature verification.

## Release

- Windows release artifact is `NTranslate-<version>-win-x64.msix`.
- Do not commit, push, publish, or create a GitHub Release unless user explicitly requests it.
- Do not run macOS `release-dmg.sh` on this branch.
