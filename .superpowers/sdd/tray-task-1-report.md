# Tray/Popup Task 1 Report

## RED

- Added focused `SelectionCaptureServiceTests` before production code.
- Focused run failed at compile time as expected: missing `NTranslate.Platform.Capture`, `Clipboard`, and `Input` contracts.
- Review-found cancellation cleanup test failed as expected: clipboard remained `private selected text` instead of restored `original`.

## GREEN

- Added capture contracts and `SelectionCaptureService` coordinator.
- Added clipboard and simulated-copy contracts only; native adapters remain later tasks.
- Capture order: UI Automation, optional simulated copy, existing clipboard.
- Production defaults: 250 ms timeout, bounded 10 ms polling.
- Outer whitespace trimmed; internal whitespace preserved.
- UI Automation failures fall through with type-only diagnostic metadata. Selected text and exception messages never enter diagnostic.
- Simulated-copy snapshot conditionally restores on success and cancellation.
- Fakes use injected delay and in-memory sequence numbers for deterministic tests.

Focused result:

```text
Passed: 8, Failed: 0, Total: 8
```

## Full tests

Command:

```powershell
dotnet test .\windows\NTranslate.slnx -c Release
```

Result:

```text
NTranslate.Core.Tests: Passed 51, Failed 0
NTranslate.Platform.Tests: Passed 9, Failed 0
Total: Passed 60, Failed 0
```

`-p:Platform=x64` was not valid for current solution configuration, so full tests ran with solution default platform.

## Self-review

- Checked task scope: platform contracts/coordinator and tests only.
- No Swift, installer, app source, metadata, or build/release script changes.
- `git diff --check` clean.
- Independent review found cancellation could skip clipboard restore; added failing regression test and fixed with conditional restore in `finally`.
- Remaining concern: native clipboard and `SendInput` adapters intentionally deferred to Task 3.
