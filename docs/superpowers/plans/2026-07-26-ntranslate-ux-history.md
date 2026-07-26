# NTranslate UX and History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hoàn thiện save/delete/filter/reopen/image-search/speech-rate/swap và redesign History theo Liquid Glass hiện có.

**Architecture:** Mở rộng các AppKit controller và store hiện có, đặt logic thuần tại các type hiện hữu để test trực tiếp. Không thêm dependency hoặc abstraction một-implementation; mọi mutation History persist atomically trước khi đổi state trong memory.

**Tech Stack:** Swift 6, AppKit, AVFoundation, Foundation, Swift Testing, Swift Package Manager.

## Global Constraints

- Giữ popup Translate hiện tại; chỉ redesign cửa sổ History theo Liquid Glass.
- Images fallback sang source text nếu LLM lỗi.
- Speech rate dùng chung 0.5x–1.5x, bước 0.1x, ghi nhớ bằng UserDefaults.
- Double-click History nạp nguyên record, không dịch lại.
- Xóa hàng loạt phải xác nhận và chỉ xóa tập record đang hiển thị.
- Không thay đổi schema JSON và không thêm dependency.
- Sau khi hoàn tất phải chạy `./install-app.sh` và báo version từ output.

---

### Task 1: History mutation và filter policy

**Files:**
- Modify: `Sources/translate/TranslationHistoryStore.swift`
- Modify: `Sources/translate/HistoryWindowController.swift`
- Test: `Tests/translateTests/TranslationHistoryStoreTests.swift`

**Interfaces:**
- Produces: `TranslationHistoryStore.remove(recordID: UUID) throws`
- Produces: `TranslationHistoryStore.remove(recordIDs: Set<UUID>) throws`
- Produces: `HistoryTimeRange` với `cutoff(now:calendar:) -> Date`
- Produces: `HistoryWindowController.filter(records:query:savedOnly:timeRange:now:calendar:) -> [TranslationRecord]`

- [ ] **Step 1: Viết test fail cho xóa và time filter**

Thêm các test Swift Testing:

```swift
@Test func removesRecordsAndReferencedAudio() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TranslationHistoryStore(directoryURL: directory)
    let first = record(source: "first")
    let second = record(source: "second")
    try store.append(first)
    try store.append(second)
    try store.attachAudio(Data([1, 2]), kind: .source, recordID: first.id)
    let audioPath = try #require(store.records.first(where: { $0.id == first.id })?.sourceAudioPath)

    try store.remove(recordIDs: [first.id])

    #expect(store.records.map(\.id) == [second.id])
    #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(audioPath).path))
    #expect(TranslationHistoryStore(directoryURL: directory).records.map(\.id) == [second.id])
}

@Test func filtersBySavedQueryAndTimeRange() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let recent = TranslationRecord(id: UUID(), timestamp: now.addingTimeInterval(-3600), sourceText: "Galaxy", resultText: "Thiên hà", sourceLanguage: "English", targetLanguage: "Vietnamese", isSaved: true)
    let old = TranslationRecord(id: UUID(), timestamp: now.addingTimeInterval(-8 * 86_400), sourceText: "Old", resultText: "Cũ", sourceLanguage: "English", targetLanguage: "Vietnamese", isSaved: true)

    let filtered = HistoryWindowController.filter(records: [recent, old], query: "galaxy", savedOnly: true, timeRange: .week, now: now)

    #expect(filtered.map(\.id) == [recent.id])
}
```

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `swift test --filter TranslationHistoryStoreTests`

Expected: FAIL vì `remove(recordIDs:)`, `HistoryTimeRange` và overload `filter` chưa tồn tại.

- [ ] **Step 3: Thêm implementation tối thiểu**

Trong store, tạo `updated = records.filter { !recordIDs.contains($0.id) }`, throw `recordNotFound` cho single remove không tồn tại, gọi `persist(updated)`, gán `records = updated`, rồi dọn các path audio của record đã xóa bằng `try? fileManager.removeItem`.

Trong History controller, thêm:

```swift
enum HistoryTimeRange: CaseIterable {
    case today, hours24, week, month

    func cutoff(now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .hours24: return now.addingTimeInterval(-86_400)
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        }
    }
}
```

Mở rộng `filter` để kết hợp `savedOnly`, query và `record.timestamp >= timeRange.cutoff(...)`.

- [ ] **Step 4: Chạy test**

Run: `swift test --filter TranslationHistoryStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/TranslationHistoryStore.swift Sources/translate/HistoryWindowController.swift Tests/translateTests/TranslationHistoryStoreTests.swift
git commit -m "feat: add history deletion and time filters"
```

### Task 2: History Liquid Glass và tương tác record

**Files:**
- Modify: `Sources/translate/HistoryWindowController.swift`
- Modify: `Sources/translate/PopoverController.swift`
- Test: `Tests/translateTests/TranslationHistoryStoreTests.swift`

**Interfaces:**
- Consumes: `remove(recordID:)`, `remove(recordIDs:)`, `HistoryTimeRange`
- Produces: `HistoryWindowController.init(store:onOpenRecord:)`
- Produces: callback `(TranslationRecord) -> Void`

- [ ] **Step 1: Viết test fail cho callback và tập clear visible**

```swift
@Test func openRecordCallbackUsesDoubleClickedRecord() throws {
    let directory = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = TranslationHistoryStore(directoryURL: directory)
    let item = record()
    try store.append(item)
    var opened: UUID?
    let controller = HistoryWindowController(store: store) { opened = $0.id }

    controller.reloadHistory()
    controller.openRecord(at: 0)

    #expect(opened == item.id)
}
```

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `swift test --filter TranslationHistoryStoreTests.openRecordCallbackUsesDoubleClickedRecord`

Expected: FAIL vì initializer callback và `openRecord(at:)` chưa tồn tại.

- [ ] **Step 3: Xây layout Liquid Glass bằng AppKit native**

- Dùng window trong suốt, `NSVisualEffectView` làm shell, corner radius 22 và material `.hudWindow`/blending `.behindWindow` phù hợp deployment target.
- Toolbar gồm `NSSearchField`, segmented `History/Saved Words`, segmented `Today/24h/Week/Month`, icon clear bằng SF Symbol `trash`.
- Row dùng surface trong suốt bo 16; text stack có trailing constraint tới action stack, `lineBreakMode = .byTruncatingTail`, `maximumNumberOfLines = 1`, tooltip chứa full text.
- Action button dùng SF Symbols: `speaker.wave.2`, `bookmark`/`bookmark.fill`, `trash`; giữ accessibility label.
- Cấu hình `tableView.target = self`, `doubleAction = #selector(openSelectedRecord)` và gọi callback qua `openRecord(at:)`.
- Toggle bookmark gọi `store.toggleSaved`, delete row gọi `store.remove`, clear visible dùng `NSAlert` xác nhận số record trước khi `remove(recordIDs:)`.

- [ ] **Step 4: Chạy test và build**

Run: `swift test --filter TranslationHistoryStoreTests && swift build`

Expected: PASS, build thành công.

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/HistoryWindowController.swift Sources/translate/PopoverController.swift Tests/translateTests/TranslationHistoryStoreTests.swift
git commit -m "feat: redesign translation history"
```

### Task 3: Image search query

**Files:**
- Modify: `Sources/translate/Translator.swift`
- Modify: `Sources/translate/PopoverController.swift`
- Test: `Tests/translateTests/translateTests.swift`

**Interfaces:**
- Produces: `Translator.imageSearchQuery(_:completion:)`
- Produces: `Translator.imageSearchPrompt`
- Produces: `PopoverIntegrationPolicy.imageSearchURL(query:) -> URL?`

- [ ] **Step 1: Viết test fail cho prompt và URL encoding**

```swift
@Test func imageSearchURLPreservesUnicodeAndGoogleImagesMode() throws {
    let url = try #require(PopoverIntegrationPolicy.imageSearchURL(query: "thiên hà xoắn ốc NASA"))
    let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    #expect(components.host == "www.google.com")
    #expect(components.queryItems?.first(where: { $0.name == "tbm" })?.value == "isch")
    #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == "thiên hà xoắn ốc NASA")
}

@Test func imageSearchPromptRequestsOnlyConcreteQuery() {
    #expect(Translator.imageSearchPrompt.contains("Return only"))
    #expect(Translator.imageSearchPrompt.localizedCaseInsensitiveContains("concrete"))
}
```

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `swift test --filter imageSearch`

Expected: FAIL vì API chưa tồn tại.

- [ ] **Step 3: Thêm LLM request và Images button**

Thêm `RequestMode.imageSearch`, prompt cố định yêu cầu query ngắn, cụ thể, trực quan và chỉ output query. `imageSearchQuery` tái dùng `request`/`perform` hiện có.

Trong popover, thêm icon/text button `Images` vào result actions. Khi click: lấy source đã trim, disable trong lúc query, gọi translator; mở URL từ response thành công. Nếu failure hoặc query rỗng, mở URL từ source text và gọi `setStatus("Image query failed; searched source text")`.

- [ ] **Step 4: Chạy test**

Run: `swift test --filter imageSearch && swift build`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/Translator.swift Sources/translate/PopoverController.swift Tests/translateTests/translateTests.swift
git commit -m "feat: add contextual image search"
```

### Task 4: Save, speech rate, reopen và swap

**Files:**
- Modify: `Sources/translate/PopoverController.swift`
- Modify: `Sources/translate/LanguageDetector.swift`
- Test: `Tests/translateTests/translateTests.swift`

**Interfaces:**
- Produces: `PopoverIntegrationPolicy.canSave(sourceText:resultText:isRequestInFlight:)`
- Produces: `LanguageDetector.swappedPair(selectedSource:selectedTarget:text:languages:targetLanguages:nativeLang:)`
- Produces: speech rate UserDefaults key `local.ninh.ntranslate.speechRate`

- [ ] **Step 1: Viết test fail cho Save và swap Auto**

```swift
@Test func validResultCanBeSavedWithoutExistingRecord() {
    #expect(PopoverIntegrationPolicy.canSave(sourceText: "Galaxy", resultText: "Thiên hà", isRequestInFlight: false))
    #expect(!PopoverIntegrationPolicy.canSave(sourceText: "Galaxy", resultText: PopoverFeedback.learning, isRequestInFlight: false))
}

@Test func swappingAutoDetectedEnglishUsesEnglishAsTarget() {
    let pair = LanguageDetector.swappedPair(selectedSource: LanguageDetector.autoDetect, selectedTarget: "Vietnamese", text: "Galaxy", languages: AppConfig.defaultLanguages, targetLanguages: AppConfig.defaultTargetLanguages, nativeLang: "Vietnamese")
    #expect(pair.source == "Vietnamese")
    #expect(pair.target == "English")
}
```

- [ ] **Step 2: Chạy test để xác nhận fail**

Run: `swift test --filter 'validResultCanBeSaved|swappingAutoDetected'`

Expected: FAIL vì signatures mới chưa tồn tại.

- [ ] **Step 3: Implement behavior tối thiểu**

- Đổi save policy sang kiểm tra source/result có nội dung, result copyable và request không chạy.
- `toggleSaveWord`: nếu record hiện tại khớp thì toggle; nếu không, tạo record mới `isSaved: true`, append và gán `currentRecordID`.
- Learn success giữ source/result hợp lệ để Save tạo record.
- History callback gọi helper nạp source/result/languages/currentRecordID, dừng request/speech, hiện panel và reflow; không gọi translator.
- Thêm rate pop-up 0.5...1.5 cạnh trái speech button, đọc/ghi UserDefaults. Trong `startPlayback`, đặt `player.enableRate = true`, `player.rate = speechRate` trước `play()`; thay đổi selection cập nhật player hiện tại.
- `swapLanguages` lấy `swappedPair`, hoán đổi `inputTextView.string` và `textView.string`, chọn cặp mới, invalidate request/speech/current record rồi reflow.

- [ ] **Step 4: Chạy toàn bộ test và build**

Run: `swift test && swift build`

Expected: toàn bộ PASS, build thành công.

- [ ] **Step 5: Commit**

```bash
git add Sources/translate/PopoverController.swift Sources/translate/LanguageDetector.swift Tests/translateTests/translateTests.swift
git commit -m "feat: complete translation actions"
```

### Task 5: Review, verify và install

**Files:**
- Verify: toàn bộ changed source/tests
- Generated install output: `NTranslate.app/Contents/Info.plist`, `NTranslate.app/Contents/MacOS/NTranslate`

**Interfaces:**
- Consumes: toàn bộ behavior Tasks 1–4.
- Produces: app đã build, sign và cài tại `/Applications/NTranslate.app`.

- [ ] **Step 1: Review diff cho scope và simplification**

Run: `git diff --check && git status --short && git diff --stat`

Expected: không whitespace error; chỉ file trực tiếp phục vụ spec và app bundle do install script quản lý.

- [ ] **Step 2: Chạy verification sạch**

Run: `swift test && swift build`

Expected: PASS.

- [ ] **Step 3: Build, sign, install**

Run: `./install-app.sh`

Expected: script in version/build, ký app và cài `/Applications/NTranslate.app` thành công.

- [ ] **Step 4: Xác minh app đã cài**

Run: `codesign --verify --deep --strict /Applications/NTranslate.app && defaults read /Applications/NTranslate.app/Contents/Info CFBundleShortVersionString`

Expected: `codesign` exit 0 và version khớp output install script.

- [ ] **Step 5: Báo kết quả**

Báo version/build, test/build/install status và các file thay đổi. Không commit generated app bundle trừ khi user yêu cầu.
