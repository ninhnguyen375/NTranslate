# Implementation Plan: Image Paste, History Filter, Custom History Directory

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support image paste into input, add freetext/saved filter in history popup, and make history directory customizable in config.

**Architecture:** Extend AppConfig with custom history directory URL initializer, update TranslationHistoryStore init, create InputTextView for image paste handling, and update HistoryWindowController with a search/filter bar.

**Tech Stack:** Swift, AppKit, Foundation.

## Global Constraints

- Swift 6 / AppKit desktop application.
- Preserve backward compatibility for history storage if custom directory is not configured.

---

### Task 1: Custom History Directory in Config and Store

**Files:**
- Modify: `Sources/translate/AppConfig.swift:50-60`
- Modify: `Sources/translate/TranslationHistoryStore.swift:45-55`
- Test: `Tests/translateTests/TranslationHistoryStoreTests.swift`

**Interfaces:**
- Produces: `AppConfig.historyDirectoryURL: URL`

- [ ] **Step 1: Write failing test for custom directory store init**

In `Tests/translateTests/TranslationHistoryStoreTests.swift`:
```swift
@Test func customHistoryDirectoryIsRespected() throws {
    let customDir = try temporaryDirectory().appendingPathComponent("custom_history")
    var config = AppConfig.default
    config.historyDirectory = customDir.path
    let store = TranslationHistoryStore(config: config)
    #expect(store.directoryURL.path == customDir.standardizedFileURL.path)
    #expect(store.audioDirectoryURL.path == customDir.appendingPathComponent("audio").standardizedFileURL.path)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter customHistoryDirectoryIsRespected`
Expected: FAIL (historyDirectory or init(config:) not existing)

- [ ] **Step 3: Implement historyDirectory in AppConfig & TranslationHistoryStore**

In `Sources/translate/AppConfig.swift`:
Add property `var historyDirectory: String?` and `var historyDirectoryURL: URL`:
```swift
var historyDirectory: String?

var historyDirectoryURL: URL {
    if let historyDirectory, !historyDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let expanded = NSString(string: historyDirectory).expandingTildeInPath
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }
    return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("NTranslate", isDirectory: true).standardizedFileURL
}
```

In `Sources/translate/TranslationHistoryStore.swift`:
```swift
convenience init(config: AppConfig, fileManager: FileManager = .default) {
    self.init(directoryURL: config.historyDirectoryURL, fileManager: fileManager)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter customHistoryDirectoryIsRespected`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/AppConfig.swift Sources/translate/TranslationHistoryStore.swift Tests/translateTests/TranslationHistoryStoreTests.swift
git commit -m "feat: add customizable historyDirectory to AppConfig and Store"
```

---

### Task 2: History Window Filtering (Search & Radio/Saved Filter)

**Files:**
- Modify: `Sources/translate/HistoryWindowController.swift`
- Test: `Tests/translateTests/TranslationHistoryStoreTests.swift`

**Interfaces:**
- Produces: UI search field, filter segment control, clear filter button in HistoryWindowController.

- [ ] **Step 1: Write test for filtering helper logic**

In `Tests/translateTests/TranslationHistoryStoreTests.swift`:
```swift
@Test func filterRecords() {
    let r1 = TranslationRecord(id: UUID(), timestamp: Date(), sourceText: "hello world", resultText: "xin chào thế giới", sourceLanguage: "en", targetLanguage: "vi", isSaved: true)
    let r2 = TranslationRecord(id: UUID(), timestamp: Date(), sourceText: "apple", resultText: "quả táo", sourceLanguage: "en", targetLanguage: "vi", isSaved: false)
    let records = [r1, r2]
    
    let filteredSaved = HistoryWindowController.filter(records: records, query: "", savedOnly: true)
    #expect(filteredSaved.count == 1 && filteredSaved[0].id == r1.id)
    
    let filteredQuery = HistoryWindowController.filter(records: records, query: "táo", savedOnly: false)
    #expect(filteredQuery.count == 1 && filteredQuery[0].id == r2.id)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter filterRecords`
Expected: FAIL

- [ ] **Step 3: Implement HistoryWindowController filtering**

Add `static func filter(records: [TranslationRecord], query: String, savedOnly: Bool) -> [TranslationRecord]` helper to `HistoryWindowController`.
Add `searchField: NSSearchField`, `segmentedControl: NSSegmentedControl`, `clearButton: NSButton` to `HistoryWindowController.swift`.
Update table view data source to use `filteredRecords`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter filterRecords`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/HistoryWindowController.swift Tests/translateTests/TranslationHistoryStoreTests.swift
git commit -m "feat: add freetext search and saved words filter to history window"
```

---

### Task 3: Image Paste Support in Input TextView

**Files:**
- Modify: `Sources/translate/PopoverController.swift`

- [ ] **Step 1: Implement InputTextView subclass with paste handler**

In `Sources/translate/PopoverController.swift`:
Create `InputTextView: NSTextView`:
```swift
final class InputTextView: NSTextView {
    var onImagePasted: ((Data) -> Void)?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            onImagePasted?(data)
            return
        }
        if let image = NSImage(pasteboard: pb), let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            onImagePasted?(png)
            return
        }
        super.paste(sender)
    }
}
```
Set `inputTextView = InputTextView(frame: .zero)` in `PopoverController`.
Connect `onImagePasted` to load pending image and show `imagePlaceholderLabel`.

- [ ] **Step 2: Test manually and verify build**

Run: `./install-app.sh`
Expected: App builds and installs cleanly.

- [ ] **Step 3: Commit**

```bash
git add Sources/translate/PopoverController.swift
git commit -m "feat: support image paste directly into input text view"
```
