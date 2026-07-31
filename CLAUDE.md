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
  .\install-app.ps1 -Version <version>
  ```

- Do not run installer for read-only analysis, review, planning, or documentation-only changes.
- Root installer requires explicit semantic `-Version`; use a version greater than latest Windows release when preparing a new release build.
- Windows app is unpackaged under Inno Setup. `Package.Current.Id.Version` may fail; runtime version resolution must retain assembly-version fallback.
- `windows/install-app.ps1` must pass `-p:Version=$Version` to both `dotnet build` and `dotnet publish`; installer filename alone does not stamp assembly version.
- Installer runs locked restore, Release build, full tests, publish, Inno Setup packaging, SHA-256 generation, per-user installation, verification, and app launch.
- Before installation, run `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\packaging\scripts\Invoke-ScriptTests.ps1` and `dotnet test .\windows\NTranslate.slnx --no-restore`.
- Always report `Version`, `Build`, setup EXE path, checksum path, and test result from installer output.
- If tests fail, report exact failures. Do not bypass or hide failures to install.
- For tray interaction fixes, `PostMessage` is not representative of Explorer callback delivery. Test dispatch through the window procedure with `SendMessage`, then verify the installed app. Do not claim physical tray clicks work until user confirmation or observed Explorer interaction.

## Update flow

- Manual update checks must run network lookup before showing result dialog; never await a modal “Checking” dialog before starting lookup.
- WinUI dialogs must be created on UI thread. Do not use `ConfigureAwait(false)` across an await whose continuation opens `ContentDialog`.
- Current version, release tag, installer filename, checksum filename, and assembly version must describe same semantic version.
- Valid Windows releases use tag `windows-v<version>` and exactly one matching setup EXE plus one `.sha256` sidecar.

## Release

- Windows release artifacts are `NTranslate-<version>-win-x64-setup.exe` and `NTranslate-<version>-win-x64-setup.exe.sha256`.
- Build and test Windows releases locally; GitHub Actions does not build Windows artifacts.
- Upload both local artifacts to matching `windows-v<version>` GitHub Release. Do not mix Windows assets into macOS `v<version>` releases.
- Do not commit, push, publish, or create a GitHub Release unless user explicitly requests it.
- Do not run macOS `release-dmg.sh` on this branch.
