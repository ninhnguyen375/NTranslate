# NTranslate Windows Native Design

**Date:** 2026-07-27

## Goal

Build a native Windows edition of NTranslate with functional parity with the current macOS app. Windows UI may follow Fluent conventions instead of matching macOS Liquid Glass. Work is complete only when tests pass, an MSIX is built and installed on this Windows 11 machine, and installed-app smoke checks pass.

## Scope

Windows v1 includes every current macOS feature:

- system tray lifecycle and menu
- configurable global hotkey
- selected-text capture with clipboard fallback
- manual text entry when no selection is available
- clipboard image paste and multimodal translation
- text translation, Learn word, Learn sentence, and same-language grammar check
- configurable source, target, native, and available languages
- language detection, target selection, and swap
- source and result speech with play, pause, resume, rate, prefetch, and cache
- result copy and optional auto-copy
- contextual Google Images search
- local translation history, search, time filters, bookmarks, audio, reopen, and deletion
- complete Settings UI and secure API-key storage
- popup positioning, pinning, focus behavior, keyboard shortcuts, and stale-request protection
- crash recovery notice and local logs
- GitHub Releases update checks and MSIX handoff
- MSIX packaging, signing, installation, and Windows documentation

The Windows edition does not need to reproduce macOS-only visuals, Accessibility permission flows, Keychain, DMG installation, or AppKit behavior. It must provide equivalent Windows-native behavior.

## Supported Platform and Distribution

- Windows 11 22H2 or newer
- x64 initial architecture
- C# and WinUI 3 on current supported .NET and Windows App SDK versions available during implementation
- MSIX distributed through GitHub Releases
- self-signed development certificate initially; private key and certificate password never committed
- release asset naming pattern uses resolved semantic version, for example `NTranslate-1.0.0-win-x64.msix`

## Repository Architecture

Keep the existing Swift/AppKit app intact. Add an independent Windows implementation in the same repository:

```text
windows/
  NTranslate.sln
  src/
    NTranslate.App/
    NTranslate.Core/
    NTranslate.Platform/
  tests/
    NTranslate.Core.Tests/
    NTranslate.Platform.Tests/
  packaging/
    Package.appxmanifest
    scripts and non-secret signing metadata
  install-app.ps1
shared/
  contracts/
    JSON schemas, API fixtures, and parity test vectors
```

### NTranslate.Core

Pure .NET business logic with no WinUI or Win32 references:

- configuration models, defaults, migration, and validation
- language detection and target-language policy
- prompt substitution and mode selection
- OpenAI-compatible request and response models
- translation orchestration contracts
- history records, filtering, bookmark behavior, and path policy
- speech playback state
- update version and asset-selection policy

### NTranslate.Platform

Windows adapters behind small interfaces:

- Windows UI Automation selected-text reader
- clipboard snapshot, text/image decoding, simulated `Ctrl+C`, and restoration
- `RegisterHotKey` global hotkey
- foreground window, cursor, monitor, and work-area services
- Windows Credential Locker API-key store
- Windows media playback
- filesystem and atomic persistence
- startup registration
- crash logging
- MSIX identity and update installation handoff

### NTranslate.App

WinUI 3 composition root and Fluent UI:

- tray icon and menu
- translation popup
- history window
- settings window
- update and crash-recovery dialogs
- ViewModels that call Core and Platform services
- minimal code-behind only where Win32 window interop requires it

Use .NET and Windows APIs before dependencies: `HttpClient`, `System.Text.Json`, Windows App SDK, Win32 interop, Windows UI Automation, Credential Locker, and media APIs. Add a package only when no platform API covers a required behavior safely.

## Shared Contracts and Parity

Swift and C# source code remain independent. Shared files define observable behavior rather than introducing FFI:

- config and history JSON schemas
- prompt substitution vectors
- language-detection vectors
- version-comparison vectors
- OpenAI-compatible request/response fixtures
- update asset-selection vectors

Both Swift and .NET tests consume applicable vectors. Windows config and history live separately from macOS data and are not synchronized automatically.

## Application Lifecycle and Tray

The packaged app starts without a normal main window and owns one tray icon. Tray actions are:

- Open Translator
- Translation History
- Settings
- Check for Updates
- Start with Windows
- Exit

Single-instance activation routes later launches to the existing process and opens the translator. Exit unregisters the hotkey, stops media, flushes completed writes, and removes the tray icon.

## Global Hotkey and Selection Capture

The configured hotkey is registered with `RegisterHotKey`. Registration failure is visible in Settings and leaves the app usable through the tray.

On hotkey activation:

1. Capture the foreground window, cursor position, and clipboard sequence number.
2. Try Windows UI Automation `TextPattern` or `TextPattern2` for selected text.
3. If no text is available and simulated copy is enabled, snapshot supported clipboard formats, send `Ctrl+C`, and wait for a bounded clipboard sequence change.
4. Read Unicode text or supported image data from the clipboard.
5. Restore the prior clipboard after simulated copy without overwriting a clipboard that another process changed afterward.
6. Open manual-entry mode when no valid selection or image exists.

The app never automatically replaces text in the source application.

## Translation Popup

The Fluent popup appears near the cursor and remains inside the current monitor work area. It supports:

- editable source and read-only result regions
- source and target language selectors
- language swap with source/result swap
- Translate and Learn
- image-search action
- source and result speech controls
- result copy
- Save Word toggle for unchanged saved translations
- pin/unpin
- image preview and image-mode restrictions

Behavior:

- unpinned popup closes when deactivated; pinned popup stays open
- dragging the popup pins it
- `Escape` closes
- `Ctrl+Enter` translates
- `Ctrl+Shift+C` copies the result
- `Ctrl+Shift+L` runs Learn
- content or language changes invalidate the current result and bookmark association
- every request has a generation ID and `CancellationToken`; stale responses cannot mutate current UI
- no selection opens the same popup ready for manual input

## Translation, Learn, Grammar, and Image Search

Use configured OpenAI-compatible chat and speech endpoints with bearer authentication.

- Translate sends text with the translation prompt.
- Equal source and target languages select the grammar prompt.
- Learn selects the word prompt for one whitespace-delimited token and the sentence prompt otherwise.
- Auto-detect chooses a detected source and a different target, preferring recent target language where applicable.
- Image translation sends normalized PNG bytes as an `image_url` data URL to the configured multimodal model.
- Images are rejected before encoding or request when decoded or encoded limits are exceeded.
- Image mode disables source language, Learn, source speech, and history recording; result speech remains available.
- Image search asks the model for a short query and opens Google Images. API failure falls back to source text.
- Optional auto-copy copies a successful result.

## Speech

Speech calls the configured OpenAI-compatible speech endpoint. Source and result have independent state:

- idle
- loading
- playing
- paused
- failed

Controls support play, pause, resume, and rates from 0.5x through 1.5x. Explicit playback fetches on demand. Optional prefetch runs after successful text translation. Valid speech bytes may be cached in memory and attached to the matching history record on disk. Invalid or unsupported audio is rejected without crashing.

## History and Saved Words

Store Windows data under `%LOCALAPPDATA%\NTranslate` by default:

- `config.json`
- `history.json`
- `Audio\`
- `Logs\`

Only successful text Translate operations create history records. Learn and image translation do not.

History supports:

- newest-first records
- source/result search
- Saved-only filter
- Today, last 24 hours, Week, and Month filters
- source/result audio playback
- bookmark and unbookmark
- delete one record
- delete all currently visible records after confirmation
- double-click or activation to reopen a record in the popup

History and config writes use a temporary file and atomic replacement. Malformed history switches the store to read-only and reports the file path rather than overwriting data. Relative audio paths reject traversal, rooted paths, and reparse-point escape. Deleting a record deletes only validated audio owned by that record.

A custom history directory is supported. Validation occurs before runtime state changes; failed migration or write leaves prior settings and data intact.

## Settings and Credentials

Settings uses Fluent controls and covers every current `AppConfig` field:

- API base URL, speech URL, API key, and model
- source, target, native, available, and target languages
- Translate, Learn Word, Learn Sentence, and Grammar prompts
- speech models and automatic prefetch
- history directory
- popup dimensions
- auto-copy and simulated-copy
- global hotkey
- speech rate where applicable
- Start with Windows

Edit a copy of configuration and commit only after all validation and persistence succeeds. Failed Save keeps the window open and runtime configuration unchanged.

The API key is stored only in Windows Credential Locker. `config.json`, logs, diagnostics, tests, and committed fixtures contain no real key. Credential update and config update use rollback behavior so a config-write failure does not silently replace the working credential.

## Error Handling, Privacy, and Recovery

- Network, HTTP, authentication, parsing, and model errors appear in the popup while preserving source input for retry.
- UI Automation and clipboard failures fall back to manual entry.
- Hotkey registration failure appears in Settings.
- Persistence errors preserve the last valid file.
- Logs redact authorization headers and API keys.
- Translation text and clipboard image content are not logged by default.
- Unhandled exceptions write local diagnostics under `%LOCALAPPDATA%\NTranslate\Logs`.
- On next launch, a new unacknowledged crash log triggers one recovery notice.
- Selected text and images are sent only to the configured chat endpoint; speech text is sent only to the configured speech endpoint.

## Update Flow

The update service:

1. Reads the latest GitHub Release.
2. Compares semantic versions without treating malformed versions as newer.
3. Selects exactly the x64 Windows MSIX asset.
4. Silent startup checks notify only when an update exists.
5. Manual checks report update, up-to-date, and failure states.
6. Downloads the package to a temporary location.
7. Verifies expected MSIX identity, publisher, and signature before handoff.
8. Opens Windows App Installer for user-confirmed installation.

The app does not execute an elevated PowerShell replacement script. macOS DMG update behavior remains unchanged.

## Build, Signing, and Installation

`windows/install-app.ps1` performs the Windows workflow:

1. restore dependencies
2. build release x64
3. run all .NET tests
4. package MSIX
5. create or reuse a user-local self-signed development certificate when no release certificate is configured
6. sign the MSIX without exposing private key material
7. install or update the package for the current user
8. launch the installed app
9. print version, build, package path, and installed package identity

Private keys, `.pfx` files, passwords, build output, downloaded packages, and user config are gitignored. A future trusted code-signing certificate can replace the development certificate without changing package identity or application code.

The macOS `./install-app.sh` is not run for Windows-only changes because it only builds and installs `NTranslate.app`.

## Testing

### Core automated tests

- configuration defaults, migration, validation, and secret exclusion
- language detection, target choice, and swap
- prompt substitution and Learn mode selection
- request serialization and response parsing for text, vision, and speech
- request generation and stale-response rejection
- history atomic writes, malformed-data lockout, filters, bookmarks, deletion, and path containment
- speech state transitions and rate bounds
- semantic version comparison and Windows asset selection

### Platform automated and integration tests

- clipboard text/image conversion and bounded restoration policy
- hotkey parsing and registration error mapping
- Credential Locker lifecycle with test-specific credential names
- cursor/monitor popup clamping math
- update identity and signature validation
- filesystem behavior on Windows paths and reparse points

### Installed-app smoke checks

After MSIX installation on this machine:

- tray icon and menu appear
- second launch activates existing instance
- global hotkey opens popup
- selection capture works in representative native and browser apps, with fallback verified
- manual input, text translation, Learn, grammar mode, copy, auto-copy, and image paste work
- source and result speech load, play, pause, resume, and honor rate
- history records text translation, filters, bookmarks, audio, reopen, and deletion
- Settings persists after restart while API key remains outside JSON
- popup pinning, keyboard shortcuts, cursor placement, and multi-monitor clamping work
- update check reaches GitHub and handles current/no-update state
- keyboard navigation, focus order, accessible names, high contrast, and text scaling remain usable

External API-dependent checks use the user's configured endpoint. If no valid endpoint or model capability is available, local request/response fixtures verify client behavior and the blocked live check is reported explicitly rather than marked passed.

## Milestones

1. Solution, Core models, API client, config, credentials, and parity fixtures.
2. Single-instance tray app, hotkey, selection/clipboard pipeline, and text popup.
3. Learn, grammar, image translation/search, speech, and popup behavior.
4. History, bookmarks, audio cache, Settings, custom storage, and crash recovery.
5. Update flow, MSIX, signing, CI/build scripts, documentation, accessibility, and installed-app hardening.

Each milestone leaves runnable tests. Later milestones may adjust earlier internals only when required by verified Windows behavior.

## Completion Criteria

Work is complete when:

- every scoped macOS function has an equivalent Windows behavior
- Windows UI follows Fluent conventions and remains keyboard/accessibility usable
- all .NET tests pass
- release x64 MSIX builds and has a valid signature
- MSIX installs or updates successfully on this Windows 11 machine
- installed app launches and critical smoke checks pass
- live checks blocked by external credentials/services are listed with exact reason
- Windows build, certificate installation, configuration, privacy, update, and troubleshooting documentation is complete
- no secret or private signing material is committed
