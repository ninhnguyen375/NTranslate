# GitHub Issues #1–#6 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hoàn thành image translation, Save Word/history, configurable TTS prefetch, Play/Pause/Resume và sentence learning trong NTranslate.

**Architecture:** Dùng AppKit/Foundation/AVFoundation thuần. Logic mới nằm trong các helper/store nhỏ có thể test; `PopoverController` vẫn là owner điều phối UI và được tích hợp bởi một agent duy nhất sau khi các interface ổn định.

**Tech Stack:** Swift 6, SwiftPM, AppKit, AVFoundation, Foundation, Swift Testing.

## Global Constraints

- Không thêm dependency, DB framework, provider abstraction hoặc networking abstraction.
- Image chỉ nhận raster PNG/TIFF, chuẩn hóa PNG và giới hạn sau encode là 10 MiB.
- History chỉ lưu Translate text thành công; audio optional và local.
- Config cũ thiếu field mới phải decode được.
- Không commit; chỉ sửa, test và cài app.
- Không chạm thay đổi có sẵn trong `.serena/project.yml`.

## File Structure

- Modify `Sources/translate/AppConfig.swift`: `sentenceLearnPrompt`, `autoPrefetchSpeech`, defaults và compatibility.
- Modify `Sources/translate/SelectionReader.swift`: typed text/image clipboard input.
- Modify `Sources/translate/Translator.swift`: prompt routing, payload builders, strict response parser, image request.
- Create `Sources/translate/SpeechPlaybackState.swift`: pure playback state machine.
- Create `Sources/translate/TranslationHistoryStore.swift`: records, bookmarks, audio persistence.
- Create `Sources/translate/HistoryWindowController.swift`: local history UI/playback.
- Modify `Sources/translate/PopoverController.swift`: final UI/data-flow integration; one owner only.
- Modify `Tests/translateTests/translateTests.swift`: config, prompt, image, payload, speech checks.
- Create `Tests/translateTests/TranslationHistoryStoreTests.swift`: persistence/window checks.
- Modify `config.json.example` and `README.md`: document new behavior/config/privacy.

---

### Task 1: Shared Config and Sentence Learning

**Files:**
- Modify: `Sources/translate/AppConfig.swift`
- Modify: `Sources/translate/Translator.swift`
- Modify: `Tests/translateTests/translateTests.swift`
- Modify: `config.json.example`
- Modify: `README.md`

**Interfaces:**
- Produces: `AppConfig.sentenceLearnPrompt`, `AppConfig.autoPrefetchSpeech`, `AppConfig.defaultSentenceLearnPrompt`.
- Produces: `Translator.renderLearnPrompt(for:sourceLang:targetLang:config:) -> String`.

- [ ] **Step 1: Add failing config and prompt tests**

```swift
@Test func appConfigDefaultsIssueFields() {
    #expect(AppConfig.default.sentenceLearnPrompt == AppConfig.defaultSentenceLearnPrompt)
    #expect(!AppConfig.default.autoPrefetchSpeech)
}

@Test func learnPromptRoutesByWhitespace() {
    var config = AppConfig.default
    config.learnPrompt = "WORD {{config.sourceLang}} {{config.targetLang}}"
    config.sentenceLearnPrompt = "SENTENCE {{config.sourceLang}} {{config.targetLang}}"
    #expect(Translator.renderLearnPrompt(for: "can't", sourceLang: "English", targetLang: "Vietnamese", config: config) == "WORD English Vietnamese")
    #expect(Translator.renderLearnPrompt(for: "hello world", sourceLang: "English", targetLang: "Vietnamese", config: config) == "SENTENCE English Vietnamese")
}
```

- [ ] **Step 2: Run tests and confirm RED**

```bash
swift test --filter 'appConfigDefaultsIssueFields|learnPromptRoutesByWhitespace'
```

Expected: compile failure because fields/helper do not exist.

- [ ] **Step 3: Implement minimal config compatibility**

```swift
var sentenceLearnPrompt: String
var autoPrefetchSpeech: Bool

sentenceLearnPrompt = try container.decodeIfPresent(String.self, forKey: .sentenceLearnPrompt) ?? Self.defaultSentenceLearnPrompt
autoPrefetchSpeech = try container.decodeIfPresent(Bool.self, forKey: .autoPrefetchSpeech) ?? false
```

Add initializer/default values. `defaultSentenceLearnPrompt` requires natural full meaning, grammar/structure, useful phrases and one variation.

- [ ] **Step 4: Implement pure prompt router**

```swift
static func renderLearnPrompt(for text: String, sourceLang: String, targetLang: String, config: AppConfig) -> String {
    let template = text.split(whereSeparator: { $0.isWhitespace }).count == 1
        ? config.learnPrompt
        : config.sentenceLearnPrompt
    return template
        .replacingOccurrences(of: "{{config.sourceLang}}", with: sourceLang)
        .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
}
```

Use helper only for `.learn`; do not change Translate/Grammar.

- [ ] **Step 5: Synchronize example and README, then verify**

```bash
python3 -m json.tool config.json.example >/dev/null
swift test --filter 'appConfig|learnPrompt'
```

Expected: valid JSON and selected tests pass.

---

### Task 2: Clipboard Image and Multimodal Payload

**Files:**
- Modify: `Sources/translate/SelectionReader.swift`
- Modify: `Sources/translate/Translator.swift`
- Modify: `Tests/translateTests/translateTests.swift`

**Interfaces:**
- Produces: `TranslatableInput`, `TranslatableInputResolution`, `ImageInputError`.
- Produces: `SelectionReader.resolveTranslatableInputWithDiagnostics(simulateCopy:) throws`.
- Produces: `Translator.translateImage(_:targetLang:completion:)` and pure request/parser helpers.

- [ ] **Step 1: Add failing input/payload/parser tests**

Tests cover image+text priority, trimmed text fallback, PNG signature, exact/oversize limit, encode failure, simulated-copy restoration, text payload string content, image payload content order/data URL, valid response trim, empty/invalid response rejection.

```swift
#expect(imageURL == "data:image/png;base64,AP8=")
#expect(instruction == "Translate all readable text in this image into Vietnamese. Return only the translation.")
```

- [ ] **Step 2: Run tests and confirm RED**

```bash
swift test --filter 'clipboard|normalizedPNG|translatorImage|translatorResponse'
```

Expected: missing typed input/payload helpers.

- [ ] **Step 3: Implement raster normalization and clipboard restoration**

```swift
enum TranslatableInput: Equatable, Sendable { case text(String); case image(Data) }
static let maximumImageBytes = 10 * 1024 * 1024
```

Read only `.png`/`.tiff`, normalize with `NSBitmapImageRep`, reject empty/oversize output. Accessibility text wins globally; raster wins over text in clipboard fallback. Restore original pasteboard with `defer` for every simulated-copy parse outcome.

- [ ] **Step 4: Implement one Translator HTTP path and strict parser**

```swift
func translateImage(_ pngData: Data, targetLang: String, completion: @escaping @Sendable (Result<String, Error>) -> Void)
static func responseContent(from data: Data) throws -> String
```

Text retains string user content. Image uses text part then `image_url`, fixed `image/png`, no `detail`. Invalid schema and trimmed-empty content fail.

- [ ] **Step 5: Verify image core**

```bash
swift test --filter 'clipboard|normalizedPNG|translatorTextPayload|translatorImagePayload|translatorResponseContent'
swift build
```

Expected: selected tests and build pass.

---

### Task 3: Speech State and TTS Prefetch Policy

**Files:**
- Create: `Sources/translate/SpeechPlaybackState.swift`
- Modify: `Tests/translateTests/translateTests.swift`

**Interfaces:**
- Consumes: `AppConfig.autoPrefetchSpeech` during final integration.
- Produces: `SpeechKind`, `SpeechIdentity`, `SpeechButtonAction`, `SpeechPlaybackState`.

- [ ] **Step 1: Add failing state-machine test**

```swift
let generation = state.beginLoading(source)
#expect(state.action(for: source) == .loading)
#expect(state.markPlaying(generation: generation, identity: source))
#expect(state.pause(source))
#expect(state.resume(source))
state.invalidateRequests()
#expect(!state.markPlaying(generation: generation, identity: source))
```

- [ ] **Step 2: Run test and confirm RED**

```bash
swift test --filter speechPlaybackState
```

Expected: helper types missing.

- [ ] **Step 3: Implement minimal pure state machine**

State has `.idle`, `.loading`, `.playing`, `.paused`; identity contains kind/text/model/optional record ID; independent generation rejects stale completion. Expose `beginLoading`, `beginPlaying`, `accepts`, `markPlaying`, `finishLoading`, `pause`, `resume`, `invalidateRequests`, `reset`, `action(for:)`.

- [ ] **Step 4: Verify state helper**

```bash
swift test --filter speechPlaybackState
```

Expected: pass.

---

### Task 4: Translation History Store and Window

**Files:**
- Create: `Sources/translate/TranslationHistoryStore.swift`
- Create: `Sources/translate/HistoryWindowController.swift`
- Create: `Tests/translateTests/TranslationHistoryStoreTests.swift`

**Interfaces:**
- Produces: `TranslationRecord`, `TranslationAudioKind`, `TranslationHistoryStore`, `HistoryWindowController`.

- [ ] **Step 1: Add failing persistence tests**

Tests cover newest-first round-trip, bookmark persistence after reload, empty record rejection, malformed-file lockout without overwrite, relative audio paths, missing audio, traversal rejection, audio rollback after metadata write failure.

- [ ] **Step 2: Run tests and confirm RED**

```bash
swift test --filter TranslationHistoryStoreTests
```

Expected: store types missing.

- [ ] **Step 3: Implement record/store with atomic writes**

```swift
struct TranslationRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let sourceText: String
    let resultText: String
    let sourceLanguage: String
    let targetLanguage: String
    var sourceAudioPath: String?
    var resultAudioPath: String?
    var isSaved: Bool
}
```

Use `@MainActor` store, `Codable`, ISO-8601 dates and atomic writes. Mutate memory only after successful history write. Audio write precedes metadata; remove orphan on metadata failure. Standardized/resolved path must remain below audio root.

- [ ] **Step 4: Verify store GREEN**

```bash
swift test --filter TranslationHistoryStoreTests
```

Expected: all store tests pass.

- [ ] **Step 5: Add failing history-window smoke test**

```swift
@MainActor @Test func windowLoadsHistory() throws {
    let controller = HistoryWindowController(store: store)
    controller.reloadHistory()
    #expect(controller.window?.title == "Translation History")
    #expect(controller.numberOfRows(in: NSTableView()) == 1)
}
```

- [ ] **Step 6: Implement native history window and verify**

Use one view-based `NSTableView` composite row showing timestamp, language pair, source/result, bookmark state and available local audio buttons. `showHistory()` reloads then activates. Audio playback reads store bytes only.

```bash
swift test --filter 'TranslationHistoryStoreTests|HistoryWindowControllerTests'
swift build
```

Expected: pass.

---

### Task 5: Final Popover Integration

**Files:**
- Modify: `Sources/translate/PopoverController.swift`
- Modify: `Tests/translateTests/translateTests.swift`
- Modify: `README.md`

**Interfaces:**
- Consumes all interfaces from Tasks 1–4.
- Produces complete user-visible behavior for issues #1–#5.

- [ ] **Step 1: Integrate typed image state**

Add `pendingImage: Data?`. `translateAtCursor()` consumes typed resolution. Keep image bytes outside `inputTextView.string`; show non-editable placeholder. Image mode disables source language/Learn/source Speak, skips language detection/source prefetch, uses selected target and `translateImage`. First text edit clears image mode. Result Speak remains available. Errors and stale generation use existing feedback flow. Never append image history.

- [ ] **Step 2: Integrate speech state and AVAudioPlayerDelegate**

Remove old loading booleans. `prefetchSpeech` guards `config.autoPrefetchSpeech`; explicit Speak does not. Same button toggles pause/resume on same player. Other button stops old identity. Symbols/tooltip/accessibility labels reflect loading/play/pause/resume. Reload invalidates pending prefetch. Close resets state. Never use translation generation as speech generation.

- [ ] **Step 3: Integrate successful text history**

Own one `TranslationHistoryStore`, `HistoryWindowController` and `currentRecordID`. Append only non-empty successful text Translate after stale guard. Invalidate record identity on input/language/new request/error/image. Attach audio only using exact speech identity record ID; hold source prefetch by translation generation until record exists.

- [ ] **Step 4: Add Save Word and History UI entry points**

Place bookmark button beside result Speak/Copy, enabled only for unchanged successful record. Toggle `isSaved` without creating records. Add status-menu `Translation History`. Refresh window after append/bookmark/audio. Report malformed store path and disable mutations.

- [ ] **Step 5: Add integration checks and documentation**

Add pure checks for image control state/record eligibility if extracted. README documents image privacy/model requirement, local history paths, Save Word, `autoPrefetchSpeech`, Play/Pause/Resume and sentence prompt.

- [ ] **Step 6: Verify integrated app**

```bash
swift test
swift build -c release
git diff --check
```

Expected: zero test failures, release build succeeds, no whitespace errors.

---

### Task 6: Review, Fix and Install

**Files:**
- Review all changed files.
- Modify only changed code where verified review findings require fixes.

- [ ] **Step 1: Run focused code review**

Review correctness, persistence safety, stale async state, accessibility, backward compatibility and scope. Verify each finding against source before editing.

- [ ] **Step 2: Apply confirmed fixes and rerun verification**

```bash
swift test
swift build -c release
git diff --check
git status --short
```

Expected: all pass; `.serena/project.yml` remains untouched.

- [ ] **Step 3: Build, sign and install required app**

```bash
./install-app.sh
```

Expected: signed `/Applications/NTranslate.app`; capture exact version/build from output.

- [ ] **Step 4: Report completion**

Report issues completed, tests/build/install results, version/build, changed files and any manual-only acceptance still requiring a real vision/TTS endpoint. Do not commit or push.
