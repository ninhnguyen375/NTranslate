# Windows popup, speech state, and Japanese source design

## Scope

Fix first-save behavior when `config.json` is absent, make `Alt+Enter` translate source text, show speech play/pause icons from actual playback state, and add Japanese as a source language with `edge-tts/ja-JP-NanamiNeural`.

## Behavior

- `JsonConfigStore.LoadAsync` returns `AppConfig.Default` when its file is absent. Save then creates the file atomically.
- `Alt+Enter` in source text input invokes the same translation path as Translate button and consumes the key event. Plain Enter remains multiline input.
- Speech buttons show Pause while their matching channel is playing. They show Play while paused, idle, failed, or finished. Loading retains existing loading behavior.
- Japanese appears in source-language choices for default and existing configs.
- Japanese source speech resolves to `edge-tts/ja-JP-NanamiNeural` by default and has an editable Advanced Settings field.

## Architecture

- Keep keyboard gesture routing in popup window, next to existing button handlers.
- Keep playback phase in `SpeechCoordinator`/`SpeechPlaybackState`; expose state changes to `TranslationViewModel`, then notify window to update glyphs. Window does not infer state from clicks.
- Extend `AppConfig`, `SettingsDraft`, Settings XAML, and speech model resolver with Japanese model.
- Normalize parsed configs in `ConfigJson`: append `Japanese` case-insensitively when absent and supply default Japanese model when absent. Preserve user language ordering and configured values.

## Error and cancellation behavior

- Existing translation, speech exception, and cancellation handling stays unchanged.
- Speech state notifications run for play, pause, resume, finish, failure, cancellation, and invalidation so icons return to Play.
- Config parse errors retain existing startup guidance behavior; only missing optional Japanese data migrates.

## Verification

- Regression test missing config file load.
- Keyboard policy/XAML test for `Alt+Enter` and Translate invocation.
- Speech state/view-model tests for Play/Pause transitions and playback end.
- Config default, legacy migration, settings round-trip, and resolver tests for Japanese.
- Required script tests and full solution tests.
- Bump manifest version and pinned manifest expectation together, run `install-app.ps1`, then report Version, Build, package path, tests, and launch/install result.
