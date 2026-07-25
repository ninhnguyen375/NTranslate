# NTranslate GitHub Issues #1–#6 Design

## Scope

Implement all six open GitHub issues with native Foundation/AppKit/AVFoundation only:

1. Send clipboard images to the configured LLM with an OCR/translation instruction.
2. Bookmark the current translated word/result.
3. Disable automatic TTS prefetch by configuration.
4. Pause and resume speech playback.
5. Persist successful translation history with optional source/result audio.
6. Use sentence-aware learning prompts.

## Product defaults

- Image mode sends PNG image bytes and asks the model to translate all readable text into the selected target language; the app displays the model response unchanged after trimming.
- Accessibility text has priority. If fallback clipboard content contains both raster image and text representations, image wins. `simulateCopy` uses the same input reader and restores the original clipboard.
- Only raster content readable as PNG/TIFF is accepted, normalized to PNG, then limited to 10 MiB. No preview, resizing, file URL or PDF support.
- The configured chat model must support OpenAI-compatible multimodal `image_url` data URLs.
- Image input cannot use source language selection, Learn or source speech. Result speech remains available. Images are not persisted in text history.
- `autoPrefetchSpeech` defaults to `false`; explicit Speak still fetches and plays audio.
- History is local, newest-first, and has no search, export, delete, sync or retention policy.
- Save Word is a bookmark (`isSaved`) on the current translation record, not a second data store.
- Audio is optional and is persisted only after an allowed prefetch or explicit Speak succeeds.
- Learning input is word mode only when trimmed text contains no whitespace after splitting on whitespace/newlines. Apostrophes and hyphens remain part of one word. Every multi-token input uses sentence/phrase mode.

## Architecture

### Input resolution

Replace string-only selection with `TranslatableInput`: `.text(String)` or `.image(Data)`. `SelectionReader` keeps Accessibility text as first priority. Its clipboard fallback checks raster image content before text, converts image bytes to PNG and rejects output over 10 MiB. Clipboard restoration remains mandatory for every `simulateCopy` outcome.

`PopoverController` stores image data separately and shows `[Image from clipboard]` as non-editable placeholder UI, never as `inputTextView.string`. It skips language detection and source TTS, disables source language/Learn/source Speak, and retries image translation through the normal generation guard. The first text edit clears image state and restores text controls.

### Translator payloads and learning prompts

`Translator` keeps one HTTP implementation and builds request payloads through testable pure helpers. Text messages retain current string content. Image translation uses the normal rendered translation system prompt and this user content order:

```json
[
  {
    "type": "text",
    "text": "Translate all readable text in this image into <target language>. Return only the translation."
  },
  {
    "type": "image_url",
    "image_url": {
      "url": "data:image/png;base64,<base64>"
    }
  }
]
```

No `detail` field is sent. Empty or schema-invalid model content is an error; it is not copied, spoken or persisted.

`AppConfig` adds `sentenceLearnPrompt` and `autoPrefetchSpeech`. Initializer, `default`, custom decoder, `config.json.example` and README stay synchronized. Missing keys decode to built-in defaults; explicit JSON values override them.

The built-in sentence prompt instructs the model to return, in the configured target language: natural full-sentence meaning, important grammar/structure, useful phrases in context, and one natural variation. `Translator` selects word or sentence/phrase prompt using the whitespace rule before replacing source/target placeholders. Translate and grammar modes remain unchanged.

### Speech

The shared `prefetchSpeech` entry point returns immediately when `autoPrefetchSpeech` is disabled. Explicit `playSpeech` remains a separate path. Reloading config invalidates in-flight prefetch requests so disabled prefetch cannot later attach audio.

One speech generation is separate from translation generation. Active identity contains kind, text, model and optional translation record ID. State transitions:

- idle: click fetches or plays cached data;
- loading: button is disabled;
- playing: same button pauses;
- paused: same button resumes at current time;
- clicking the other speech button stops the old player and starts the new identity;
- completion, decode error or panel close returns to idle.

Button symbol, tooltip and accessibility label reflect Play, Pause, Resume or loading. `AVAudioPlayerDelegate` resets state after completion/error. Stale completions cannot play or attach data to another record.

### History and Save Word

`TranslationRecord` stores ID, timestamp, source/result text, source/target language, optional relative source/result audio paths and `isSaved`. Only successful Translate responses are recorded; Learn remains outside history because issue #5 requests translation history.

`TranslationHistoryStore` uses `Codable`, `FileManager` and atomic writes:

- `~/Library/Application Support/NTranslate/history.json`
- `~/Library/Application Support/NTranslate/audio/<record-id>-<kind>.audio`

It serializes mutations and refuses to overwrite malformed history. A successful response means HTTP success plus non-empty trimmed content after the stale-generation guard. Empty input, image input, HTTP errors, invalid response JSON and stale responses create no record.

Audio is written atomically before history metadata. If metadata update fails, the new orphan file is removed. Store-generated relative paths are resolved only after standardization confirms they remain under the audio directory. Missing/corrupt audio reports playback failure but leaves the history record visible. History loads bytes into `AVAudioPlayer(data:)`; extension does not imply format.

Source prefetch that finishes before translation is held by translation generation and attached only after that generation creates its record. Explicit source/result speech attaches only when its identity contains that exact record ID.

`PopoverController` adds:

- Save Word button beside result Speak/Copy, enabled only for the current unchanged successful translation;
- bookmark/bookmark.fill state and matching accessibility label;
- status-menu item opening Translation History;
- invalidation of current record when input/language changes, another request starts, an error occurs or image mode begins.

Result remains read-only, so Save bookmarks the API snapshot. `HistoryWindowController` uses `NSWindowController` and `NSTableView`, showing newest-first time, source/result, language pair and saved state, with playback controls only when local audio exists.

Malformed history displays an error with the file path and disables append/bookmark/audio attachment for that store instance; it is never silently replaced.

## Error handling

- Invalid, empty or oversized normalized PNG shows a user-facing error and never creates a request.
- Unsupported vision models surface the existing HTTP error response.
- Empty/invalid model responses do not copy, prefetch speech or create history.
- Atomic writes preserve the previous history file on write failure.
- Missing new config keys always use backward-compatible defaults.
- Stale translation and speech completions cannot mutate newer state.

## Testing

Use Swift Testing and temporary directories. Add focused checks for:

- Both config defaults, old JSON missing keys and explicit overrides.
- Word/sentence prompt selection with whitespace, newline, apostrophe and hyphen cases.
- Clipboard text/image priority, image+text content, `simulateCopy` restoration, PNG normalization, exact/oversize limits and encode failure.
- Text versus multimodal payload shape, target instruction, fixed MIME and base64.
- Empty/invalid model output handling.
- History round-trip, newest-first append, bookmark persistence, relaunch, malformed-file lockout, atomic failure handling, relative audio paths and traversal rejection.
- Speech state transitions, pause/resume identity, disabled prefetch, reload invalidation and stale audio attachment.

Manual acceptance covers Carbon hotkey, Accessibility, a real clipboard screenshot, a vision-capable 9router model, TTS request counting, pause/resume current time, history access from the status menu, relaunch persistence and local audio playback with API unavailable.

## Integration order

1. Shared config fields and pure logic.
2. Image input and multimodal request.
3. Learning prompt routing.
4. TTS prefetch flag and pause/resume state.
5. History store, Save Word and history window.
6. Run tests and focused code review.
7. Run `./install-app.sh`; report installed version.

## Explicit exclusions

No new dependencies, database framework, cloud sync, image preview, image history, OCR engine, audio conversion, history search/export/delete, or provider abstraction. Add these only after a concrete requirement proves the native minimal design insufficient.
