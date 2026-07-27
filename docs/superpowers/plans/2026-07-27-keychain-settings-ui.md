# Keychain API Key and Settings UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chuyển API key khỏi `config.json` sang macOS Keychain, tự động migrate key hiện tại, thêm Settings window quản lý toàn bộ cấu hình, và bật Hardened Runtime.

**Architecture:** `AppConfig` tiếp tục chứa toàn bộ cấu hình không bí mật và được lưu dạng JSON với quyền `0600`; `APIKeyStore` là biên duy nhất đọc/ghi API key trong Keychain. `SettingsWindowController` dùng AppKit thuần, chỉnh một bản sao `AppConfig`, chỉ ghi khi Save, rồi callback cho `PopoverController` reload runtime state. Migration ghi Keychain thành công trước, sau đó mới xóa `apiKey` khỏi JSON để không làm mất credential.

**Tech Stack:** Swift 6.3, AppKit, Security.framework (`SecItem*`), Swift Testing, shell `codesign`.

## Global Constraints

- Không thêm dependency.
- Keychain service: `local.ninh.ntranslate`; account: `apiKey`.
- Keychain accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- `config.json` không được encode field `apiKey`; quyền file sau mọi lần ghi là `0600`.
- Migration phải idempotent: Keychain đã có key thì giữ key trong Keychain và chỉ xóa plaintext; ghi Keychain lỗi thì không xóa plaintext.
- Settings UI quản lý tất cả field hiện có của `AppConfig`.
- Settings UI có bốn tab: General, Prompts, Languages, Advanced.
- Save lỗi không đóng window và không thay đổi runtime config.
- Giữ Apple Development certificate hiện tại; bật Hardened Runtime bằng `codesign -o runtime`.
- Không bật App Sandbox trong scope này.
- Sau khi hoàn tất phải chạy `swift test`, `./install-app.sh`, và báo version/build từ script.

---

## File Map

- Create `Sources/translate/APIKeyStore.swift`: toàn bộ thao tác Keychain và lỗi có thể hiển thị.
- Modify `Sources/translate/AppConfig.swift`: bỏ secret khỏi model Codable, ghi JSON an toàn, migrate legacy key, validate dữ liệu Settings.
- Create `Sources/translate/SettingsWindowController.swift`: Settings window AppKit và mapping UI ↔ `AppConfig`.
- Modify `Sources/translate/PopoverController.swift`: mở Settings, load key từ Keychain, reload runtime sau Save.
- Modify `Tests/translateTests/translateTests.swift`: regression tests cho JSON, migration, validation, setup issues.
- Create `Tests/translateTests/APIKeyStoreTests.swift`: integration test tối thiểu với macOS Keychain.
- Modify `config.json.example`: xóa `apiKey` khỏi config mẫu.
- Modify `install-app.sh`: không seed local plaintext secret; bật Hardened Runtime và xác minh flag.

---

### Task 1: Keychain credential store

**Files:**
- Create: `Sources/translate/APIKeyStore.swift`
- Create: `Tests/translateTests/APIKeyStoreTests.swift`

**Interfaces:**
- Produces: `APIKeyStore.init(service:account:)`, `load() throws -> String?`, `save(_:) throws`, `delete() throws`.
- Consumes: Security.framework có sẵn trên macOS; không cần thay đổi `Package.swift`.

- [ ] **Step 1: Viết integration test thất bại cho vòng đời Keychain item**

Tạo `Tests/translateTests/APIKeyStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import translate

@Suite(.serialized)
struct APIKeyStoreTests {
    @Test func savesUpdatesLoadsAndDeletesAPIKey() throws {
        let account = "test-\(UUID().uuidString)"
        let store = APIKeyStore(service: "local.ninh.ntranslate.tests", account: account)
        defer { try? store.delete() }

        try store.delete()
        #expect(try store.load() == nil)

        try store.save("first-key")
        #expect(try store.load() == "first-key")

        try store.save("second-key")
        #expect(try store.load() == "second-key")

        try store.save("   ")
        #expect(try store.load() == nil)
    }
}
```

- [ ] **Step 2: Chạy test để xác nhận fail đúng lý do**

Run:

```bash
swift test --filter APIKeyStoreTests
```

Expected: FAIL compile với `cannot find 'APIKeyStore' in scope`.

- [ ] **Step 3: Implement Keychain wrapper tối thiểu**

Tạo `Sources/translate/APIKeyStore.swift`:

```swift
import Foundation
import Security

struct APIKeyStore: Sendable {
    static let shared = APIKeyStore(service: "local.ninh.ntranslate", account: "apiKey")

    let service: String
    let account: String

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw APIKeyStoreError(status: status) }
        guard let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else {
            throw APIKeyStoreError.invalidData
        }
        return value
    }

    func save(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try delete()
            return
        }

        let data = Data(trimmed.utf8)
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw APIKeyStoreError(status: updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw APIKeyStoreError(status: addStatus) }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw APIKeyStoreError(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

enum APIKeyStoreError: LocalizedError {
    case status(OSStatus)
    case invalidData

    init(status: OSStatus) {
        self = .status(status)
    }

    var errorDescription: String? {
        switch self {
        case let .status(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown Keychain error"
            return "Keychain error \(status): \(message)"
        case .invalidData:
            return "API key in Keychain is not valid UTF-8."
        }
    }
}
```

- [ ] **Step 4: Chạy integration test**

Run:

```bash
swift test --filter APIKeyStoreTests
```

Expected: PASS; test item được xóa bởi `defer`.

- [ ] **Step 5: Commit task**

```bash
git add Sources/translate/APIKeyStore.swift Tests/translateTests/APIKeyStoreTests.swift
git commit -m "feat: store API key in macOS Keychain

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Secret-free AppConfig, secure writes, and legacy migration

**Files:**
- Modify: `Sources/translate/AppConfig.swift:34-55,194-303,343-422,443-471`
- Modify: `Tests/translateTests/translateTests.swift:102-152,180-355`

**Interfaces:**
- Consumes: `APIKeyStore.load/save` từ Task 1.
- Produces: `AppConfig.write(_:at:fileManager:)`, `AppConfig.migrateLegacyAPIKey(at:fileManager:keyStore:)`, `AppConfig.validationIssues()`, và `setupIssues(apiKey:loadMessage:accessibilityTrusted:)`.

- [ ] **Step 1: Viết tests cho JSON không chứa secret, quyền `0600`, và migration idempotent**

Thêm vào `Tests/translateTests/translateTests.swift`:

```swift
@Test func appConfigEncodingNeverContainsAPIKey() throws {
    let text = String(decoding: try AppConfig.encodePrettyJSON(), as: UTF8.self)
    #expect(!text.contains("apiKey"))
}

@Test func appConfigWriteUsesOwnerOnlyPermissions() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let path = directory.appendingPathComponent("config.json").path
    defer { try? FileManager.default.removeItem(at: directory) }

    try AppConfig.write(.default, at: path)
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func migrationExtractsAndRemovesLegacyAPIKey() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let path = directory.appendingPathComponent("config.json").path
    let keyStore = APIKeyStore(service: "local.ninh.ntranslate.tests", account: UUID().uuidString)
    defer {
        try? keyStore.delete()
        try? FileManager.default.removeItem(at: directory)
    }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var object = try #require(
        JSONSerialization.jsonObject(with: AppConfig.encodePrettyJSON()) as? [String: Any]
    )
    object["apiKey"] = "legacy-secret"
    try JSONSerialization.data(withJSONObject: object).write(to: URL(fileURLWithPath: path))

    #expect(try AppConfig.migrateLegacyAPIKey(at: path, keyStore: keyStore))
    #expect(try keyStore.load() == "legacy-secret")
    let migratedText = try String(contentsOfFile: path, encoding: .utf8)
    #expect(!migratedText.contains("apiKey"))
    #expect(!try AppConfig.migrateLegacyAPIKey(at: path, keyStore: keyStore))
}

@Test func migrationKeepsExistingKeychainValue() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let path = directory.appendingPathComponent("config.json").path
    let keyStore = APIKeyStore(service: "local.ninh.ntranslate.tests", account: UUID().uuidString)
    defer {
        try? keyStore.delete()
        try? FileManager.default.removeItem(at: directory)
    }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try keyStore.save("keychain-secret")
    var object = try #require(
        JSONSerialization.jsonObject(with: AppConfig.encodePrettyJSON()) as? [String: Any]
    )
    object["apiKey"] = "stale-plaintext-secret"
    try JSONSerialization.data(withJSONObject: object).write(to: URL(fileURLWithPath: path))

    #expect(try AppConfig.migrateLegacyAPIKey(at: path, keyStore: keyStore))
    #expect(try keyStore.load() == "keychain-secret")
    #expect(!try String(contentsOfFile: path).contains("apiKey"))
}
```

Trong các JSON fixture cũ, `apiKey` có thể giữ tạm để xác minh decoder bỏ qua unknown legacy field. Đổi assertions trực tiếp trên `config.apiKey` vì property sẽ bị xóa.

- [ ] **Step 2: Chạy tests để xác nhận fail**

Run:

```bash
swift test --filter appConfig
```

Expected: FAIL compile do `write`, `migrateLegacyAPIKey` chưa tồn tại và test cũ còn tham chiếu `apiKey`.

- [ ] **Step 3: Xóa `apiKey` khỏi `AppConfig` và mọi initializer/default**

Trong `Sources/translate/AppConfig.swift`:

```swift
// Xóa property này:
var apiKey: String

// Xóa parameter `apiKey` khỏi init, dòng `self.apiKey = apiKey`,
// `apiKey: ""` khỏi AppConfig.default, và dòng decode apiKey.
```

Không thêm custom CodingKey cho legacy key. `JSONDecoder` mặc định bỏ qua field dư `apiKey`, nên config cũ vẫn decode được sau khi migration đọc secret riêng.

- [ ] **Step 4: Thêm write path duy nhất với atomic write và `0600`**

Thêm vào `AppConfig` và thay cả hai `data.write(...)` hiện có bằng helper này:

```swift
static func write(
    _ config: AppConfig,
    at path: String = configPath,
    fileManager: FileManager = .default
) throws {
    let directory = (path as NSString).deletingLastPathComponent
    try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
    try encodePrettyJSON(config).write(to: URL(fileURLWithPath: path), options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
}
```

`seedConfigFileIfMissing` dùng `try write(config, at:path, fileManager:fileManager)`. Backfill `historyDirectory` dùng `try? write(updatedConfig, at:path, fileManager:fileManager)`.

- [ ] **Step 5: Thêm migration an toàn, idempotent**

Thêm vào `AppConfig`:

```swift
@discardableResult
static func migrateLegacyAPIKey(
    at path: String = configPath,
    fileManager: FileManager = .default,
    keyStore: APIKeyStore = .shared
) throws -> Bool {
    let url = URL(fileURLWithPath: path)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch CocoaError.fileReadNoSuchFile {
        return false
    }

    guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          object.keys.contains("apiKey")
    else { return false }

    let legacyKey = (object["apiKey"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if try keyStore.load() == nil, !legacyKey.isEmpty {
        try keyStore.save(legacyKey)
    }

    object.removeValue(forKey: "apiKey")
    let sanitized = try JSONSerialization.data(
        withJSONObject: object,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    try sanitized.write(to: url, options: .atomic)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    return true
}
```

Thứ tự bắt buộc: `keyStore.save` trước `object.removeValue`. Nếu Keychain lỗi, function throw trước khi file bị ghi lại.

- [ ] **Step 6: Chuyển setup validation sang nhận API key runtime**

Đổi signature và nội dung:

```swift
func setupIssues(
    apiKey: String,
    loadMessage: String? = nil,
    accessibilityTrusted: Bool
) -> [String] {
    var issues: [String] = []
    if let loadMessage {
        let trimmed = loadMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { issues.append(trimmed) }
    }
    if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append("API key is empty. Menu → Settings…, enter your 9router API key, then Save.")
    }
    if apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || URL(string: apiBaseURL) == nil {
        issues.append("apiBaseURL is invalid: \(apiBaseURL)")
    }
    if apiSpeechURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || URL(string: apiSpeechURL) == nil {
        issues.append("apiSpeechURL is invalid: \(apiSpeechURL)")
    }
    if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append("model is empty.")
    }
    if !accessibilityTrusted {
        issues.append("Accessibility permission is missing. Menu → Grant Accessibility Access (needed to read selected text).")
    }
    return issues
}
```

Cập nhật tests gọi `setupIssues(apiKey: "", ...)` và `setupIssues(apiKey: "sk-test", ...)`.

- [ ] **Step 7: Thêm validation cho Settings trust boundary**

Thêm vào `AppConfig`:

```swift
func validationIssues() -> [String] {
    var issues: [String] = []
    let urls = [("API base URL", apiBaseURL), ("Speech URL", apiSpeechURL)]
    for (name, value) in urls {
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil
        else {
            issues.append("\(name) must be a valid http:// or https:// URL.")
            continue
        }
    }
    if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append("Model cannot be empty.")
    }
    if languages.isEmpty { issues.append("Languages cannot be empty.") }
    if targetLanguages.isEmpty { issues.append("Target languages cannot be empty.") }
    if Set(languages).count != languages.count { issues.append("Languages contain duplicates.") }
    if Set(targetLanguages).count != targetLanguages.count { issues.append("Target languages contain duplicates.") }
    if !languages.contains(sourceLang) { issues.append("Source language must exist in Languages.") }
    if !targetLanguages.contains(targetLang) { issues.append("Target language must exist in Target Languages.") }
    if maxTranslateLength <= 0 { issues.append("Maximum translation length must be greater than zero.") }
    if ui.width <= 0 || ui.height <= 0 { issues.append("Panel width and height must be greater than zero.") }
    if hotkey.key.count != 1 || !("A"..."Z").contains(hotkey.key.uppercased()) {
        issues.append("Hotkey must be one letter from A to Z.")
    }
    return issues
}
```

Thêm test tối thiểu:

```swift
@Test func appConfigValidationRejectsInvalidSettings() {
    var config = AppConfig.default
    config.apiBaseURL = "file:///tmp/key"
    config.languages = ["English", "English"]
    config.maxTranslateLength = 0
    let issues = config.validationIssues()
    #expect(issues.contains(where: { $0.contains("API base URL") }))
    #expect(issues.contains(where: { $0.contains("duplicates") }))
    #expect(issues.contains(where: { $0.contains("greater than zero") }))
}
```

- [ ] **Step 8: Chạy AppConfig tests và toàn suite**

Run:

```bash
swift test --filter appConfig
swift test
```

Expected: tất cả PASS; không còn source/test reference tới `config.apiKey`.

- [ ] **Step 9: Commit task**

```bash
git add Sources/translate/AppConfig.swift Tests/translateTests/translateTests.swift
git commit -m "feat: migrate API key out of config JSON

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Full Settings window

**Files:**
- Create: `Sources/translate/SettingsWindowController.swift`

**Interfaces:**
- Consumes: `AppConfig`, `AppConfig.validationIssues()`, `APIKeyStore` indirectly qua save callback.
- Produces: `SettingsWindowController.init(config:apiKey:onSave:)`, `showSettings(config:apiKey:)`.

- [ ] **Step 1: Tạo window shell và exact field inventory**

Tạo `Sources/translate/SettingsWindowController.swift` với API:

```swift
import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    typealias SaveHandler = (AppConfig, String) throws -> Void

    private var workingConfig: AppConfig
    private let onSave: SaveHandler

    private let apiKeyField = NSSecureTextField()
    private let apiBaseURLField = NSTextField()
    private let apiSpeechURLField = NSTextField()
    private let modelField = NSTextField()
    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let nativeLanguagePopup = NSPopUpButton()
    private let maxTranslateLengthField = NSTextField()

    private let systemPromptView = NSTextView()
    private let learnPromptView = NSTextView()
    private let sentenceLearnPromptView = NSTextView()
    private let grammarPromptView = NSTextView()

    private let languagesTable = NSTableView()
    private let targetLanguagesTable = NSTableView()

    private let autoPrefetchSpeechCheckbox = NSButton(checkboxWithTitle: "Prefetch speech automatically", target: nil, action: nil)
    private let speechSourceModelField = NSTextField()
    private let speechSourceModelVietnameseField = NSTextField()
    private let speechSourceModelChineseField = NSTextField()
    private let speechTargetModelField = NSTextField()
    private let historyDirectoryField = NSTextField()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let autoCopyCheckbox = NSButton(checkboxWithTitle: "Copy translation automatically", target: nil, action: nil)
    private let simulateCopyCheckbox = NSButton(checkboxWithTitle: "Paste translation into source app", target: nil, action: nil)
    private let hotkeyPopup = NSPopUpButton()
    private let optionCheckbox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let commandCheckbox = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    private let controlCheckbox = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    private let shiftCheckbox = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)

    init(config: AppConfig, apiKey: String, onSave: @escaping SaveHandler) {
        self.workingConfig = config
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NTranslate Settings"
        window.setFrameAutosaveName("NTranslateSettingsWindow")
        super.init(window: window)
        configureContent()
        populate(config: config, apiKey: apiKey)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showSettings(config: AppConfig, apiKey: String) {
        workingConfig = config
        populate(config: config, apiKey: apiKey)
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

Tab inventory bắt buộc:

- `General`: API Key, API Base URL, Speech URL, Model, Source Language, Target Language, Native Language, Maximum Translation Length.
- `Prompts`: System Prompt, Learn Word Prompt, Learn Sentence Prompt, Grammar Prompt; mỗi prompt là `NSTextView` trong scroll view, monospaced 12 pt.
- `Languages`: hai `NSTableView`, mỗi bảng có Add và Remove; bảng trái là `languages`, bảng phải là `targetLanguages`.
- `Advanced`: bốn speech model, auto-prefetch, history directory + Choose…, panel width/height, auto-copy, simulate-copy, hotkey A–Z và bốn modifiers.
- Footer ngoài tab: `Cancel`, `Revert`, `Save`.

- [ ] **Step 2: Build controls bằng AppKit native, không custom drawing**

Dùng helper cục bộ sau để tránh lặp layout mà không tạo abstraction ngoài file:

```swift
private func labeledRow(_ label: String, _ control: NSView) -> NSView {
    let title = NSTextField(labelWithString: label)
    title.alignment = .right
    title.widthAnchor.constraint(equalToConstant: 150).isActive = true
    let row = NSStackView(views: [title, control])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    return row
}

private func verticalForm(_ rows: [NSView]) -> NSStackView {
    let stack = NSStackView(views: rows)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 12
    stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    return stack
}

private func scrollView(for documentView: NSView) -> NSScrollView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .bezelBorder
    scroll.documentView = documentView
    return scroll
}
```

`configureContent()` phải:

```swift
private func configureContent() {
    apiKeyField.placeholderString = "Stored in macOS Keychain"
    maxTranslateLengthField.formatter = integerFormatter(minimum: 1)
    widthField.formatter = integerFormatter(minimum: 1)
    heightField.formatter = integerFormatter(minimum: 1)
    hotkeyPopup.addItems(withTitles: (65...90).compactMap { UnicodeScalar($0).map(String.init) })

    [systemPromptView, learnPromptView, sentenceLearnPromptView, grammarPromptView].forEach {
        $0.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        $0.isRichText = false
        $0.isAutomaticQuoteSubstitutionEnabled = false
        $0.isAutomaticDashSubstitutionEnabled = false
    }

    configureLanguageTable(languagesTable, identifier: "languages")
    configureLanguageTable(targetLanguagesTable, identifier: "targetLanguages")

    let tabs = NSTabView()
    tabs.addTabViewItem(tab(title: "General", view: makeGeneralView()))
    tabs.addTabViewItem(tab(title: "Prompts", view: makePromptsView()))
    tabs.addTabViewItem(tab(title: "Languages", view: makeLanguagesView()))
    tabs.addTabViewItem(tab(title: "Advanced", view: makeAdvancedView()))

    let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
    let revert = NSButton(title: "Revert", target: self, action: #selector(revertClicked))
    let save = NSButton(title: "Save", target: self, action: #selector(saveClicked))
    save.keyEquivalent = "\r"

    let buttons = NSStackView(views: [revert, NSView(), cancel, save])
    buttons.orientation = .horizontal
    buttons.spacing = 8
    let root = NSStackView(views: [tabs, buttons])
    root.orientation = .vertical
    root.spacing = 12
    root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
    tabs.setContentHuggingPriority(.defaultLow, for: .vertical)
    buttons.setContentHuggingPriority(.required, for: .vertical)
    window?.contentView = root
}
```

`tab(title:view:)`, `integerFormatter(minimum:)`, `makeGeneralView`, `makePromptsView`, `makeLanguagesView`, `makeAdvancedView` chỉ tạo native controls đã liệt kê; không thêm design system hoặc custom component.

- [ ] **Step 3: Implement language list editor với Add/Remove**

```swift
private func configureLanguageTable(_ table: NSTableView, identifier: String) {
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
    column.title = "Language"
    table.addTableColumn(column)
    table.headerView = nil
    table.delegate = self
    table.dataSource = self
}

func numberOfRows(in tableView: NSTableView) -> Int {
    tableView === languagesTable ? workingConfig.languages.count : workingConfig.targetLanguages.count
}

func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let value = tableView === languagesTable
        ? workingConfig.languages[row]
        : workingConfig.targetLanguages[row]
    let field = NSTextField(string: value)
    field.identifier = tableColumn?.identifier
    field.tag = row
    field.target = self
    field.action = #selector(languageEdited(_:))
    return field
}

@objc private func languageEdited(_ sender: NSTextField) {
    let value = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if sender.identifier?.rawValue == "languages" {
        workingConfig.languages[sender.tag] = value
    } else {
        workingConfig.targetLanguages[sender.tag] = value
    }
    reloadLanguagePopups()
}

@objc private func addSourceLanguage() {
    workingConfig.languages.append("New Language")
    languagesTable.reloadData()
    languagesTable.selectRowIndexes(IndexSet(integer: workingConfig.languages.count - 1), byExtendingSelection: false)
    languagesTable.editColumn(0, row: workingConfig.languages.count - 1, with: nil, select: true)
}

@objc private func removeSourceLanguage() {
    guard languagesTable.selectedRow >= 0 else { return }
    workingConfig.languages.remove(at: languagesTable.selectedRow)
    languagesTable.reloadData()
    reloadLanguagePopups()
}

@objc private func addTargetLanguage() {
    workingConfig.targetLanguages.append("New Language")
    targetLanguagesTable.reloadData()
    targetLanguagesTable.selectRowIndexes(IndexSet(integer: workingConfig.targetLanguages.count - 1), byExtendingSelection: false)
    targetLanguagesTable.editColumn(0, row: workingConfig.targetLanguages.count - 1, with: nil, select: true)
}

@objc private func removeTargetLanguage() {
    guard targetLanguagesTable.selectedRow >= 0 else { return }
    workingConfig.targetLanguages.remove(at: targetLanguagesTable.selectedRow)
    targetLanguagesTable.reloadData()
    reloadLanguagePopups()
}
```

Trước Save, gọi `window?.makeFirstResponder(nil)` để commit edit đang mở trong table/text field.

- [ ] **Step 4: Implement populate, collect, Save/Revert/Cancel**

`populate` phải map mọi field 1:1. `collectConfig` dùng bản sao `workingConfig`, trim field một dòng nhưng giữ nguyên whitespace trong prompt:

```swift
private func collectConfig() throws -> AppConfig {
    window?.makeFirstResponder(nil)
    var config = workingConfig
    config.apiBaseURL = apiBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    config.apiSpeechURL = apiSpeechURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    config.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    config.sourceLang = sourceLanguagePopup.titleOfSelectedItem ?? ""
    config.targetLang = targetLanguagePopup.titleOfSelectedItem ?? ""
    config.nativeLang = nativeLanguagePopup.titleOfSelectedItem ?? ""
    config.maxTranslateLength = maxTranslateLengthField.integerValue
    config.systemPrompt = systemPromptView.string
    config.learnPrompt = learnPromptView.string
    config.sentenceLearnPrompt = sentenceLearnPromptView.string
    config.grammarPrompt = grammarPromptView.string
    config.autoPrefetchSpeech = autoPrefetchSpeechCheckbox.state == .on
    config.speechSourceModel = speechSourceModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    config.speechSourceModelVietnamese = speechSourceModelVietnameseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    config.speechSourceModelChinese = speechSourceModelChineseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    config.speechTargetModel = speechTargetModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let history = historyDirectoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    config.historyDirectory = history.isEmpty ? nil : history
    config.ui.width = widthField.doubleValue
    config.ui.height = heightField.doubleValue
    config.ui.autoCopy = autoCopyCheckbox.state == .on
    config.ui.simulateCopy = simulateCopyCheckbox.state == .on
    config.hotkey.key = hotkeyPopup.titleOfSelectedItem ?? "D"
    config.hotkey.option = optionCheckbox.state == .on
    config.hotkey.command = commandCheckbox.state == .on
    config.hotkey.control = controlCheckbox.state == .on
    config.hotkey.shift = shiftCheckbox.state == .on

    let issues = config.validationIssues()
    if !issues.isEmpty {
        throw SettingsError.validation(issues)
    }
    return config
}

@objc private func saveClicked() {
    do {
        let config = try collectConfig()
        try onSave(config, apiKeyField.stringValue)
        workingConfig = config
        close()
    } catch {
        present(error)
    }
}

@objc private func revertClicked() {
    populate(config: workingConfig, apiKey: apiKeyField.stringValue)
}

@objc private func cancelClicked() {
    close()
}
```

Để `Revert` thực sự quay về snapshot lúc mở, thêm `private var originalConfig` và `private var originalAPIKey`, cập nhật cả hai trong `showSettings`, rồi `revertClicked` gọi `populate(config: originalConfig, apiKey: originalAPIKey)`.

Error/UI helpers:

```swift
enum SettingsError: LocalizedError {
    case validation([String])

    var errorDescription: String? {
        switch self {
        case let .validation(issues): return issues.joined(separator: "\n")
        }
    }
}

private func present(_ error: Error) {
    let alert = NSAlert(error: error)
    if let window { alert.beginSheetModal(for: window) }
}
```

History directory picker:

```swift
@objc private func chooseHistoryDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    historyDirectoryField.stringValue = url.path
}
```

- [ ] **Step 5: Build và chạy toàn bộ test**

Run:

```bash
swift build
swift test
```

Expected: build và tests PASS. Warnings mới trong `SettingsWindowController.swift` bằng 0.

- [ ] **Step 6: Commit task**

```bash
git add Sources/translate/SettingsWindowController.swift
git commit -m "feat: add full settings window

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Wire Keychain and Settings into app runtime

**Files:**
- Modify: `Sources/translate/PopoverController.swift:240-298,1338-1418,1420-1453,1525-1573`

**Interfaces:**
- Consumes: `APIKeyStore.shared`, `AppConfig.migrateLegacyAPIKey`, `SettingsWindowController`.
- Produces: menu `Settings…`; reload path dùng Keychain; save callback cập nhật JSON + Keychain rồi reload app.

- [ ] **Step 1: Thêm runtime state cho key và Settings controller**

Gần các controller property hiện có:

```swift
private var apiKey = ""
private var settingsWindowController: SettingsWindowController?
```

- [ ] **Step 2: Chạy migration trước lần load đầu tiên**

Trong `applicationDidFinishLaunching`, trước `reloadConfig()`:

```swift
do {
    try AppConfig.migrateLegacyAPIKey()
} catch {
    setResultText("Error: Could not migrate API key to Keychain: \(error.localizedDescription)")
}
reloadConfig()
```

Không xóa plaintext hoặc tiếp tục giả định migration thành công khi function throw.

- [ ] **Step 3: Thay menu JSON bằng Settings**

Trong `buildMenu()` thay:

```swift
statusMenu.addItem(withTitle: "Open Config File", action: #selector(openConfigFileMenu), keyEquivalent: "")
statusMenu.addItem(withTitle: "Reload Config", action: #selector(reloadConfigMenu), keyEquivalent: "r")
```

bằng:

```swift
statusMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",")
```

Xóa `openConfigFileMenu` và `reloadConfigMenu`; giữ private `reloadConfig(showSuccess:)` cho runtime.

- [ ] **Step 4: Implement Settings open/save flow**

```swift
@objc private func openSettingsMenu() {
    let outcome = AppConfig.loadOutcome()
    let key: String
    do {
        key = try APIKeyStore.shared.load() ?? ""
    } catch {
        setResultText("Error: \(error.localizedDescription)")
        openTranslatePanelShowingSetupStatus(loadMessage: error.localizedDescription)
        return
    }

    if let controller = settingsWindowController {
        controller.showSettings(config: outcome.config, apiKey: key)
        return
    }

    let controller = SettingsWindowController(config: outcome.config, apiKey: key) { [weak self] config, key in
        try self?.saveSettings(config: config, apiKey: key)
    }
    settingsWindowController = controller
    controller.showSettings(config: outcome.config, apiKey: key)
}

private func saveSettings(config: AppConfig, apiKey newAPIKey: String) throws {
    let previousKey = try APIKeyStore.shared.load()
    try APIKeyStore.shared.save(newAPIKey)
    do {
        try AppConfig.write(config)
    } catch {
        if let previousKey {
            try? APIKeyStore.shared.save(previousKey)
        } else {
            try? APIKeyStore.shared.delete()
        }
        throw error
    }
    _ = reloadConfig(showSuccess: true)
}
```

Rollback credential nếu JSON write fail. Runtime chỉ reload sau cả hai write thành công.

- [ ] **Step 5: Load API key từ Keychain trong reload path**

Trong `reloadConfig(showSuccess:)`, sau `config = outcome.config`:

```swift
do {
    apiKey = try APIKeyStore.shared.load() ?? ""
} catch {
    apiKey = ""
    translator = nil
    setResultText("Error: \(error.localizedDescription)")
    return outcome
}
```

Thay local `let apiKey = config.apiKey...` bằng:

```swift
let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
guard !trimmedAPIKey.isEmpty else {
    translator = nil
    setResultText("Error: API key is empty — open Settings… and enter your 9router API key.")
    return outcome
}
translator = Translator(config: config, apiKey: trimmedAPIKey)
```

- [ ] **Step 6: Truyền runtime key vào setup checks và sửa copy**

Cả hai call `config.setupIssues(...)` phải thêm `apiKey: apiKey`.

Đổi status/copy cũ:

```swift
setStatus("Fix the errors above, then open Settings…")
setResultText("Saved settings")
```

Không còn text user-facing nhắc `Open Config File`, `Reload Config`, hoặc đường dẫn để nhập key.

- [ ] **Step 7: Build, test, grep regression**

Run:

```bash
swift test
grep -R "config\.apiKey\|Open Config File\|Reload Config" Sources Tests
```

Expected: tests PASS; grep không có output.

- [ ] **Step 8: Commit task**

```bash
git add Sources/translate/PopoverController.swift
git commit -m "feat: manage runtime settings through Keychain UI

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: Remove plaintext seed and enable Hardened Runtime

**Files:**
- Modify: `config.json.example`
- Modify: `install-app.sh:115-139`

**Interfaces:**
- Consumes: app-created `AppConfig.default` và migration từ Tasks 2–4.
- Produces: build ký với Hardened Runtime; fresh installs không copy developer `config.json` chứa secret.

- [ ] **Step 1: Xóa field secret khỏi config mẫu**

Xóa toàn bộ dòng:

```json
"apiKey": "",
```

khỏi `config.json.example`. Kiểm tra JSON còn hợp lệ:

```bash
plutil -lint config.json.example
```

Expected: `config.json.example: OK`.

- [ ] **Step 2: Ngừng ưu tiên local ignored `config.json` khi seed**

Trong `install-app.sh`, thay block `CONFIG_SRC` bằng:

```bash
CONFIG_SRC="$PROJECT_DIR/config.json.example"
```

Và thay block seed bằng:

```bash
mkdir -p "$CONFIG_SUPPORT_DIR"
if [ ! -f "$CONFIG_SRC" ]; then
  echo "Warning: no config.json.example in project; app will create defaults on launch" >&2
elif [ -f "$CONFIG_DST" ] && [ "${FORCE_CONFIG:-0}" != "1" ]; then
  echo "Config exists (leave as-is): $CONFIG_DST"
else
  cp "$CONFIG_SRC" "$CONFIG_DST"
  chmod 600 "$CONFIG_DST"
  echo "Config seeded: $CONFIG_SRC -> $CONFIG_DST"
fi
```

`FORCE_CONFIG=1` chỉ copy secret-free example. Không bao giờ copy ignored `config.json` nữa.

- [ ] **Step 3: Bật Hardened Runtime và verify flag trong script**

Thay signing block:

```bash
codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP_DST"
codesign -vv "$APP_DST"
codesign -dv --verbose=4 "$APP_DST" 2>&1 | grep -E 'Identifier=|Authority=|TeamIdentifier=|flags=' || true
FLAGS=$(codesign -dv --verbose=4 "$APP_DST" 2>&1 | grep 'flags=' || true)
if [[ "$FLAGS" != *"runtime"* ]]; then
  echo "Error: Hardened Runtime is not enabled" >&2
  exit 1
fi
```

Không thêm entitlement `disable-library-validation`, `allow-unsigned-executable-memory`, hoặc `get-task-allow`; chúng làm yếu mục tiêu bảo vệ key và app không cần chúng.

- [ ] **Step 4: Static checks**

Run:

```bash
plutil -lint config.json.example
zsh -n install-app.sh
grep -R '"apiKey"' config.json.example Sources/translate || true
```

Expected: JSON và shell syntax PASS; grep không tìm thấy secret field trong config schema/source (chuỗi migration `"apiKey"` trong `AppConfig.swift` là ngoại lệ duy nhất và phải xuất hiện đúng ở migration).

- [ ] **Step 5: Commit task**

```bash
git add config.json.example install-app.sh
git commit -m "build: enable hardened runtime signing

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: End-to-end verification and installed-app smoke test

**Files:**
- No source changes expected.
- Modify only code directly responsible if verification finds a failure; rerun affected task tests before continuing.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: verified installed `.app`, migrated credential, Settings persistence, Hardened Runtime evidence.

- [ ] **Step 1: Run complete automated suite**

```bash
swift test
```

Expected: all tests PASS; no Keychain test item remains after run.

- [ ] **Step 2: Snapshot existing plaintext-key state for manual migration check**

Do not print key. Check only presence:

```bash
python3 - <<'PY'
import json
from pathlib import Path
p = Path.home() / "Library/Application Support/NTranslate/config.json"
if not p.exists():
    print("legacy_api_key_present=false (config missing)")
else:
    data = json.loads(p.read_text())
    print(f"legacy_api_key_present={'apiKey' in data and bool(str(data.get('apiKey', '')).strip())}")
PY
```

Expected: boolean only; credential value never appears in terminal log.

- [ ] **Step 3: Build, sign, install bằng project-required script**

```bash
./install-app.sh
```

Expected decisive lines:

```text
Version: <version> (build <build>)
flags=0x10000(runtime)
Installed: /Applications/NTranslate.app
```

Record exact version/build for final report.

- [ ] **Step 4: Verify signature and runtime flag independently**

```bash
codesign --verify --deep --strict --verbose=2 /Applications/NTranslate.app
codesign -dv --verbose=4 /Applications/NTranslate.app 2>&1 | grep 'flags='
```

Expected: `valid on disk`, `satisfies its Designated Requirement`, và flag chứa `runtime`.

- [ ] **Step 5: Verify migration without exposing key**

```bash
python3 - <<'PY'
import json
from pathlib import Path
p = Path.home() / "Library/Application Support/NTranslate/config.json"
data = json.loads(p.read_text())
mode = oct(p.stat().st_mode & 0o777)
print(f"api_key_field_present={'apiKey' in data}")
print(f"permissions={mode}")
PY
security find-generic-password -s local.ninh.ntranslate -a apiKey >/dev/null \
  && echo 'keychain_item_present=true' \
  || echo 'keychain_item_present=false'
```

Expected sau migration của user có key cũ:

```text
api_key_field_present=false
permissions=0o600
keychain_item_present=true
```

Không dùng `security ... -w`, vì option đó in secret.

- [ ] **Step 6: Manual Settings smoke test**

1. Click status-bar icon, chọn `Settings…`.
2. Xác nhận bốn tab hiện đủ field và API Key bị che.
3. Sửa Model thành giá trị tạm, thêm rồi xóa một language, sửa một prompt, bấm Revert; xác nhận mọi field quay lại snapshot lúc mở.
4. Sửa Model, bấm Save; xác nhận window đóng và translation kế tiếp dùng config mới mà không cần Reload.
5. Mở lại Settings; xác nhận giá trị persisted.
6. Xóa API key rồi Save; xác nhận app báo `API key is empty` và không crash.
7. Nhập lại API key rồi Save; xác nhận translation hoạt động.
8. Mở `config.json`; xác nhận không có `apiKey`.
9. Đóng/mở app; xác nhận API key vẫn hoạt động từ Keychain.

- [ ] **Step 7: Final security regression checks**

```bash
grep -R 'config\.apiKey\|Open Config File\|Reload Config' Sources Tests || true
grep -R 'disable-library-validation\|allow-unsigned-executable-memory' . \
  --exclude-dir=.git --exclude-dir=.build --exclude='*.md' || true
git diff --check
git status --short
```

Expected: hai security greps không có output; `git diff --check` không có output. `git status` chỉ chứa thay đổi thuộc plan/task và các thay đổi có sẵn từ trước không bị chạm.

- [ ] **Step 8: Final report**

Báo ngắn gọn:

- API key đã migrate sang Keychain và plaintext field đã bị xóa.
- Settings UI quản lý toàn bộ config.
- `config.json` có mode `0600`.
- Hardened Runtime flag đã được xác minh.
- `swift test` result.
- Version/build chính xác từ `./install-app.sh`.

Không commit/push nếu user chưa yêu cầu.

---

## Self-Review

- Spec coverage: full Settings UI, Keychain, automatic plaintext migration, secure file permissions, Hardened Runtime, tests, install verification đều có task riêng.
- Scope giữ tối thiểu: không App Sandbox, không Developer ID/notarization, không dependency, không custom design system.
- Failure safety: Keychain migration chỉ xóa plaintext sau khi secure write thành công; Settings save rollback key nếu config write fail.
- Type consistency: `APIKeyStore`, `AppConfig.write`, `AppConfig.migrateLegacyAPIKey`, `SettingsWindowController.SaveHandler`, và `setupIssues(apiKey:...)` dùng cùng signature xuyên suốt.
- Rollback caveat: bản app cũ sẽ đọc được JSON nhưng không thấy `apiKey`; user phải nhập lại key nếu downgrade. Đây là hành vi đã chọn.
