# Windows Install Workflow Design

## Scope

Make `windows-app` self-contained for Windows development. Remove project instructions that require macOS build, install, DMG, or release workflows. Add one root PowerShell entrypoint for local Windows build, package, signing, installation, verification, and launch.

## Entrypoint

Create `install-app.ps1` at repository root. It must:

1. Fail outside Windows.
2. Read `Identity.Version` from `windows/packaging/manifest/AppxManifest.xml`.
3. Require four numeric MSIX version components with revision `0`.
4. Convert `major.minor.patch.0` to strict semantic version `major.minor.patch`.
5. Invoke `windows/install-app.ps1` with that version and `-TrustDevelopmentCertificate`.
6. Propagate failures and output without duplicating child orchestration.

Manifest version is single source of truth. Local installation does not bump it.

## Existing Installer Ownership

`windows/install-app.ps1` remains responsible for:

- host, OS, architecture, and .NET SDK validation;
- locked restore, Release build, full tests, and publish;
- MSIX layout and packaging;
- development or external certificate signing;
- signature verification;
- `Add-AppxPackage -ForceApplicationShutdown`;
- installed identity/version verification;
- app launch;
- Version, Build, Package, Identity, OS, and tested-target output.

No build or packaging logic moves to root wrapper.

## Certificate Behavior

Root wrapper always enables `-TrustDevelopmentCertificate`. This may create self-signed code-signing certificate and add it to current user's `TrustedPeople` store. `CLAUDE.md` must identify this as development-machine behavior. No signature bypass is added.

## Project Instructions

Replace macOS-specific `CLAUDE.md` content with Windows rules:

- `windows-app` is primary branch for Windows app work.
- Ignore Swift, `.app`, DMG, `install-app.sh`, and `release-dmg.sh` workflows on this branch.
- Run `.\install-app.ps1` after source, resource, manifest, build, packaging, or release-script changes affecting Windows app.
- Do not install for read-only analysis, review, planning, or documentation-only changes.
- Report Version, Build, package path, and test result from installer output.
- Do not commit, push, publish, or create release unless requested.
- Windows release artifact is `NTranslate-<version>-win-x64.msix`.

Delete obsolete root `install-app.sh`. Leave unrelated macOS source and release files untouched.

## Tests

Add a small PowerShell test for root wrapper. Test must prove:

- manifest `1.2.3.0` becomes child `-Version 1.2.3`;
- child receives `-TrustDevelopmentCertificate`;
- nonzero revision is rejected;
- malformed or missing identity version is rejected.

Use injectable script/manifest paths or invocation callback only if needed to test without building or installing. Keep production wrapper minimal.

Verification order:

1. Wrapper regression test RED before implementation.
2. Wrapper regression test GREEN after implementation.
3. Existing packaging script tests.
4. Full `dotnet test windows/NTranslate.slnx --no-restore`.
5. `.\install-app.ps1` only when automated tests pass, because it modifies installed package and certificate trust store.

Known unrelated `WindowsSpeechPlayerTests` failures must be reported rather than hidden or bypassed.
