# Task 3 report

## RED

Created policy tests before production code. Ran:

```powershell
dotnet test .\windows\NTranslate.slnx --filter "FullyQualifiedName~LanguagePolicyTests|FullyQualifiedName~PromptRendererTests"
```

Result: failed at compile time as expected. `NTranslate.Core.Languages`, `NTranslate.Core.Prompts`, and `PromptMode` were absent.

## GREEN

Added `LanguagePolicy` and `PromptRenderer` Windows Core policies. Coverage includes shared language/prompt vectors, Auto source target selection, configured/native/first-target fallback, same-language grammar pair, swapping, whitespace learn mode, and supported placeholder-only replacement.

Ran:

```powershell
dotnet test .\windows\NTranslate.slnx -c Release --filter "FullyQualifiedName~LanguagePolicyTests|FullyQualifiedName~PromptRendererTests"
```

Result: 17 passed, 0 failed.

## Full tests

Ran:

```powershell
dotnet test .\windows\NTranslate.slnx -c Release
```

Result: 27 passed, 0 failed, 0 skipped. Platform test project reports no tests available.

## Self-review

- No Swift edits.
- No installer run.
- No plan/spec written.
- Exact ordinal replacement limited per renderer: translation replaces source/target, grammar replaces native/lang, learn replaces source/target.
- Vietnamese detection normalizes combining marks; Chinese uses U+4E00 through U+9FFF; English fallback deterministic.
- `ResolvePair` preserves configured `Auto detect` source while using detected language only to avoid same target.

## Concern

`LanguagePair` retains `Auto detect` for auto-source calls, matching shared resolution vector. Downstream caller must detect source before sending translation prompt if prompt requires concrete source language.
