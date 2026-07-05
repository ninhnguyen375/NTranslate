# NTranslate Stability & UI/UX Hardening — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the concrete stability bugs and UI glitches found in a full review of NTranslate's source (duplicate hotkey firing, popover flicker/focus loss on every keystroke, popup that won't dismiss on outside click, a force-unwrap, a fragile 3-flag focus state machine, and silent config-parse failures), and add the minimum regression-test safety net needed to make the biggest refactor (Task 4) safe.

**Architecture:** No architectural rewrite. NTranslate stays a single-target AppKit menu-bar app (`PopoverController` as the `NSApplicationDelegate`). This plan extracts pure, testable logic (language detection, hotkey key-code mapping, popover layout math) into small new files so it can be unit-tested with Swift Testing, then fixes bugs in `PopoverController.swift` in an order chosen so each fix's prerequisites already exist (see "Why execution order differs from severity order" below).

**Tech Stack:** Swift 6.3, AppKit, Carbon.HIToolbox (global hotkey), AVFoundation (audio playback), Swift Testing (`import Testing`, not XCTest), SwiftPM (`swift build` / `swift test`).

## Global Constraints

- Swift tools version 6.3, deployment target macOS 13 (`Package.swift` — do not change).
- Build: `swift build -c release`. Install: `./install-app.sh` (rebuilds, re-codesigns with the existing `Apple Development` identity, copies to `/Applications/NTranslate.app`, relaunches). Do not modify `install-app.sh` in this plan — no packaging details change.
- Tests use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `Issue.record`), matching `Tests/translateTests/translateTests.swift` — do not introduce XCTest.
- This is a single-user, single-machine personal utility, not a distributed app. Do **not** add notarization, sandboxing, app-distribution tooling, or config-migration/versioning infrastructure — out of scope and not requested.
- Do **not** relocate `AppConfig.configPath` away from `~/Code/MacOS/translate/config.json`. The README documents editing that exact path + "Reload Config" as the intended live-reload workflow; moving it would silently break that documented workflow for no requested benefit.
- Preserve the existing one-responsibility-per-file convention (`AppConfig`, `APIKeychain`, `SelectionReader`, `Translator`, `PopoverController`, `main`). New pure-logic types get their own new files under `Sources/translate/`.
- No comments except where a genuinely non-obvious constraint needs explaining (matches the codebase's existing near-comment-free style).
- Every task must leave the repo building clean (`swift build`) and all tests passing (`swift test`) before its commit.
- Because most of the app is AppKit UI with no existing UI test harness, every task that touches `PopoverController.swift` includes a **Manual QA** step run via `swift build -c release && .build/release/translate` (do not require `./install-app.sh` for every iteration — that's for shipping to `/Applications`, use it only after the final task).

## Why execution order differs from the severity table

Reviewing `PopoverController.swift`, the 3-boolean focus-restore state machine (`shouldRestorePreviousAppFocus` / `shouldActivateAppForSelectionFlow` / `shouldRestoreFocusOnDismiss`) has a defensive double-gate that only makes sense as a guard against a *spurious* `popoverDidClose` notification firing while `rebuildPopoverLayout()` swaps `popover.contentViewController` out from under a **currently shown** popover (this happens on every keystroke today). Task 4 removes that content-view-controller swap entirely (it becomes an in-place frame update). Simplifying the focus state machine (Task 5) is safe and correct only *after* Task 4 removes the hazard it was guarding against — so Task 4 is scheduled before Task 5 even though Task 5 also fixes higher-severity items (dead click-outside code, force-unwrap). This is called out explicitly so a future reader doesn't wonder why the "simplify state" task isn't first.

## Priority / Severity Table

| # | Severity | Issue | Files | Fixed in |
|---|---|---|---|---|
| 1 | **Critical** | Global hotkey C-callback (`InstallEventHandler`) is re-installed on every `reloadConfig()` without ever calling `RemoveEventHandler` — after N reloads, one hotkey press fires `translateAtCursor()` N times. | `PopoverController.swift:563-583` | Task 3 |
| 2 | **Critical** | `rebuildPopoverLayout()` tears down and rebuilds the *entire* view hierarchy and reassigns `popover.contentViewController` on every single keystroke (`textDidChange`) — this is the most likely cause of the "unstable UI / lỗi vặt" symptom (flicker, wasted allocations, risk to input-method marked-text composition when `.string` is reassigned on the input view). | `PopoverController.swift:104-268, 377-384` | Task 4 |
| 3 | **High** | `globalMouseMonitor` is declared but never assigned or used — clicking outside the popover does **not** dismiss it (popover behavior is `.applicationDefined`, so AppKit won't auto-close it either). Users can only close via Escape or re-clicking the status icon. | `PopoverController.swift:48, 250` | Task 5 |
| 4 | **High** | 3-boolean tri-state focus/dismiss state machine (`shouldRestorePreviousAppFocus`, `shouldActivateAppForSelectionFlow`, `shouldRestoreFocusOnDismiss`) spread across 7 call sites — easy to leave in an inconsistent state, causing inconsistent focus-restore behavior. | `PopoverController.swift:50-52` + call sites | Task 5 |
| 5 | **Medium** | Force-unwrap `anchorWindow.contentView!` (×2) in the hotkey-triggered show path. Currently always safe, but a crash risk if that invariant is ever broken by future edits. | `PopoverController.swift:675` | Task 5 |
| 6 | **Medium** | `AppConfig.load()` silently falls back to `.default` on a JSON decode failure — if the user hand-edits `config.json` and makes a syntax error, nothing tells them their edit had no effect. | `AppConfig.swift:48-53` | Task 2 |
| 7 | **Medium** | No regression tests exist for the pure logic most likely to break during refactors: language auto-detection (`resolvedLanguagePair`), hotkey key-code fallback (`hotKeyCode`), and popover layout math (`inputHeight`/`measuredTextHeight`). | `PopoverController.swift:270-356, 522-552` | Tasks 1 & 4 |
| 8 | **Low** | `pasteResultToPreviousApp()` waits on two chained fixed `DispatchQueue.main.asyncAfter` delays (0.15s + 0.1s) for the target app to activate before simulating ⌘V — a timing race on a loaded machine. Documented as a known risk; fix is optional/stretch (Task 6). | `PopoverController.swift:791-806` | Task 6 (optional) |

## Recommended Execution Order

1. Task 1 — Extract & test pure logic: language detection + hotkey key-code mapping (foundation, no behavior change)
2. Task 2 — Surface `AppConfig` parse/load failures instead of failing silently
3. Task 3 — Fix the hotkey event-handler leak (duplicate-trigger bug)
4. Task 4 — Extract & test popover layout math, then stop rebuilding the whole view tree on every keystroke
5. Task 5 — Consolidate the focus/dismiss state machine, wire up click-outside-to-dismiss, remove the force-unwrap
6. Task 6 (optional/stretch) — Replace the fixed-delay paste-activation wait with a notification-based wait

---

### Task 1: Extract & test language detection and hotkey key-code mapping

**Files:**
- Create: `Sources/translate/LanguageDetector.swift`
- Create: `Sources/translate/HotkeyKeyCode.swift`
- Modify: `Sources/translate/PopoverController.swift:53, 331-337, 339-356, 358-375, 491-500, 522-552, 567`
- Test: `Tests/translateTests/translateTests.swift`

**Interfaces:**
- Produces: `enum LanguageDetector` with `static let supportedLanguages: [String]`, `static func normalizeSource(_ value: String) -> String`, `static func normalizeTarget(_ value: String) -> String`, `static func looksVietnamese(_ text: String) -> Bool`, `static func looksChinese(_ text: String) -> Bool`, `static func resolvedPair(selectedSource: String, selectedTarget: String, text: String) -> (source: String, target: String)`.
- Produces: `enum HotkeyKeyCode` with `static func code(for key: String) -> UInt32`.
- Consumes (from `PopoverController`, unchanged by this task): `selectedSourceLanguage()`, `selectedTargetLanguage()`, `config.hotkey.key`.

- [ ] **Step 1: Write the failing tests for `LanguageDetector` and `HotkeyKeyCode`**

Append to `Tests/translateTests/translateTests.swift`:

```swift
import AppKit
import Testing
@testable import translate

struct TranslateTests {
    @Test func plainDisplayPreservesReadableText() {
        let rendered = NSAttributedString.plainDisplay("**Bold** and *italic*", font: .systemFont(ofSize: 13))
        #expect(rendered.string == "**Bold** and *italic*")
    }

    @Test func hotkeyCodeFallsBackToDForUnknownKey() {
        #expect(HotkeyKeyCode.code(for: "1") == HotkeyKeyCode.code(for: "D"))
    }

    @Test func hotkeyCodeIsCaseInsensitive() {
        #expect(HotkeyKeyCode.code(for: "a") == HotkeyKeyCode.code(for: "A"))
    }

    @Test func languageDetectorNormalizesUnknownSourceToAutoDetect() {
        #expect(LanguageDetector.normalizeSource("French") == "Auto detect")
    }

    @Test func languageDetectorNormalizesUnknownOrAutoTargetToVietnamese() {
        #expect(LanguageDetector.normalizeTarget("French") == "Vietnamese")
        #expect(LanguageDetector.normalizeTarget("Auto detect") == "Vietnamese")
    }

    @Test func languageDetectorSwapsToEnglishWhenSourceIsVietnamese() {
        let pair = LanguageDetector.resolvedPair(selectedSource: "Vietnamese", selectedTarget: "Vietnamese", text: "xin chào")
        #expect(pair.source == "Vietnamese")
        #expect(pair.target == "English")
    }

    @Test func languageDetectorAutoDetectsVietnameseTextAndTargetsEnglish() {
        let pair = LanguageDetector.resolvedPair(selectedSource: "Auto detect", selectedTarget: "Vietnamese", text: "xin chào các bạn")
        #expect(pair.target == "English")
    }

    @Test func languageDetectorFallsBackWhenSourceEqualsTarget() {
        let pair = LanguageDetector.resolvedPair(selectedSource: "English", selectedTarget: "English", text: "hello")
        #expect(pair.target == "Vietnamese")
    }

    @Test func languageDetectorRecognizesChineseText() {
        #expect(LanguageDetector.looksChinese("你好") == true)
        #expect(LanguageDetector.looksChinese("hello") == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail to compile (types don't exist yet)**

Run: `swift test --filter TranslateTests 2>&1 | tail -30`
Expected: FAIL — `cannot find 'HotkeyKeyCode' in scope` / `cannot find 'LanguageDetector' in scope`

- [ ] **Step 3: Create `Sources/translate/HotkeyKeyCode.swift`**

```swift
import Carbon.HIToolbox

enum HotkeyKeyCode {
    static func code(for key: String) -> UInt32 {
        switch key.uppercased() {
        case "A": return UInt32(kVK_ANSI_A)
        case "B": return UInt32(kVK_ANSI_B)
        case "C": return UInt32(kVK_ANSI_C)
        case "D": return UInt32(kVK_ANSI_D)
        case "E": return UInt32(kVK_ANSI_E)
        case "F": return UInt32(kVK_ANSI_F)
        case "G": return UInt32(kVK_ANSI_G)
        case "H": return UInt32(kVK_ANSI_H)
        case "I": return UInt32(kVK_ANSI_I)
        case "J": return UInt32(kVK_ANSI_J)
        case "K": return UInt32(kVK_ANSI_K)
        case "L": return UInt32(kVK_ANSI_L)
        case "M": return UInt32(kVK_ANSI_M)
        case "N": return UInt32(kVK_ANSI_N)
        case "O": return UInt32(kVK_ANSI_O)
        case "P": return UInt32(kVK_ANSI_P)
        case "Q": return UInt32(kVK_ANSI_Q)
        case "R": return UInt32(kVK_ANSI_R)
        case "S": return UInt32(kVK_ANSI_S)
        case "T": return UInt32(kVK_ANSI_T)
        case "U": return UInt32(kVK_ANSI_U)
        case "V": return UInt32(kVK_ANSI_V)
        case "W": return UInt32(kVK_ANSI_W)
        case "X": return UInt32(kVK_ANSI_X)
        case "Y": return UInt32(kVK_ANSI_Y)
        case "Z": return UInt32(kVK_ANSI_Z)
        default: return UInt32(kVK_ANSI_D)
        }
    }
}
```

- [ ] **Step 4: Create `Sources/translate/LanguageDetector.swift`**

```swift
import Foundation

enum LanguageDetector {
    static let supportedLanguages = ["Auto detect", "English", "Vietnamese", "Chinese"]

    static func normalizeSource(_ value: String) -> String {
        supportedLanguages.contains(value) ? value : "Auto detect"
    }

    static func normalizeTarget(_ value: String) -> String {
        supportedLanguages.contains(value) && value != "Auto detect" ? value : "Vietnamese"
    }

    static func looksVietnamese(_ text: String) -> Bool {
        let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        return sample.contains(where: { $0.value >= 0x0102 && $0.value <= 0x1EF9 }) || text.localizedCaseInsensitiveContains("đ")
    }

    static func looksChinese(_ text: String) -> Bool {
        let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        return sample.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF })
    }

    static func resolvedPair(selectedSource: String, selectedTarget: String, text: String) -> (source: String, target: String) {
        let source = normalizeSource(selectedSource)
        var target = normalizeTarget(selectedTarget)
        if source == "Vietnamese" {
            target = "English"
        }
        if source == target {
            target = source == "English" ? "Vietnamese" : "English"
        }
        if source == "Auto detect", looksVietnamese(text) {
            target = "English"
        }
        return (source, target)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter TranslateTests 2>&1 | tail -30`
Expected: PASS — all `TranslateTests` tests green, including the two new files' tests.

- [ ] **Step 6: Wire `PopoverController` to the extracted types (delete the duplicated logic)**

In `Sources/translate/PopoverController.swift`, delete the stored property (originally line 53):

```swift
private let supportedLanguages = ["Auto detect", "English", "Vietnamese", "Chinese"]
```

Replace the three methods (originally lines 331-356):

```swift
    private func normalizeSourceLanguage(_ value: String) -> String {
        supportedLanguages.contains(value) ? value : "Auto detect"
    }

    private func normalizeTargetLanguage(_ value: String) -> String {
        supportedLanguages.contains(value) && value != "Auto detect" ? value : "Vietnamese"
    }

    private func resolvedLanguagePair(for text: String) -> (source: String, target: String) {
        let source = normalizeSourceLanguage(selectedSourceLanguage())
        var target = normalizeTargetLanguage(selectedTargetLanguage())
        if source == "Vietnamese" {
            target = "English"
        }
        if source == target {
            target = source == "English" ? "Vietnamese" : "English"
        }
        if source == "Auto detect" {
            let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
            let looksVietnamese = sample.contains(where: { $0.value >= 0x0102 && $0.value <= 0x1EF9 }) || text.localizedCaseInsensitiveContains("đ")
            if looksVietnamese {
                target = "English"
            }
        }
        return (source, target)
    }
```

with:

```swift
    private func normalizeSourceLanguage(_ value: String) -> String {
        LanguageDetector.normalizeSource(value)
    }

    private func normalizeTargetLanguage(_ value: String) -> String {
        LanguageDetector.normalizeTarget(value)
    }

    private func resolvedLanguagePair(for text: String) -> (source: String, target: String) {
        LanguageDetector.resolvedPair(selectedSource: selectedSourceLanguage(), selectedTarget: selectedTargetLanguage(), text: text)
    }
```

In `configureLanguageControls()` (originally lines 358-375), replace the two `supportedLanguages` references:

```swift
        sourceLanguagePopup.addItems(withTitles: supportedLanguages)
```
```swift
        targetLanguagePopup.addItems(withTitles: supportedLanguages.filter { $0 != "Auto detect" })
```

with:

```swift
        sourceLanguagePopup.addItems(withTitles: LanguageDetector.supportedLanguages)
```
```swift
        targetLanguagePopup.addItems(withTitles: LanguageDetector.supportedLanguages.filter { $0 != "Auto detect" })
```

Replace `sourceSpeechModel(for:)` (originally lines 491-500):

```swift
    private func sourceSpeechModel(for text: String) -> String {
        let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        if sample.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
            return config.speechSourceModelChinese
        }
        if sample.contains(where: { $0.value >= 0x0102 && $0.value <= 0x1EF9 }) || text.localizedCaseInsensitiveContains("đ") {
            return config.speechSourceModelVietnamese
        }
        return config.speechSourceModel
    }
```

with:

```swift
    private func sourceSpeechModel(for text: String) -> String {
        if LanguageDetector.looksChinese(text) {
            return config.speechSourceModelChinese
        }
        if LanguageDetector.looksVietnamese(text) {
            return config.speechSourceModelVietnamese
        }
        return config.speechSourceModel
    }
```

Delete the `hotKeyCode(for:)` method entirely (originally lines 522-552).

In `registerHotKey()`, change the call site (originally line 567):

```swift
        let status = RegisterEventHotKey(hotKeyCode(for: config.hotkey.key), hotKeyModifiers(), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
```

to:

```swift
        let status = RegisterEventHotKey(HotkeyKeyCode.code(for: config.hotkey.key), hotKeyModifiers(), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
```

- [ ] **Step 7: Build and run the full test suite**

Run: `swift build 2>&1 | tail -30 && swift test 2>&1 | tail -30`
Expected: build succeeds with no warnings about unused `supportedLanguages`/`hotKeyCode`; all tests pass.

- [ ] **Step 8: Manual QA**

Run: `.build/debug/translate` (or `swift run`), select some English text in another app, press Option+D. Confirm translation still works, language auto-detect still picks Vietnamese target/source correctly for a Vietnamese sentence, and the hotkey still fires normally.

- [ ] **Step 9: Commit**

```bash
git add Sources/translate/HotkeyKeyCode.swift Sources/translate/LanguageDetector.swift Sources/translate/PopoverController.swift Tests/translateTests/translateTests.swift
git commit -m "refactor: extract language detection and hotkey key-code mapping into testable types"
```

---

### Task 2: Surface `AppConfig` load/parse failures instead of failing silently

**Files:**
- Modify: `Sources/translate/AppConfig.swift:48-53`
- Modify: `Sources/translate/PopoverController.swift:602-613` (`reloadConfig()`)
- Test: `Tests/translateTests/translateTests.swift`

**Interfaces:**
- Produces: `AppConfig.ConfigLoadOutcome` enum (`.loaded(AppConfig)`, `.missing`, `.invalid(String)`), `AppConfig.decodeOutcome(from: Data?) -> ConfigLoadOutcome` (pure, testable), `AppConfig.loadOutcome() -> ConfigLoadOutcome` (reads disk), `AppConfig.load() -> AppConfig` (unchanged signature, now backed by `loadOutcome()`).
- Consumes: none new — `config.keychainService`, `config.apiBaseURL`, `config.speechURL` used exactly as before in `reloadConfig()`.

- [ ] **Step 1: Write the failing tests for `decodeOutcome`**

Append to `Tests/translateTests/translateTests.swift` (inside the `TranslateTests` struct):

```swift
    @Test func configDecodeOutcomeReturnsMissingForNilData() {
        guard case .missing = AppConfig.decodeOutcome(from: nil) else {
            Issue.record("expected .missing")
            return
        }
    }

    @Test func configDecodeOutcomeReturnsInvalidForMalformedJSON() {
        let data = Data("{ not json".utf8)
        guard case .invalid = AppConfig.decodeOutcome(from: data) else {
            Issue.record("expected .invalid")
            return
        }
    }

    @Test func configDecodeOutcomeLoadsValidJSON() {
        let json = """
        {"apiBaseURL":"http://localhost:1/v1/chat/completions","keychainService":"svc","model":"m","sourceLang":"Auto detect","targetLang":"Vietnamese","systemPrompt":"p","speechSourceModel":"a","speechSourceModelVietnamese":"b","speechSourceModelChinese":"c","speechTargetModel":"d","hotkey":{"key":"D","option":true,"command":false,"control":false,"shift":false},"ui":{"width":480,"height":320,"autoCopy":false}}
        """
        guard case let .loaded(config) = AppConfig.decodeOutcome(from: Data(json.utf8)) else {
            Issue.record("expected .loaded")
            return
        }
        #expect(config.model == "m")
    }
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter TranslateTests 2>&1 | tail -30`
Expected: FAIL — `type 'AppConfig' has no member 'decodeOutcome'`

- [ ] **Step 3: Replace `AppConfig.load()` (originally lines 48-53) with the outcome-based implementation**

In `Sources/translate/AppConfig.swift`, replace:

```swift
    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return .default }
        return config
    }
```

with:

```swift
    enum ConfigLoadOutcome {
        case loaded(AppConfig)
        case missing
        case invalid(String)
    }

    static func decodeOutcome(from data: Data?) -> ConfigLoadOutcome {
        guard let data else { return .missing }
        do {
            return .loaded(try JSONDecoder().decode(AppConfig.self, from: data))
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    static func loadOutcome() -> ConfigLoadOutcome {
        decodeOutcome(from: try? Data(contentsOf: URL(fileURLWithPath: configPath)))
    }

    static func load() -> AppConfig {
        switch loadOutcome() {
        case let .loaded(config): return config
        case .missing, .invalid: return .default
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TranslateTests 2>&1 | tail -30`
Expected: PASS

- [ ] **Step 5: Surface the failure reason in `PopoverController.reloadConfig()`**

In `Sources/translate/PopoverController.swift`, replace `reloadConfig()` (originally lines 602-613):

```swift
    @objc private func reloadConfig() {
        config = AppConfig.load()
        rebuildPopoverLayout()
        do {
            translator = try Translator(config: config, apiKey: APIKeychain.load(service: config.keychainService))
            registerHotKey()
            assert(URL(string: config.apiBaseURL) != nil)
            assert(URL(string: config.speechURL) != nil)
        } catch {
            setResultText("Config load error: \(error.localizedDescription)")
        }
    }
```

with:

```swift
    @objc private func reloadConfig() {
        let outcome = AppConfig.loadOutcome()
        switch outcome {
        case let .loaded(loadedConfig):
            config = loadedConfig
        case .missing, .invalid:
            config = .default
        }
        rebuildPopoverLayout()
        do {
            translator = try Translator(config: config, apiKey: APIKeychain.load(service: config.keychainService))
            registerHotKey()
            assert(URL(string: config.apiBaseURL) != nil)
            assert(URL(string: config.speechURL) != nil)
            if case let .invalid(reason) = outcome {
                setResultText("Config file is invalid, using defaults instead: \(reason)")
            }
        } catch {
            setResultText("Config load error: \(error.localizedDescription)")
        }
    }
```

(Note: `rebuildPopoverLayout()` here is renamed to `reflowLayout()` by Task 4 — if executing tasks in order, Task 4 will touch this same line again; that's expected and fine.)

- [ ] **Step 6: Build, test, and manually verify the error surfaces**

Run: `swift build 2>&1 | tail -30 && swift test 2>&1 | tail -30`
Expected: build succeeds, tests pass.

Manual QA: run the app (`swift run`), open `~/Code/MacOS/translate/config.json`, break the JSON (delete a closing brace), save, click the status icon → menu → "Reload Config". Confirm the popover shows `Config file is invalid, using defaults instead: ...`. Restore the original `config.json` afterward and reload again to confirm it clears.

- [ ] **Step 7: Commit**

```bash
git add Sources/translate/AppConfig.swift Sources/translate/PopoverController.swift Tests/translateTests/translateTests.swift
git commit -m "fix: surface config parse/load failures instead of silently using defaults"
```

---

### Task 3: Fix the hotkey event-handler leak (duplicate-trigger bug)

**Files:**
- Modify: `Sources/translate/PopoverController.swift:55-101 (applicationDidFinishLaunching), 563-583 (registerHotKey)`

**Interfaces:**
- Produces: `installHotKeyEventHandler()` (called exactly once, from `applicationDidFinishLaunching`).
- Consumes: `hotKeyModifiers()`, `HotkeyKeyCode.code(for:)` (from Task 1), `translateAtCursor()` — all unchanged.

- [ ] **Step 1: Split `registerHotKey()` — move the one-time `InstallEventHandler` call out into its own method**

In `Sources/translate/PopoverController.swift`, replace `registerHotKey()` (originally lines 563-583):

```swift
    private func registerHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let hotKeyID = EventHotKeyID(signature: OSType(0x54524E53), id: 1)
        let status = RegisterEventHotKey(HotkeyKeyCode.code(for: config.hotkey.key), hotKeyModifiers(), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            setResultText("Failed to register hotkey")
            return
        }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                let controller = Unmanaged<PopoverController>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in controller.translateAtCursor() }
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }
```

with:

```swift
    private func installHotKeyEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                let controller = Unmanaged<PopoverController>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in controller.translateAtCursor() }
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private func registerHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let hotKeyID = EventHotKeyID(signature: OSType(0x54524E53), id: 1)
        let status = RegisterEventHotKey(HotkeyKeyCode.code(for: config.hotkey.key), hotKeyModifiers(), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            setResultText("Failed to register hotkey")
            return
        }
    }
```

- [ ] **Step 2: Call `installHotKeyEventHandler()` exactly once, in `applicationDidFinishLaunching`**

In `applicationDidFinishLaunching(_:)` (originally lines 55-101), find this line:

```swift
        buildPopover()
        buildMenu()
        reloadConfig()
```

and replace it with:

```swift
        buildPopover()
        buildMenu()
        installHotKeyEventHandler()
        reloadConfig()
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -30`
Expected: build succeeds.

- [ ] **Step 4: Manual QA — confirm no more duplicate firing after repeated reloads**

Run: `.build/debug/translate`. Click the status icon → "Reload Config" **5 times in a row**. Select some text in another app and press Option+D **once**. Confirm the popover opens and shows exactly one translation request (check Console.app filtered to process "translate" for a single `[NTranslate]` log line per press, or just confirm the popover doesn't flicker/reopen multiple times). Repeat: reload 5 more times, press the hotkey once again — behavior should be identical (no compounding).

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/PopoverController.swift
git commit -m "fix: install the hotkey event handler once instead of leaking one per config reload"
```

---

### Task 4: Extract & test popover layout math, then stop rebuilding the whole view tree on every keystroke

This is the highest-impact, highest-effort task — it targets the most likely cause of "UI hoạt động không ổn định". Read the whole task before starting; it touches most of `PopoverController.swift`'s view-construction code.

**Files:**
- Create: `Sources/translate/PopoverLayoutMath.swift`
- Modify: `Sources/translate/PopoverController.swift` (stored properties, `buildPopover`, `rebuildPopoverLayout`, `inputHeight`, `measuredTextHeight`, `textDidChange`, and every call site of `rebuildPopoverLayout()`)
- Test: `Tests/translateTests/translateTests.swift`

**Interfaces:**
- Produces: `enum PopoverLayoutMath` with `static func textHeight(for text: String, font: NSFont, containerWidth: CGFloat, lineFragmentPadding: CGFloat) -> CGFloat`, `static func attributedTextHeight(_ text: NSAttributedString, containerWidth: CGFloat) -> CGFloat`, `static func clampedInputHeight(measured: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat`.
- Produces (on `PopoverController`): `constructSubviewsIfNeeded()` (idempotent, builds the view tree exactly once), `reflowLayout()` (recomputes all frames from current `config`/text and resizes the popover in place — replaces every previous call to `rebuildPopoverLayout()`).
- Consumes: `LanguageDetector`, `HotkeyKeyCode` (Task 1), `AppConfig.ConfigLoadOutcome` (Task 2) — unaffected by this task.

- [ ] **Step 1: Write the failing tests for `PopoverLayoutMath`**

Append to `Tests/translateTests/translateTests.swift`:

```swift
    @Test func popoverLayoutMathClampsInputHeightToRange() {
        #expect(PopoverLayoutMath.clampedInputHeight(measured: 10, minHeight: 30, maxHeight: 74) == 30)
        #expect(PopoverLayoutMath.clampedInputHeight(measured: 200, minHeight: 30, maxHeight: 74) == 74)
        #expect(PopoverLayoutMath.clampedInputHeight(measured: 50, minHeight: 30, maxHeight: 74) == 50)
    }

    @Test func popoverLayoutMathGrowsWithLongerText() {
        let font = NSFont.systemFont(ofSize: 13)
        let shortHeight = PopoverLayoutMath.textHeight(for: "hi", font: font, containerWidth: 300, lineFragmentPadding: 5)
        let longText = String(repeating: "hello world ", count: 40)
        let longHeight = PopoverLayoutMath.textHeight(for: longText, font: font, containerWidth: 300, lineFragmentPadding: 5)
        #expect(longHeight > shortHeight)
    }

    @Test func popoverLayoutMathTreatsEmptyTextAsSingleLine() {
        let font = NSFont.systemFont(ofSize: 13)
        let emptyHeight = PopoverLayoutMath.textHeight(for: "", font: font, containerWidth: 300, lineFragmentPadding: 5)
        #expect(emptyHeight > 0)
    }
```

- [ ] **Step 2: Run the tests to verify they fail to compile**

Run: `swift test --filter TranslateTests 2>&1 | tail -30`
Expected: FAIL — `cannot find 'PopoverLayoutMath' in scope`

- [ ] **Step 3: Create `Sources/translate/PopoverLayoutMath.swift`**

```swift
import AppKit

enum PopoverLayoutMath {
    static func textHeight(for text: String, font: NSFont, containerWidth: CGFloat, lineFragmentPadding: CGFloat) -> CGFloat {
        let contentWidth = max(100, containerWidth)
        let storage = NSTextStorage(string: text.isEmpty ? " " : text)
        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = lineFragmentPadding
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    static func attributedTextHeight(_ text: NSAttributedString, containerWidth: CGFloat) -> CGFloat {
        let contentWidth = max(100, containerWidth)
        let storage = NSTextStorage(attributedString: text.length == 0 ? NSAttributedString(string: " ") : text)
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    static func clampedInputHeight(measured: CGFloat, minHeight: CGFloat, maxHeight: CGFloat) -> CGFloat {
        min(max(minHeight, measured), maxHeight)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TranslateTests 2>&1 | tail -30`
Expected: PASS

- [ ] **Step 5: Rewrite `inputHeight`/`measuredTextHeight` to delegate to `PopoverLayoutMath`**

Replace (originally lines 270-289):

```swift
    private func inputHeight(for text: String, minHeight: CGFloat, maxHeight: CGFloat, width: CGFloat) -> CGFloat {
        let inset = inputTextView.textContainerInset
        let padding = inputTextView.textContainer?.lineFragmentPadding ?? 5
        let contentWidth = max(100, width - 20 - inset.width * 2 - padding * 2)

        let storage = NSTextStorage(string: text.isEmpty ? " " : text)
        storage.addAttribute(.font, value: inputTextView.font ?? .systemFont(ofSize: 13), range: NSRange(location: 0, length: storage.length))

        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = padding

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let usedHeight = layoutManager.usedRect(for: container).height
        let measured = ceil(usedHeight + inset.height * 2)
        return min(max(minHeight, measured), maxHeight)
    }
```

with:

```swift
    private func inputHeight(for text: String, minHeight: CGFloat, maxHeight: CGFloat, width: CGFloat) -> CGFloat {
        let inset = inputTextView.textContainerInset
        let padding = inputTextView.textContainer?.lineFragmentPadding ?? 5
        let contentWidth = max(100, width - 20 - inset.width * 2 - padding * 2)
        let font = inputTextView.font ?? .systemFont(ofSize: 13)
        let measured = ceil(PopoverLayoutMath.textHeight(for: text, font: font, containerWidth: contentWidth, lineFragmentPadding: padding) + inset.height * 2)
        return PopoverLayoutMath.clampedInputHeight(measured: measured, minHeight: minHeight, maxHeight: maxHeight)
    }
```

Replace `measuredTextHeight` (originally lines 311-321):

```swift
    private func measuredTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let contentWidth = max(100, width)
        let storage = NSTextStorage(attributedString: text.length == 0 ? NSAttributedString(string: " ") : text)
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }
```

with:

```swift
    private func measuredTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        PopoverLayoutMath.attributedTextHeight(text, containerWidth: width)
    }
```

- [ ] **Step 6: Build and test**

Run: `swift build 2>&1 | tail -30 && swift test 2>&1 | tail -30`
Expected: build succeeds, tests pass. (No behavior change yet — pure refactor.)

- [ ] **Step 7: Add the new stored properties needed for in-place reflow**

In `Sources/translate/PopoverController.swift`, find the stored-properties block (originally lines 19-53) and add these three declarations right after `private let closeButton = NSButton(frame: .zero)`:

```swift
    private let titleLabel = NSTextField(labelWithString: "Translate")
    private var resultCardView: NSView?
    private var subviewsConstructed = false
```

- [ ] **Step 8: Replace `buildPopover()` with `constructSubviewsIfNeeded()` + `reflowLayout()`**

Replace the entire `buildPopover()` method (originally lines 104-251) with:

```swift
    private func buildPopover() {
        constructSubviewsIfNeeded()
        reflowLayout()
    }

    private func constructSubviewsIfNeeded() {
        guard !subviewsConstructed else { return }
        subviewsConstructed = true

        let vc = NSViewController()
        let root = NSView(frame: .zero)
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor

        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePopover)

        configureLanguageControls()

        let inputContainer = NSView(frame: .zero)
        inputContainer.wantsLayer = true
        inputContainer.layer?.cornerRadius = 10
        inputContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        inputContainerView = inputContainer

        inputTextView.isEditable = true
        inputTextView.isSelectable = true
        inputTextView.delegate = self
        inputTextView.font = .systemFont(ofSize: 13)
        inputTextView.drawsBackground = false
        inputTextView.textColor = .labelColor
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.textContainerInset = NSSize(width: 6, height: 6)
        inputTextView.textContainer?.widthTracksTextView = true

        inputScrollView.borderType = .noBorder
        inputScrollView.drawsBackground = false
        inputScrollView.hasHorizontalScroller = false
        inputScrollView.autohidesScrollers = true
        inputScrollView.documentView = inputTextView
        inputContainer.addSubview(inputScrollView)

        translateButton.title = "Translate"
        translateButton.image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: "Translate")
        translateButton.imagePosition = .imageLeading
        translateButton.target = self
        translateButton.action = #selector(runTranslate)
        translateButton.bezelStyle = .rounded
        translateButton.controlSize = .large

        learnButton.title = "Learn"
        learnButton.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Learn")
        learnButton.imagePosition = .imageLeading
        learnButton.target = self
        learnButton.action = #selector(runLearn)
        learnButton.bezelStyle = .rounded
        learnButton.controlSize = .large

        speakSourceButton.target = self
        speakSourceButton.action = #selector(speakInput)
        speakSourceButton.bezelStyle = .rounded
        speakSourceButton.controlSize = .large

        speakResultButton.target = self
        speakResultButton.action = #selector(speakResult)
        speakResultButton.bezelStyle = .rounded
        speakResultButton.controlSize = .large

        updateSpeakButtons()

        let resultCard = NSView(frame: .zero)
        resultCard.wantsLayer = true
        resultCard.layer?.cornerRadius = 12
        resultCard.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        resultCardView = resultCard

        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        textScrollView.borderType = .noBorder
        textScrollView.drawsBackground = false
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.documentView = textView
        resultCard.addSubview(textScrollView)

        root.addSubview(titleLabel)
        root.addSubview(closeButton)
        root.addSubview(sourceLanguagePopup)
        root.addSubview(swapLanguagesButton)
        root.addSubview(targetLanguagePopup)
        root.addSubview(inputContainer)
        root.addSubview(translateButton)
        root.addSubview(learnButton)
        root.addSubview(speakSourceButton)
        root.addSubview(speakResultButton)
        root.addSubview(resultCard)

        vc.view = root
        popover.contentViewController = vc
        popover.delegate = self
        popover.behavior = .applicationDefined
    }

    private func reflowLayout() {
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        let padding: CGFloat = 14
        let headerHeight: CGFloat = 18
        let languageHeight: CGFloat = 28
        let minInputHeight: CGFloat = 30
        let maxInputHeight: CGFloat = 74
        let buttonHeight: CGFloat = 30
        let buttonGap: CGFloat = 8
        let buttonTitles = ["Translate", "Learn", speakSourceButtonTitle(), speakResultButtonTitle()]
        let buttonFonts = [translateButton, learnButton, speakSourceButton, speakResultButton].map {
            ($0.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).withSize(NSFont.systemFontSize)
        }
        let buttonAreaHeight = actionButtonsHeight(height: buttonHeight, gap: buttonGap, width: width - padding * 2, titles: buttonTitles, fonts: buttonFonts)
        let languageY = height - padding - headerHeight - 10 - languageHeight
        let inputHeight = inputHeight(for: inputTextView.string, minHeight: minInputHeight, maxHeight: maxInputHeight, width: width - padding * 2)
        let inputY = languageY - 10 - inputHeight
        let buttonY = inputY - 12 - buttonHeight
        let resultY = padding
        let resultHeight = max(120, buttonY - 12 - resultY - (buttonAreaHeight - buttonHeight))

        guard let root = popover.contentViewController?.view, let inputContainer = inputContainerView, let resultCard = resultCardView else { return }
        root.setFrameSize(NSSize(width: width, height: height))

        titleLabel.frame = NSRect(x: padding, y: height - padding - headerHeight, width: 200, height: headerHeight)
        closeButton.frame = NSRect(x: width - padding - 18, y: height - padding - headerHeight + 1, width: 18, height: 18)

        sourceLanguagePopup.frame = NSRect(x: padding, y: languageY, width: 150, height: languageHeight)
        swapLanguagesButton.frame = NSRect(x: sourceLanguagePopup.frame.maxX + 8, y: languageY, width: 38, height: languageHeight)
        targetLanguagePopup.frame = NSRect(x: swapLanguagesButton.frame.maxX + 8, y: languageY, width: 150, height: languageHeight)

        let inputFrame = NSRect(x: padding, y: inputY, width: width - padding * 2, height: inputHeight)
        inputContainer.frame = inputFrame
        inputTextView.textContainer?.containerSize = NSSize(width: inputFrame.width - 20, height: .greatestFiniteMagnitude)
        inputTextView.frame = NSRect(x: 0, y: 0, width: inputFrame.width - 20, height: inputHeight - 2)
        inputScrollView.frame = NSRect(x: 10, y: 1, width: inputFrame.width - 20, height: inputHeight - 2)
        inputScrollView.hasVerticalScroller = inputHeight >= maxInputHeight

        updateSpeakButtons()
        layoutActionButtons(y: buttonY, height: buttonHeight, gap: buttonGap, width: width - padding * 2, titles: buttonTitles, fonts: buttonFonts)
        languageSelectionChanged()

        resultCard.frame = NSRect(x: padding, y: resultY, width: width - padding * 2, height: resultHeight)
        textView.minSize = NSSize(width: 0, height: resultHeight)
        textScrollView.frame = NSRect(x: 1, y: 1, width: resultCard.frame.width - 2, height: resultCard.frame.height - 2)

        if popover.isShown {
            popover.contentSize = NSSize(width: width, height: height)
        }
    }
```

- [ ] **Step 9: Delete the old `rebuildPopoverLayout()` wrapper and rename all call sites to `reflowLayout()`**

Delete this method entirely (originally lines 253-264):

```swift
    private func rebuildPopoverLayout() {
        let wasShown = popover.isShown
        let existingResult = textView.string
        let existingInput = inputTextView.string
        buildPopover()
        inputTextView.string = existingInput
        setResultText(existingResult)
        if wasShown {
            popover.contentSize = popover.contentViewController?.view.frame.size ?? .zero
            textView.scrollToBeginningOfDocument(nil)
        }
    }
```

Replace `textDidChange(_:)` (originally lines 377-384):

```swift
    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === inputTextView else { return }
        let selectedRange = inputTextView.selectedRange()
        let currentText = inputTextView.string
        rebuildPopoverLayout()
        inputTextView.string = currentText
        inputTextView.setSelectedRange(selectedRange)
    }
```

with:

```swift
    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === inputTextView else { return }
        reflowLayout()
    }
```

Then find every remaining call to `rebuildPopoverLayout()` and rename it to `reflowLayout()`. There are 5 more: one in `reloadConfig()`, one in `translateAtCursor()`, and two each in `runTranslate()`'s and `runLearn()`'s completion handlers (success and failure branches). For example, in `runTranslate()`:

```swift
                case let .success(value):
                    self?.setResultText(value)
                    self?.rebuildPopoverLayout()
                    self?.textView.scrollToBeginningOfDocument(nil)
```

becomes:

```swift
                case let .success(value):
                    self?.setResultText(value)
                    self?.reflowLayout()
                    self?.textView.scrollToBeginningOfDocument(nil)
```

Apply the same `rebuildPopoverLayout()` → `reflowLayout()` rename to: the `.failure` branch right below it in `runTranslate()`, both branches in `runLearn()`, the line in `translateAtCursor()`, and the line in `reloadConfig()`.

- [ ] **Step 10: Build and test**

Run: `swift build 2>&1 | tail -30 && swift test 2>&1 | tail -30`
Expected: build succeeds with no remaining references to `rebuildPopoverLayout` (grep to confirm: `grep -rn rebuildPopoverLayout Sources/` should return nothing). All tests pass.

- [ ] **Step 11: Manual QA — this is the critical verification for this task**

Run: `.build/debug/translate`. For each check below, watch specifically for flicker, cursor jumps, or the input losing focus while typing:

1. Select English text elsewhere, press Option+D — popover opens, translation runs, result shows. No flicker.
2. Click into the input box and type a long sentence character-by-character — confirm the text box grows smoothly, no flicker, and the text cursor stays exactly where you're typing (no jump-to-start).
3. With a Vietnamese input method active (or just type Vietnamese with `đ`, `ạ`, `ệ` etc. using the built-in Vietnamese keyboard if available), type a full sentence — confirm diacritics compose correctly and nothing gets dropped or reset mid-word.
4. Click "Translate" and "Learn" repeatedly — result box resizes correctly for both short and long (multi-paragraph "Learn" explanation) results, scrolled to top each time.
5. Click the status bar icon to toggle the popover open/closed a few times — still works.
6. Edit `config.json`'s `ui.width` to `600`, save, "Reload Config" — popover width updates correctly without needing to reopen it.

- [ ] **Step 12: Commit**

```bash
git add Sources/translate/PopoverLayoutMath.swift Sources/translate/PopoverController.swift Tests/translateTests/translateTests.swift
git commit -m "fix: stop rebuilding the entire popover view tree on every keystroke"
```

---

### Task 5: Consolidate the focus/dismiss state machine, add click-outside-to-dismiss, remove the force-unwrap

**Files:**
- Modify: `Sources/translate/PopoverController.swift` (stored properties, `applicationDidFinishLaunching`, `manualToggle`, `translateAtCursor`, `pasteResultToPreviousApp`, `closePopover`, `restorePreviousAppFocus`, `popoverDidShow`, `popoverDidClose`)

**Interfaces:**
- Produces: `private enum CloseFocusIntent: Equatable { case none, restorePrevious }`, `private var closeFocusIntent: CloseFocusIntent`, `private var activateAppOnShow: Bool` (replace the 3 old booleans), `installOutsideClickMonitor()` / `removeOutsideClickMonitor()` (wire up the previously-dead `globalMouseMonitor`).
- Consumes: `popover`, `previousApp`, `anchorWindow` — unchanged.

- [ ] **Step 1: Replace the 3 boolean flags with the new state**

In the stored-properties block, replace:

```swift
    private var previousApp: NSRunningApplication?
    private var shouldRestorePreviousAppFocus = false
    private var shouldActivateAppForSelectionFlow = false
    private var shouldRestoreFocusOnDismiss = false
```

with:

```swift
    private var previousApp: NSRunningApplication?
    private enum CloseFocusIntent: Equatable { case none, restorePrevious }
    private var closeFocusIntent: CloseFocusIntent = .none
    private var activateAppOnShow = false
```

- [ ] **Step 2: Update the Escape-key handlers in `applicationDidFinishLaunching`**

Replace the local monitor's Escape branch:

```swift
            if event.keyCode == UInt16(kVK_Escape) {
                self.shouldRestoreFocusOnDismiss = true
                self.shouldRestorePreviousAppFocus = true
                self.popover.performClose(nil)
                return nil
            }
```

with:

```swift
            if event.keyCode == UInt16(kVK_Escape) {
                self.closeFocusIntent = .restorePrevious
                self.popover.performClose(nil)
                return nil
            }
```

Replace the global monitor's Escape branch:

```swift
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in
                    self.shouldRestoreFocusOnDismiss = true
                    self.shouldRestorePreviousAppFocus = true
                    self.popover.performClose(nil)
                }
                return
            }
```

with:

```swift
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in
                    self.closeFocusIntent = .restorePrevious
                    self.popover.performClose(nil)
                }
                return
            }
```

- [ ] **Step 3: Update `manualToggle()`**

Replace:

```swift
    @objc private func manualToggle() {
        guard NSApp.currentEvent?.type == .leftMouseUp else { return }
        if popover.isShown {
            shouldRestoreFocusOnDismiss = true
            shouldRestorePreviousAppFocus = true
            popover.performClose(nil)
        } else if let button = statusItem.button {
            shouldActivateAppForSelectionFlow = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
```

with:

```swift
    @objc private func manualToggle() {
        guard NSApp.currentEvent?.type == .leftMouseUp else { return }
        if popover.isShown {
            closeFocusIntent = .restorePrevious
            popover.performClose(nil)
        } else if let button = statusItem.button {
            activateAppOnShow = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
```

- [ ] **Step 4: Update `translateAtCursor()` and remove the force-unwrap**

Replace:

```swift
        previousApp = NSWorkspace.shared.frontmostApplication
        let text = SelectionReader.snapshotText() ?? NSPasteboard.general.string(forType: .string) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputTextView.string = trimmed
        rebuildPopoverLayout()
        updateLanguageSelection(for: trimmed)
        setResultText("Translating...")
        moveAnchorWindowToMouse()
        if !popover.isShown {
            shouldRestorePreviousAppFocus = true
            shouldActivateAppForSelectionFlow = false
            shouldRestoreFocusOnDismiss = false
            popover.show(relativeTo: anchorWindow.contentView!.bounds, of: anchorWindow.contentView!, preferredEdge: .maxY)
        }
        runTranslate()
```

with:

```swift
        previousApp = NSWorkspace.shared.frontmostApplication
        let text = SelectionReader.snapshotText() ?? NSPasteboard.general.string(forType: .string) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputTextView.string = trimmed
        reflowLayout()
        updateLanguageSelection(for: trimmed)
        setResultText("Translating...")
        moveAnchorWindowToMouse()
        if !popover.isShown, let anchorContentView = anchorWindow.contentView {
            activateAppOnShow = false
            popover.show(relativeTo: anchorContentView.bounds, of: anchorContentView, preferredEdge: .maxY)
        }
        runTranslate()
```

(Note: this also renames the leftover `rebuildPopoverLayout()` call here to `reflowLayout()` in case Task 4's Step 9 rename missed it — grep afterward to confirm none remain.)

- [ ] **Step 5: Update `pasteResultToPreviousApp()`**

Replace:

```swift
    private func pasteResultToPreviousApp() {
        guard let value = copyValue(), writePasteboard(value) else {
            popover.performClose(nil)
            return
        }
        let app = previousApp
        shouldRestoreFocusOnDismiss = false
        shouldRestorePreviousAppFocus = false
        popover.performClose(nil)
```

with:

```swift
    private func pasteResultToPreviousApp() {
        guard let value = copyValue(), writePasteboard(value) else {
            popover.performClose(nil)
            return
        }
        let app = previousApp
        closeFocusIntent = .none
        popover.performClose(nil)
```

(leave the rest of the method — the `DispatchQueue.main.asyncAfter` chain below — untouched; that's addressed by optional Task 6).

- [ ] **Step 6: Update `closePopover()`**

Replace:

```swift
    @objc private func closePopover() {
        shouldRestoreFocusOnDismiss = true
        shouldRestorePreviousAppFocus = true
        popover.performClose(nil)
    }
```

with:

```swift
    @objc private func closePopover() {
        closeFocusIntent = .restorePrevious
        popover.performClose(nil)
    }
```

- [ ] **Step 7: Simplify `restorePreviousAppFocus()`, add the outside-click monitor, and update the `NSPopoverDelegate` callbacks**

Replace:

```swift
    private func restorePreviousAppFocus() {
        defer {
            previousApp = nil
            shouldRestorePreviousAppFocus = false
            shouldActivateAppForSelectionFlow = false
            shouldRestoreFocusOnDismiss = false
        }
        guard shouldRestorePreviousAppFocus, shouldRestoreFocusOnDismiss else { return }
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }

    func popoverDidClose(_ notification: Notification) {
        restorePreviousAppFocus()
    }

    func popoverDidShow(_ notification: Notification) {
        guard shouldActivateAppForSelectionFlow else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
```

with:

```swift
    private func restorePreviousAppFocus() {
        defer {
            previousApp = nil
            closeFocusIntent = .none
            activateAppOnShow = false
        }
        guard closeFocusIntent == .restorePrevious else { return }
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }

    private func installOutsideClickMonitor() {
        guard globalMouseMonitor == nil else { return }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                self.closeFocusIntent = .restorePrevious
                self.popover.performClose(nil)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        globalMouseMonitor = nil
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
        restorePreviousAppFocus()
    }

    func popoverDidShow(_ notification: Notification) {
        installOutsideClickMonitor()
        guard activateAppOnShow else { return }
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 8: Build and test**

Run: `swift build 2>&1 | tail -30 && swift test 2>&1 | tail -30`
Expected: build succeeds — grep `grep -rn "shouldRestorePreviousAppFocus\|shouldActivateAppForSelectionFlow\|shouldRestoreFocusOnDismiss" Sources/` returns nothing. All tests pass.

- [ ] **Step 9: Manual QA — cover every open/close path**

Run: `.build/debug/translate`.

1. **Hotkey open → Escape**: select text, Option+D, press Escape. Popover closes, focus returns to the app you selected text in (click there and confirm you can type/click normally).
2. **Hotkey open → click outside**: select text, Option+D, click somewhere else on screen (not the popover). Popover closes (this is the fix for the previously-dead click-outside code) and focus returns correctly.
3. **Hotkey open → ⌘V paste-to-app**: select text, Option+D, wait for translation, press ⌘V. Popover closes, translated text is pasted into the original app at the cursor.
4. **Manual toggle open → click icon again**: click the status bar icon, popover opens; click it again, popover closes.
5. **Manual toggle open → click outside**: click the status bar icon to open, then click elsewhere on screen — popover should close.
6. **Manual toggle open → Escape**: click the status bar icon to open, press Escape — popover closes.
7. **Close button**: open via either path, click the "×" close button in the popover header — closes correctly.
8. Repeat check 2 and 5 with a **left click and a right click** to confirm both are caught by the monitor.

- [ ] **Step 10: Commit**

```bash
git add Sources/translate/PopoverController.swift
git commit -m "fix: consolidate focus/dismiss state into one enum, dismiss popover on outside click, remove force-unwrap"
```

---

### Task 6 (Optional / stretch): Replace the fixed-delay paste-activation wait with a notification-based wait

Lower severity (timing race, not a reproducible bug) — do this only after Tasks 1-5 are verified stable. Skip if time-constrained; note it as a known follow-up instead.

**Files:**
- Modify: `Sources/translate/PopoverController.swift:791-806` (`pasteResultToPreviousApp`)

**Interfaces:**
- Consumes: `NSWorkspace.shared.notificationCenter`, `NSWorkspace.didActivateApplicationNotification` — new, not previously used in this file.

- [ ] **Step 1: Replace the two chained `asyncAfter` calls with an activation-notification observer**

Replace:

```swift
        let app = previousApp
        closeFocusIntent = .none
        popover.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            app?.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.postCommandV()
            }
        }
    }
```

with:

```swift
        let app = previousApp
        closeFocusIntent = .none
        popover.performClose(nil)
        guard let app else { return }
        var observer: NSObjectProtocol?
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  activated.processIdentifier == app.processIdentifier
            else { return }
            if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
            self?.postCommandV()
        }
        app.activate(options: [.activateIgnoringOtherApps])
    }
```

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -30`
Expected: build succeeds.

- [ ] **Step 3: Manual QA**

Run: `.build/debug/translate`. Select text in a heavier app (e.g. one that's slow to regain focus, or deliberately add background load with `yes > /dev/null &` beforehand and remember to `kill %1` after), Option+D, translate, press ⌘V. Confirm the paste lands correctly even under load, and still works normally without load. Then test rapid repeated use (open, ⌘V, open again, ⌘V again) to confirm the observer doesn't leak or double-fire.

- [ ] **Step 4: Commit**

```bash
git add Sources/translate/PopoverController.swift
git commit -m "fix: wait for target app activation notification instead of a fixed delay before pasting"
```

---

## Final Verification

After all tasks (or Tasks 1-5 if Task 6 is skipped):

```bash
cd ~/Code/MacOS/translate
swift build 2>&1 | tail -30
swift test 2>&1 | tail -30
grep -rn "rebuildPopoverLayout\|shouldRestorePreviousAppFocus\|shouldActivateAppForSelectionFlow\|shouldRestoreFocusOnDismiss" Sources/ || echo "clean"
```

Then run `./install-app.sh` once to ship the hardened build to `/Applications/NTranslate.app`, and re-run the full Manual QA checklist from Task 5 Step 9 against the installed app (not just the dev build) before considering this done — Accessibility permission is granted per-bundle, so confirm `/Applications/NTranslate.app` still has it after reinstall.
