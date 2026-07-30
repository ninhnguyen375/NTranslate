# Windows popup version and local release design

## Scope

- Show running Windows package version in popup title as `NTranslate 1.2.3`.
- Make manual update check run immediately, then show one result dialog.
- Remove GitHub Actions Windows release workflow and workflow-specific tests.
- Keep local installer build and release upload flow; update Windows README wording to match.

## Design

Resolve current version once in `AppComposition` before creating `TranslationWindow`. Pass `SemanticVersion` into popup and expose formatted title text. Existing update coordinator receives same resolved value.

`ManualUpdateFlow.RunAsync` calls `UpdateCoordinator.CheckAsync` first. It then shows current/error/available result. Available result keeps explicit Install confirmation and existing verified installer path.

Delete `.github/workflows/windows-release.yml` and `windows/packaging/tests/ReleaseWorkflow.Tests.ps1`. Keep `windows/install-app.ps1`, Inno Setup packaging, checksum generation, and updater release conventions unchanged.

## Verification

- XAML/source test requires popup title binding and `NTranslate 1.2.3` formatting.
- Update flow test proves check starts before any dialog can block it and install still needs confirmation.
- Script tests no longer expect GitHub Actions workflow.
- Full Windows tests and `install-app.ps1` pass; installed popup displays package version.
