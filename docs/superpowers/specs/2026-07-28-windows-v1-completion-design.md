# Windows v1 Completion Design

**Date:** 2026-07-28

## Goal

Complete Windows v1 functional parity in one delivery: Learn, image translation/search, speech, history, bookmarks, complete Settings, crash recovery, GitHub update checks, signed x64 MSIX packaging, installation, and installed-app smoke tests.

Work runs in parallel by subsystem. Each subsystem runs focused tests, but code review occurs once after integration. Completion requires a signed MSIX installed on this Windows 10 22H2 x64 host and automated smoke tests against the installed app.

## Scope

This delivery includes:

- Learn word and Learn sentence flows
- same-language grammar mode
- bounded clipboard image normalization and multimodal translation
- contextual Google Images search
- source and result TTS with play, pause, resume, rate, prefetch, and memory cache
- local text-translation history, search, time filters, bookmarks, audio attachment, reopen, and deletion
- complete Fluent Settings UI with secure Credential Locker API-key storage
- transactional config save and custom history-directory migration
- redacted crash logs and one-time recovery notice
- GitHub Releases update checks, strict Windows asset selection, download, package verification, and App Installer handoff
- signed x64 MSIX packaging, development-certificate workflow, installation, Windows docs, accessibility checks, and installed-app smoke tests

Learn and image operations do not create history. Successful text Translate and same-language grammar operations do.

## Delivery Strategy

Use three parallel subsystem tracks, followed by one integration and review track.

### Track A: Translation Media

Owns:

- `windows/src/NTranslate.Core/Translation/`
- `windows/src/NTranslate.Core/Speech/`
- `windows/src/NTranslate.Platform/Images/`
- `windows/src/NTranslate.Platform/Media/`
- `windows/src/NTranslate.Platform/Shell/`
- matching focused tests
- translator popup controls and ViewModel behavior, except shared integration files

Delivers Learn, grammar, image translation/search, TTS state, Windows playback, cache, and stale-request protection.

### Track B: History, Settings, and Recovery

Owns:

- `windows/src/NTranslate.Core/History/`
- `windows/src/NTranslate.Core/Settings/`
- `windows/src/NTranslate.Core/Recovery/`
- `windows/src/NTranslate.Platform/Storage/`
- `windows/src/NTranslate.Platform/Diagnostics/`
- History and Settings windows and ViewModels
- matching focused tests

Delivers atomic history/audio persistence, filters, bookmarks, deletion, reopen, transactional Settings, custom-directory migration, crash logging, and recovery notice.

### Track C: Package and Update

Owns:

- `windows/src/NTranslate.Core/Updates/`
- `windows/src/NTranslate.Platform/Updates/`
- `windows/packaging/`
- `windows/install-app.ps1`
- Windows installation/release documentation
- matching focused and script tests

Delivers semantic-version and asset policy, GitHub client, bounded atomic download, MSIX verification, update UI coordination, packaging, signing, installation, and installed smoke infrastructure.

### Integration Ownership

Shared files remain integration-owned to reduce merge conflicts:

- project files and central build configuration
- `AppConfig`
- application startup and composition root
- shared translator ViewModel constructor or service wiring
- tray menu wiring
- final XAML resource registration

Subsystem tracks may define required contracts, but integration applies shared-file changes after comparing all requirements.

## Architecture

Keep existing project boundaries:

- `NTranslate.Core`: pure .NET models, policy, validation, filtering, state machines, and coordinators; no WinUI or Win32 references.
- `NTranslate.Platform`: Windows adapters for media, images, filesystem, credentials, diagnostics, browser launch, package verification, and installer handoff.
- `NTranslate.App`: WinUI 3 windows, ViewModels, tray commands, dialogs, and composition.

Use .NET, WinUI, WinRT, and Win32 APIs before dependencies. Do not add a database, ORM, MVVM framework, logging package, audio converter, or third-party HTTP client.

## Functional Data Flow

### Translation, Learn, and Images

1. Selection capture or manual input populates translator source.
2. Translator starts a generation-gated, cancellable operation.
3. Translate chooses normal or same-language grammar prompt. Learn chooses word or sentence prompt by existing policy.
4. Clipboard images are decoded with overflow-safe bounds, normalized to PNG, and rejected if limits are exceeded.
5. Accepted successful text Translate or grammar results are persisted to history before history-linked UI state is exposed.
6. Learn and image results remain session-only.
7. Image search uses a generated short query and falls back to source text when generation fails. Cancellation prevents browser launch.

Every operation checks its generation before changing result, status, history, browser, or speech state. Cancellation alone is not treated as sufficient stale-response protection.

### Speech

Source and result channels maintain independent idle, loading, playing, paused, and failed states.

Explicit playback fetches on demand. Optional prefetch occurs only after an accepted successful text translation. Audio bytes must pass platform validation before entering memory cache or history storage. Cache identity uses channel, text, and model; history record identity remains separate so valid cached bytes can attach only to the intended record. Changing source, languages, image mode, or window lifecycle invalidates affected speech operations.

### History

History uses newest-first JSON records under `%LOCALAPPDATA%\NTranslate` or a validated custom root. Writes use same-directory temporary files and atomic replacement. In-memory state changes only after persistence succeeds.

Malformed or duplicate history enters read-only mode and preserves original bytes. Audio paths must be owned relative paths and reject rooted paths, traversal, and reparse-point escape. Record deletion removes metadata first, then only validated owned audio.

History UI supports source/result search, Saved-only, All, Today, last 24 hours, Week, and Month filters; source/result audio; bookmark toggle; single deletion; confirmed visible deletion; and reopen by double-click or Enter.

### Settings

Settings edits a deep copy of current configuration. Save order is:

1. validate all fields and paths
2. prepare custom-history migration when needed
3. update Credential Locker secret
4. atomically save secret-free config
5. commit migration
6. replace runtime configuration and dependent services

Failure before completion keeps runtime configuration unchanged and rolls back owned changes. Rollback failures report both primary and rollback errors. Cancel writes nothing. API keys never enter config JSON, logs, diagnostics, fixtures, or committed files.

### Recovery

Unhandled WinUI, AppDomain, and task exceptions write bounded structured crash logs under `Logs`. Logs redact authorization values, API keys, passwords, and tokens and omit translation and clipboard content. Next launch shows one notice for newest unacknowledged crash log and atomically records acknowledgement.

### Updates

Updater reads latest GitHub Release over HTTPS, rejects draft and prerelease releases, compares strict semantic versions, and selects exactly one case-sensitive `NTranslate-<version>-win-x64.msix` asset.

Download streams to a partial file and atomically publishes only after success. Before installation handoff, verifier requires:

- valid Windows signature
- expected package identity
- expected publisher
- x64 architecture
- package version matching selected release
- safe bounded manifest parsing

Only verified packages open through Windows App Installer. Application code does not run an elevated replacement script or bypass signature checks.

## Error Handling and Data Safety

- Network, HTTP, authentication, parsing, and model errors remain visible while preserving source input for retry.
- Image and audio validation failures do not cache or persist invalid bytes.
- Persistence failures preserve last valid files and runtime state.
- Credential/config/migration save behaves transactionally with rollback.
- Stale or cancelled operations cannot mutate current UI.
- Hotkey, selection, clipboard, and media failures leave manual translation usable.
- Update failures never hand an unverified package to App Installer.
- Logs and test diagnostics exclude secrets and request content.

## Testing and Review

Each subsystem follows TDD and leaves focused runnable tests. Intermediate subsystem work does not receive separate code-review rounds.

Integration performs:

1. reconcile `AppConfig` and shared contracts
2. wire services into application composition
3. connect popup, history, settings, recovery, tray, and update commands
4. run full Release tests and build
5. run `git diff --check`
6. review complete integrated diff once for correctness, races, security, data loss, accessibility, reuse, and unnecessary complexity
7. verify and fix confirmed findings
8. rerun full verification

Required automated coverage includes:

- prompt/mode selection and stale-generation races
- image size, format, cancellation, and URL policy
- speech state, identity, cache, playback, and history attachment
- history filtering, atomic writes, malformed-data lockout, audio containment, and deletion
- Settings validation, transaction order, rollback, and migration safety
- crash-log selection, acknowledgement, redaction, and write failures
- semantic versions, release parsing, asset selection, download cleanup, package identity, and signature checks
- XAML accessible names, keyboard actions, focus order, and non-color-only state
- packaging/install script command order, guards, redaction, and fail-fast behavior

## Packaging, Installation, and Smoke Tests

`windows/install-app.ps1` must:

1. verify supported Windows x64 host and pinned SDK
2. restore locked dependencies
3. build and test Release
4. publish deterministic x64 output
5. create package layout and versioned manifest
6. pack and sign MSIX
7. optionally trust only the explicit CurrentUser development certificate
8. install or update package for current user
9. launch installed app
10. print version, build, package path, identity, OS, and tested target

Automated installed-app smoke checks cover package identity/version/signature, launch, tray, single-instance activation, manual translation fixture, copy, history, bookmark, Settings secret exclusion, update fixture, invalid-package rejection, exit, and log redaction.

Manual smoke checks cover representative selection capture, clipboard image translation, TTS controls, multi-monitor popup placement, high contrast, and text scaling. Live external API checks are not required for completion; missing endpoint credentials or model capability must be reported as `BLOCKED` rather than passed.

Because this delivery changes only Windows implementation and tooling, do not run macOS `./install-app.sh`.

## Completion Criteria

Delivery is complete only when:

- all three subsystem scopes are integrated
- full .NET Release build and tests pass
- final integrated review has no unresolved confirmed findings
- x64 MSIX has valid expected signature and identity
- package installs or updates for current user on Windows 10 22H2
- installed automated smoke suite passes
- manual smoke outcomes are recorded as PASS, FAIL, or exact BLOCKED reason
- no secret, private key, PFX, certificate password, build artifact, or user data is committed
- Windows installation, privacy, update, certificate, and troubleshooting docs match shipped behavior
