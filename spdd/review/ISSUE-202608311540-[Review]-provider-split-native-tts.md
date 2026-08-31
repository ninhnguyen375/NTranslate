# SPDD Code Review: Provider split (LLM/TTS) + native macOS TTS

## Review Context

- **Contract**: `spdd/analysis/ISSUE-202608311314-[Analysis]-provider-split-native-tts-llm.md` (analysis doc used in place of a REASONS Canvas; canvas phase deliberately skipped)
- **Code Scope**: `NativeSpeechEngine.swift` (new, untracked), `SpeechModelResolver.swift`, `Translator.swift`, `APIKeyStore.swift`, `AppConfig.swift`, `PopoverController+Speech.swift`, `+Actions.swift`, `+Subtranslate.swift`, `+Menu.swift`, `SettingsWindowController.swift`, `TranslationHistoryStore.swift`, `PopoverController.swift` (`speechAPIKey` only)
- **Verification**: `swift build` → success. `swift test` not run (toolchain lacks swift-testing), so there is no automated safety net.
- **Review Date**: 2026-08-31

## Review Summary

| Dimension | Status | Findings | Priority |
| --- | --- | --- | --- |
| Requirements (AC1-AC4) | ⚠️ Partial | 2 | Medium |
| Entities | ✅ Aligned | 0 | - |
| Approach | ⚠️ Partial | 1 | Medium |
| Structure | ✅ Aligned | 0 | - |
| Operations | ⚠️ Partial | 3 | High |
| Norms | ✅ Aligned | 1 | Low |
| Safeguards (Key Business Rules) | ❌ Violations | 3 | High |
| Intent Drift | ⚠️ Partial | 2 | Medium |
| Scope Boundary | ✅ Within scope | 0 | - |

**Overall Assessment**: ⚠️ Needs Attention — one hang path and one crash path in the new native engine, plus a silent network fallback that contradicts a stated business rule.

---

## 🔴 Must Review (Critical)

### F1. `synthesize` can never call `completion` — permanent "Loading" state
`Sources/translate/NativeSpeechEngine.swift:76-84` (+ `WriterBox.accept`, `:98-125`)

**Verified by reading code.** `completion` fires only from `WriterBox.finish()`, which is only reachable from `accept()`, which is only reachable from the `write` buffer callback. If AVFoundation never delivers a buffer, completion never fires. The contract itself lists this exact case: *"Voice từ chối `write()`: một số voice (personal voice, một phần voice Siri) không cho phép ghi ra buffer. Đã gặp trong lúc benchmark."* (Edge Cases).

Failure scenario: user picks a target language whose best installed voice is a personal/Siri voice → `AVSpeechSynthesisVoice(identifier:)` succeeds so the `noVoice` guard passes → `write` yields nothing → `loadAndPlaySpeech` (`PopoverController+Speech.swift:207-236`) stays in `speechState.beginLoading`, the speak button stays disabled showing "Loading", and `prefetchingSpeech` (for the prefetch path, `:141-159`) never clears that identity. Only a settings change or retry (which bumps `prefetchGeneration`) recovers it. No error is ever shown.

Suggested fix: arm a watchdog in `synthesize` (e.g. `DispatchQueue.global().asyncAfter(deadline: .now() + 10)` calling `box.failIfUnfinished()`), which `WriterBox` already can serve exactly-once via its `finished` flag under the existing lock.

### F2. `AVAudioFile.write(from:)` format mismatch raises an ObjC exception, not a Swift error
`Sources/translate/NativeSpeechEngine.swift:110-124`

**Partly verified / partly suspicion.** Verified: the code wraps `try file?.write(from: pcm)` in `do/catch`. Suspicion (not runtime-verified): `AVAudioFile.write(from:)` throws `NSInvalidArgumentException` — an Objective-C exception — when the buffer's format does not match the file's `processingFormat`, and Swift `catch` cannot intercept that; it terminates the app. The settings dictionary is built from the *first* buffer's `sampleRate`/`channelCount`, so a voice that changes format mid-utterance, or a processing format that differs from the buffer's (interleaving/common-format), crashes rather than failing gracefully.

Suggested fix: capture `file.processingFormat` after creation and skip/convert (`AVAudioConverter`) any buffer whose `format` is not equal, rather than relying on `do/catch`.

### F3. Native provider silently falls back to the network, breaking the offline rule
`Sources/translate/SpeechModelResolver.swift:5-12`

**Verified by reading code.** With `speechProvider == .native` and no installed voice for a language, `model(for:)` returns the *API* model string, so `Translator.speak` posts to `apiSpeechURL`. This contradicts two stated Key Business Rules: *"Ngôn ngữ nào không có voice native thì phải nói rõ, không im lặng phát sai giọng"* and *"Provider native phải hoạt động không cần mạng"*.

It also compounds with the Settings change: when `native` is selected, `updateSpeechProviderRows` (`SettingsWindowController.swift:591-596`) hides Speech URL, Speech API Key, per-language models and Fallback Model, and `AppConfig.validationIssues()` (`AppConfig.swift:507-511`) stops validating the speech URL. So the fallback fires against a URL the user can no longer see or validate. Worst case: 9router is down (the entire motivation for native per the analysis), user switches to native, an unsupported language silently tries the dead endpoint and fails with a network error that names no cause.

Suggested fix: under `.native`, return `nil`/throw and surface `EngineError.noVoice` with the language name, instead of falling through to `apiModel`. If a fallback is wanted, make it explicit and only when the user has not hidden the API config.

---

## 🟡 Should Review (Important)

### F4. Speech API key change does not invalidate the audio cache
`Sources/translate/PopoverController+Menu.swift:284-295`

**Verified.** `speechChanged` compares `speechProvider`, `apiSpeechURL`, `speechModels`, `speechFallbackModel` — but not the speech API key. Scenario: user keeps the same URL and model but swaps the speech key to a different tenant/vendor that maps the same model name to a different voice. Cache is not cleared, so the current record keeps playing the old voice until an explicit retry. Cheap fix: include `newSpeechKey != originalSpeechKey` in the comparison (the previous value is already loadable via `APIKeyStore.speech.load()` before the save, alongside `previousKey`).

### F5. `setupIssues()` still validates the speech URL under the native provider
`Sources/translate/AppConfig.swift:580-586`

**Verified.** `validationIssues()` was made provider-aware; `setupIssues()` was not. A native-provider user with a blank or malformed `apiSpeechURL` gets a persistent "Speech URL must be a valid http:// or https:// URL" setup issue with an "open Settings" action pointing at a field that is hidden. This is the *unsaveable/unfixable state* the parent asked about — Save is not blocked, but the setup banner cannot be cleared through the UI. Mirror the `if speechProvider == .api` guard here.

### F6. `EngineError.noVoice` interpolates a model string into a language-shaped message
`Sources/translate/NativeSpeechEngine.swift:17-19, 71-74`

**Verified.** The message reads "macOS has no installed voice for \(language)" but the value passed at `:73` is `model` — e.g. `native/com.apple.voice.compact.vi-VN.Linh`, or the whole raw model string when the prefix is missing. User-facing text is English and emoji-free (project rule OK), but the content is wrong. Pass the language name down, or reword to name the voice identifier.

### F7. `completion` is invoked while `WriterBox`'s lock is held, on AVFoundation's queue
`Sources/translate/NativeSpeechEngine.swift:105-107` → `finish()` at `:127`

**Verified.** `accept` takes `lock` with `defer { lock.unlock() }` and calls `finish()` inside, which calls `completion`. Callers do real work synchronously in that callback — `loadAndPlaySpeech` (`PopoverController+Speech.swift:213`) and `prefetchSpeech` (`:146`) both run `SpeechTrim.bounds(of:)`, a full decode, before hopping to the main actor. That decode now runs on AVFoundation's speech queue holding a lock. No deadlock found (nothing re-enters `accept` after `finished`), but it blocks the synthesis queue for the duration. Fix: snapshot the result, unlock, then call completion outside the critical section.

### F8. Possible retain cycle: synthesizer → write closure → WriterBox → synthesizer
`Sources/translate/NativeSpeechEngine.swift:80-84, 88-91`

**Suspicion, not verified.** `WriterBox` holds `synthesizer` strongly (correct — it must outlive the write, and the requirement the parent asked about is satisfied), and the `write` closure captures `box` strongly. If AVFoundation retains the buffer callback for the synthesizer's lifetime rather than releasing it at end-of-utterance, each synthesis leaks one `AVSpeechSynthesizer` + `WriterBox`. Worth one instrumented run; a `deinit` print or Instruments allocation check settles it. If confirmed, break the cycle in `finish()` by nilling a `var synthesizer: AVSpeechSynthesizer?` (the current `_ = synthesizer` line at `:133` does nothing).

---

## 🟢 Informational

- **F9. `clearAudioCache` closes the stale-audio paths asked about — verified.** `PopoverController+Speech.swift:311-327` clears `speechCache`/`speechTrim` for the record *and* every nil-recordID orphan (so `adoptCachedSpeech` at `:120-127` cannot resurrect one), calls `invalidateSpeech(stopPlayback: true)` first so `prefetchGeneration` bumps and in-flight prefetches are dropped by the generation guard at `:153`, clears `pendingSourceSpeech`, and removes on-disk audio so `hydrateStoredAudio` (`:106-118`) has nothing to reload. I found no remaining path back to stale audio for the cleared record. Other records intentionally keep their audio, matching D3.
- **F10. D2 key inheritance holds — verified.** `Translator.effectiveSpeechKey` (`Translator.swift:60-63`) resolves at call time within a `Translator` instance, and `reloadConfig` rebuilds the `Translator` with both freshly-loaded Keychain values after every save (`PopoverController+Menu.swift:396, 421`). Changing the LLM key while the speech key is blank therefore propagates. The one residual: a long-lived `Translator` captured elsewhere would hold a stale copy — none found in scope.
- **F11. D1 respected.** No Apple Intelligence / FoundationModels code anywhere in the diff. Correct per the locked decision; not flagged as a gap.
- **F12. AAC encoding respects the history-size rule.** Native audio is encoded before it reaches `attachAudio`, so the ~38x PCM blowup the analysis warned about does not occur.
- **F13. `native/` prefix instead of a `SpeechIdentity` field.** Reasonable trade: it avoids the "widest-blast-radius change" the analysis flagged (`SpeechIdentity` is a dict key across 7+ functions), and still distinguishes providers in cache keys since `edge-tts/...` and `native/...` never collide. Implicit decision worth a nod, not a defect.
- **F14. `speed` is ignored by `NativeSpeechEngine`.** Consistent with the API path — callers always pass `speed: 1.0` and apply rate at `AVAudioPlayer`. No issue.
- **F15. Provider is stored/read by `displayName` string round-trip** (`SettingsWindowController.swift:591, 619-621`) rather than by `rawValue` on the popup item. It works because display names are unique, but it couples UI copy to persistence; `representedObject` or `indexOfSelectedItem` would be sturdier.

---

## Intent Drift Analysis

### Positive drift (additions beyond the contract)
| ID | Severity | Location | Description |
| --- | --- | --- | --- |
| D-P1 | 🟡 | `SpeechModelResolver.swift:5-12` | Silent native→API fallback was not a locked decision; the analysis recommended native as a fallback *for API failure*, not the reverse. See F3. |
| D-P2 | 🟢 | `NativeSpeechEngine.swift:33-49` | Voice selection heuristic (quality, then `Locale.preferredLanguages`, then language tag) resolves an ambiguity the analysis explicitly left open ("tự chọn theo ngôn ngữ" was the recommendation). Matches the recommendation; the tie-break rationale for cache-key stability is sound. |

### Negative drift (contract items not implemented)
| ID | Severity | Location | Description |
| --- | --- | --- | --- |
| D-N1 | 🟡 | Analysis "Key Design Decisions" | Native as an automatic fallback when the **API** provider errors was recommended ("khuyến nghị làm cả hai"). Not implemented. Acceptable as scope trimming, but it is the half that would have covered the 9router-is-down scenario. |
| D-N2 | 🟡 | Analysis "Edge Cases" | "Ngôn ngữ không có voice native thì phải nói rõ" is not honored — see F3. |

### Direction drift
| ID | Severity | Location | Description |
| --- | --- | --- | --- |
| D-D1 | 🟢 | `NativeSpeechEngine.modelPrefix` | Expected: provider carried in `SpeechIdentity`. Actual: encoded in the `model` string. Behaviorally equivalent for cache-key separation, far smaller diff. Endorsed; see F13. |

---

## Implicit Decisions (need human validation)

| Decision | Category | Location | AI's choice | Risk |
| --- | --- | --- | --- | --- |
| AAC bitrate | Config | `NativeSpeechEngine.swift:117` | Hard-coded 48 kbps | Low |
| Temp file in `temporaryDirectory`, deleted after read | Data | `:76-78, 129-131` | Fine; leaks the file if the process dies mid-write | Low |
| Zero-length buffer treated as end-of-utterance | Algorithm | `:104` | Matches documented AVFoundation behavior | Low |
| No cancellation handle for native synthesis | Concurrency | `Translator.swift:675-679` | Relies on caller generation guards | Medium — combined with F1, an unfinished synthesis is unobservable and uncancellable |
| Speech URL/model rows hidden (not disabled) under native | UX | `SettingsWindowController.swift:591-596` | Hidden | Medium — see F5 |
| Cache-clear trigger set | Algorithm | `PopoverController+Menu.swift:286-290` | Provider/URL/models/fallback, excludes speech key | Medium — see F4 |

## Scope Boundary Check

**Status**: ✅ Within scope. Every reviewed change traces to AC1-AC3. `PopoverController.swift` contributes only the `speechAPIKey` property within scope (the `languageWidth` change belongs to the excluded pre-existing work). No shared utility or base class was refactored beyond what the split required; `APIKeyStore` gained one static and no behavior change, satisfying D2's "no migration" requirement.

## Recommended Actions

1. Fix F1 (watchdog / guaranteed single completion) — this is the only finding that can wedge the UI with no recovery path.
2. Fix F2 (validate buffer format against `processingFormat`) — ObjC exceptions are not catchable and would crash the app.
3. Decide F3: either surface `noVoice` under the native provider, or keep the fallback and stop hiding the API rows. The current combination is the worst of both.
4. Cheap follow-ups: F4 (include speech key in `speechChanged`), F5 (`setupIssues` provider guard), F6 (message interpolation), F7 (unlock before completion).
5. Confirm or dismiss F8 with one instrumented run.
6. Since `swift test` cannot run, F1/F2/F3 deserve manual exercise: a language with no installed voice, a personal/Siri voice, and a native run with the speech URL blanked.
