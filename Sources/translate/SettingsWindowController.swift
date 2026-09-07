import AppKit

/// One editable hotkey (letter popup + modifier checkboxes).
@MainActor
final class HotkeyFields {
    let popup = NSPopUpButton()
    let option = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    let command = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    let control = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    let shift = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)

    func configure() {
        popup.addItems(withTitles: (65...90).compactMap { UnicodeScalar($0).map(String.init) })
    }

    func makeRow() -> NSStackView {
        let row = NSStackView(views: [popup, option, command, control, shift])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    func populate(_ hotkey: AppConfig.Hotkey) {
        popup.selectItem(withTitle: hotkey.key.uppercased())
        option.state = hotkey.option ? .on : .off
        command.state = hotkey.command ? .on : .off
        control.state = hotkey.control ? .on : .off
        shift.state = hotkey.shift ? .on : .off
    }

    func collect(fallbackKey: String) -> AppConfig.Hotkey {
        AppConfig.Hotkey(
            key: popup.titleOfSelectedItem ?? fallbackKey,
            option: option.state == .on,
            command: command.state == .on,
            control: control.state == .on,
            shift: shift.state == .on
        )
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// One sidebar row: title, SF Symbol, search keywords, and the pane shown on the right.
private final class SettingsSidebarItem: NSObject {
    let title: String
    let symbolName: String
    let keywords: [String]
    let contentView: NSView

    init(title: String, symbolName: String, keywords: [String], contentView: NSView) {
        self.title = title
        self.symbolName = symbolName
        self.keywords = keywords
        self.contentView = contentView
    }

    func matches(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        if title.localizedCaseInsensitiveContains(needle) { return true }
        return keywords.contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSplitViewDelegate {
    typealias SaveHandler = (AppConfig, String, String) throws -> Void

    private var originalConfig: AppConfig
    private var originalAPIKey: String
    private var originalSpeechAPIKey: String
    var workingConfig: AppConfig
    private let onSave: SaveHandler

    private let apiKeyField = NSSecureTextField()
    private let apiBaseURLField = NSTextField()
    private let apiSpeechURLField = NSTextField()
    private let speechProviderPopup = NSPopUpButton()
    private let speechAPIKeyField = NSSecureTextField()
    private let modelField = NSTextField()
    private let themePopup = NSPopUpButton()
    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let nativeLanguagePopup = NSPopUpButton()
    private let maxTranslateLengthField = NSTextField()
    private let dailyReviewLimitField = NSTextField()

    private let systemPromptView = NSTextView()
    private let learnPromptView = NSTextView()
    private let sentenceLearnPromptView = NSTextView()
    private let grammarPromptView = NSTextView()
    private let imagePromptView = NSTextView()
    private let qaPromptView = NSTextView()
    private let weavePromptView = NSTextView()

    /// Each editable prompt paired with the default this build ships, so the Prompts tab can offer
    /// "Sync with app prompt" when an update changes a default the user never customized.
    private var promptSyncButtons: [ObjectIdentifier: NSButton] = [:]
    private var promptDefaults: [ObjectIdentifier: String] = [:]

    let languagesTable = NSTableView()
    let targetLanguagesTable = NSTableView()

    private let speechSlowRatePopup = NSPopUpButton()
    /// Rates offered by the "Slow speed" popup, matching the tortoise buttons.
    private static let speechSlowRates: [Float] = [0.25, 0.3, 0.4, 0.5, 0.6, 0.75]

    private let autoPrefetchSpeechCheckbox = NSButton(
        checkboxWithTitle: "Prefetch speech automatically",
        target: nil,
        action: nil
    )
    /// Rebuilt whenever the Languages list changes; one row per language plus a fallback row.
    private var speechModelFields: [String: NSTextField] = [:]
    /// Single Speech pane grid so static and runtime rows share one 150pt label column.
    private var speechGrid: NSGridView?
    /// API-only grid rows (URL, key, fallback) hidden when the native provider is selected.
    private var speechAPIRows: [NSGridRow] = []
    private var speechModelRows: [NSGridRow] = []
    private var nativeVoiceRows: [NSGridRow] = []
    private let speechFallbackModelField = NSTextField()
    private let historyDirectoryField = NSTextField()
    private let densityPopup = NSPopUpButton()
    private let widthField = NSTextField()
    private let heightField = NSTextField()
    private let autoCopyCheckbox = NSButton(
        checkboxWithTitle: "Copy translation automatically",
        target: nil,
        action: nil
    )
    private let simulateCopyCheckbox = NSButton(
        checkboxWithTitle: "Paste translation into source app",
        target: nil,
        action: nil
    )
    private let hotkeyFields = HotkeyFields()
    private let copyTranslateHotkeyFields = HotkeyFields()
    private let learnHotkeyFields = HotkeyFields()
    private let proofreadHotkeyFields = HotkeyFields()
    private let ocrHotkeyFields = HotkeyFields()
    private let testConnectionButton = NSButton(title: "Test connection", target: nil, action: nil)
    private let testConnectionStatus = NSTextField(labelWithString: "")
    private let hotkeyConflictLabel = NSTextField(wrappingLabelWithString: "")

    private let sidebarWidth: CGFloat = 180
    private let sidebarView = NSVisualEffectView()
    private let detailHost = NSView()
    private let sidebarOutline = NSOutlineView()
    private let sidebarSearchField = NSSearchField()
    private var allPanes: [SettingsSidebarItem] = []
    private var visiblePanes: [SettingsSidebarItem] = []

    init(config: AppConfig, apiKey: String, speechAPIKey: String, onSave: @escaping SaveHandler) {
        originalConfig = config
        originalAPIKey = apiKey
        originalSpeechAPIKey = speechAPIKey
        workingConfig = config
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "NTranslate Settings"
        window.setFrameAutosaveName("NTranslateSettingsWindow")
        window.minSize = NSSize(width: 680, height: 560)

        super.init(window: window)
        configureContent()
        populate(config: config, apiKey: apiKey, speechAPIKey: speechAPIKey)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showSettings(config: AppConfig, apiKey: String, speechAPIKey: String) {
        originalConfig = config
        originalAPIKey = apiKey
        originalSpeechAPIKey = speechAPIKey
        workingConfig = config
        populate(config: config, apiKey: apiKey, speechAPIKey: speechAPIKey)
        showWindow(nil)
        window?.center()
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    private func configureContent() {
        apiKeyField.placeholderString = "Stored in macOS Keychain"
        maxTranslateLengthField.formatter = integerFormatter(minimum: 1)
        dailyReviewLimitField.formatter = integerFormatter(minimum: 1)
        dailyReviewLimitField.toolTip = "Maximum cards per review session. New words fill any slots left over by due reviews."
        widthField.formatter = integerFormatter(minimum: 1)
        heightField.formatter = integerFormatter(minimum: 1)
        [hotkeyFields, copyTranslateHotkeyFields, learnHotkeyFields, proofreadHotkeyFields, ocrHotkeyFields].forEach { $0.configure() }

        [systemPromptView, learnPromptView, sentenceLearnPromptView, grammarPromptView, imagePromptView, qaPromptView, weavePromptView].forEach {
            $0.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            $0.isRichText = false
            $0.isAutomaticQuoteSubstitutionEnabled = false
            $0.isAutomaticDashSubstitutionEnabled = false
        }

        configureLanguageTable(languagesTable, identifier: "languages")
        configureLanguageTable(targetLanguagesTable, identifier: "targetLanguages")

        allPanes = makeAllPanes()
        visiblePanes = allPanes
        installPaneViews()

        let split = makeSettingsSplitView()
        sidebarOutline.reloadData()
        if !visiblePanes.isEmpty {
            sidebarOutline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        displaySelectedPane()

        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancel.keyEquivalent = "\u{1b}"
        let revert = NSButton(title: "Revert", target: self, action: #selector(revertClicked))
        let save = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [revert, spacer, cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let root = NSStackView(views: [split, buttons])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        split.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        split.setContentHuggingPriority(.defaultLow, for: .vertical)
        split.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        buttons.setContentHuggingPriority(.required, for: .vertical)

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        window?.contentView = content
    }

    private func makeAllPanes() -> [SettingsSidebarItem] {
        [
            SettingsSidebarItem(
                title: "General",
                symbolName: "gearshape",
                keywords: ["Theme", "Panel Width × Height", "Density", "Copy", "Paste"],
                contentView: makeGeneralView()
            ),
            SettingsSidebarItem(
                title: "Translation",
                symbolName: "globe",
                keywords: ["Source Language", "Target Language", "Native Language", "Maximum Length", "Daily Reviews"],
                contentView: makeTranslationView()
            ),
            SettingsSidebarItem(
                title: "Languages",
                symbolName: "character.book.closed",
                keywords: ["Source Languages", "Target Languages"],
                contentView: makeLanguagesView()
            ),
            SettingsSidebarItem(
                title: "API",
                symbolName: "key",
                keywords: ["API Base URL", "API Key", "Model", "Connection", "Test connection"],
                contentView: makeAPIView()
            ),
            SettingsSidebarItem(
                title: "Speech",
                symbolName: "speaker.wave.2",
                keywords: ["Speech Provider", "Speech URL", "Speech API Key", "Fallback Model", "Slow speed", "Prefetch speech"],
                contentView: makeSpeechView()
            ),
            SettingsSidebarItem(
                title: "Shortcuts",
                symbolName: "keyboard",
                keywords: [
                    "Global Hotkey",
                    "Copy & Translate Hotkey",
                    "Learn Hotkey",
                    "Proofread Hotkey",
                    "OCR Translate Hotkey",
                    "Hotkey Conflicts",
                ],
                contentView: makeShortcutsView()
            ),
            SettingsSidebarItem(
                title: "Prompts",
                symbolName: "text.alignleft",
                keywords: [
                    "System Prompt",
                    "Learn Word Prompt",
                    "Learn Sentence Prompt",
                    "Grammar Prompt",
                    "Image Prompt",
                    "Q&A Prompt",
                ],
                contentView: makePromptsView()
            ),
            SettingsSidebarItem(
                title: "History & Sync",
                symbolName: "clock.arrow.circlepath",
                keywords: ["History Folder"],
                contentView: makeHistoryView()
            ),
        ]
    }

    private func makeGeneralView() -> NSView {
        themePopup.removeAllItems()
        AppTheme.allCases.forEach { themePopup.addItem(withTitle: $0.displayName) }

        densityPopup.removeAllItems()
        densityPopup.addItems(withTitles: ["Normal", "Compact"])

        let dimensions = NSStackView(views: [widthField, NSTextField(labelWithString: "×"), heightField])
        dimensions.orientation = .horizontal
        dimensions.spacing = 8
        let densityHint = wrappingHint("Compact trims padding and pane headers to fit more text.")
        let densityRow = NSStackView(views: [densityPopup, densityHint])
        densityRow.orientation = .vertical
        densityRow.alignment = .leading
        densityRow.spacing = 4
        densityRow.setContentHuggingPriority(.defaultLow, for: .horizontal)
        densityPopup.widthAnchor.constraint(equalToConstant: 160).isActive = true
        densityHint.widthAnchor.constraint(equalTo: densityRow.widthAnchor).isActive = true

        widthField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 90).isActive = true

        return scrollableForm([
            ("Theme", themePopup),
            ("Panel Width × Height", dimensions),
            ("Density", densityRow),
            ("Copy", autoCopyCheckbox),
            ("Paste", simulateCopyCheckbox),
        ])
    }

    private func makeTranslationView() -> NSView {
        scrollableForm([
            ("Source Language", sourceLanguagePopup),
            ("Target Language", targetLanguagePopup),
            ("Native Language", nativeLanguagePopup),
            ("Maximum Length", maxTranslateLengthField),
            ("Daily Reviews", dailyReviewLimitField),
        ])
    }

    private func makePromptsView() -> NSView {
        let sections: [NSView] = [
            promptSection("System Prompt", systemPromptView, appDefault: AppConfig.default.systemPrompt, variables: "{{config.sourceLang}}, {{config.targetLang}}, {{config.nativeLang}}"),
            promptSection("Learn Word Prompt", learnPromptView, appDefault: AppConfig.defaultLearnPrompt, variables: "{{config.sourceLang}}, {{config.targetLang}}"),
            promptSection("Learn Sentence Prompt", sentenceLearnPromptView, appDefault: AppConfig.defaultSentenceLearnPrompt, variables: "{{config.sourceLang}}, {{config.targetLang}}"),
            promptSection("Grammar Prompt", grammarPromptView, appDefault: AppConfig.defaultGrammarPrompt, variables: "{{lang}}, {{config.nativeLang}}"),
            promptSection("Image Prompt", imagePromptView, appDefault: AppConfig.defaultImagePrompt, variables: "{{config.targetLang}}, {{config.alternateLang}}, {{config.sourceLang}}, {{config.nativeLang}}"),
            promptSection("Q&A Prompt", qaPromptView, appDefault: AppConfig.defaultQAPrompt, variables: "{{sourceText}}, {{translatedText}}, {{config.sourceLang}}, {{config.targetLang}}"),
            promptSection("Reading Passage Prompt", weavePromptView, appDefault: AppConfig.defaultWeavePrompt, variables: "{{words}}, {{config.sourceLang}}, {{config.targetLang}}"),
        ]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        // `.width` alignment only makes the sections equal to each other; without this they keep
        // their natural width and leave a gap when the stack is stretched to the scroll view.
        for section in sections {
            section.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -(stack.edgeInsets.left + stack.edgeInsets.right)
            ).isActive = true
        }

        let scroll = scrollView(for: stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    private func makeLanguagesView() -> NSView {
        let sourceButtons = NSStackView(views: [
            NSButton(title: "Add", target: self, action: #selector(addSourceLanguage)),
            NSButton(title: "Remove", target: self, action: #selector(removeSourceLanguage)),
        ])
        let targetButtons = NSStackView(views: [
            NSButton(title: "Add", target: self, action: #selector(addTargetLanguage)),
            NSButton(title: "Remove", target: self, action: #selector(removeTargetLanguage)),
        ])

        let sourceGroup = languageGroup(
            title: "Source Languages",
            table: languagesTable,
            buttons: sourceButtons
        )
        let targetGroup = languageGroup(
            title: "Target Languages",
            table: targetLanguagesTable,
            buttons: targetButtons
        )
        let groups = NSStackView(views: [sourceGroup, targetGroup])
        groups.orientation = .horizontal
        groups.distribution = .fillEqually
        groups.spacing = 16
        groups.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(groups)
        NSLayoutConstraint.activate([
            groups.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            groups.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            groups.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            groups.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        return content
    }

    private func makeAPIView() -> NSView {
        testConnectionButton.target = self
        testConnectionButton.action = #selector(testConnectionClicked)
        testConnectionStatus.font = .systemFont(ofSize: 11)
        testConnectionStatus.textColor = .secondaryLabelColor
        testConnectionStatus.usesSingleLineMode = false
        testConnectionStatus.lineBreakMode = .byWordWrapping
        testConnectionStatus.maximumNumberOfLines = 2
        testConnectionStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let testRow = NSStackView(views: [testConnectionButton, testConnectionStatus])
        testRow.orientation = .horizontal
        testRow.spacing = 8
        testConnectionStatus.setContentHuggingPriority(.defaultLow, for: .horizontal)

        return scrollableForm([
            ("API Base URL", apiBaseURLField),
            ("API Key", apiKeyField),
            ("Model", modelField),
            ("Connection", testRow),
        ])
    }

    private func makeSpeechView() -> NSView {
        speechProviderPopup.removeAllItems()
        AppConfig.SpeechProvider.allCases.forEach { speechProviderPopup.addItem(withTitle: $0.displayName) }
        speechProviderPopup.target = self
        speechProviderPopup.action = #selector(speechProviderChanged)
        speechAPIKeyField.placeholderString = "Leave empty to reuse the API Key"

        let grid = makeFormGrid()
        speechGrid = grid
        addFormRow(grid, "Speech Provider", speechProviderPopup)
        let speechURLRow = addFormRow(grid, "Speech URL", apiSpeechURLField)
        let speechAPIKeyRow = addFormRow(grid, "Speech API Key", speechAPIKeyField)
        let speechFallbackModelRow = addFormRow(grid, "Fallback Model", speechFallbackModelField)
        speechSlowRatePopup.removeAllItems()
        Self.speechSlowRates.forEach { speechSlowRatePopup.addItem(withTitle: String(format: "%.2gx", $0)) }
        addFormRow(grid, "Slow speed", speechSlowRatePopup)
        addFormRow(grid, "Prefetch speech", autoPrefetchSpeechCheckbox)
        speechAPIRows = [speechURLRow, speechAPIKeyRow, speechFallbackModelRow]
        return wrapFormGrid(grid)
    }

    private func makeShortcutsView() -> NSView {
        hotkeyConflictLabel.font = .systemFont(ofSize: 11)
        hotkeyConflictLabel.textColor = .systemOrange
        hotkeyConflictLabel.isHidden = true
        hotkeyConflictLabel.maximumNumberOfLines = 3
        hotkeyConflictLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wireHotkeyConflictWatch()

        return scrollableForm([
            ("Global Hotkey", hotkeyFields.makeRow()),
            ("Copy & Translate Hotkey", copyTranslateHotkeyFields.makeRow()),
            ("Learn Hotkey", learnHotkeyFields.makeRow()),
            ("Proofread Hotkey", proofreadHotkeyFields.makeRow()),
            ("OCR Translate Hotkey", ocrHotkeyFields.makeRow()),
            ("Hotkey Conflicts", hotkeyConflictLabel),
        ])
    }

    private func makeHistoryView() -> NSView {
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseHistoryDirectory))
        let historyFields = NSStackView(views: [historyDirectoryField, choose])
        historyFields.orientation = .horizontal
        historyFields.spacing = 8

        // The label column is a fixed 150pt, so the sync hint goes under the field instead.
        let historyHint = wrappingHint("Point at a folder your Macs already share (iCloud Drive, Dropbox, Syncthing) to sync history across devices.")
        let historyRow = NSStackView(views: [historyFields, historyHint])
        historyRow.orientation = .vertical
        historyRow.alignment = .leading
        historyRow.spacing = 4
        historyRow.setContentHuggingPriority(.defaultLow, for: .horizontal)
        historyHint.widthAnchor.constraint(equalTo: historyRow.widthAnchor).isActive = true

        return scrollableForm([
            ("History Folder", historyRow),
        ])
    }

    /// Languages the user can pick anywhere, minus the auto-detect pseudo-language.
    private func speechModelLanguages() -> [String] {
        var seen: Set<String> = []
        return (workingConfig.languages + workingConfig.targetLanguages).filter {
            $0 != LanguageDetector.autoDetect && seen.insert($0).inserted
        }
    }

    private func rebuildSpeechModelRows() {
        let languages = speechModelLanguages()
        // Keep whatever the user already typed for languages that survived the edit.
        var retained: [String: NSTextField] = [:]
        for language in languages {
            retained[language] = speechModelFields[language] ?? NSTextField()
        }
        speechModelFields = retained

        guard let grid = speechGrid, speechAPIRows.count >= 3 else { return }
        removeGridRows(speechModelRows, from: grid)
        speechModelRows.removeAll()

        let keyIndex = grid.index(of: speechAPIRows[1])
        guard keyIndex != NSNotFound else { return }
        var insertAt = keyIndex + 1
        let hide = !isAPISpeechProvider
        for language in languages {
            guard let field = speechModelFields[language] else { continue }
            let row = insertFormRow(grid, at: insertAt, "\(language) Model", field)
            row.isHidden = hide
            speechModelRows.append(row)
            insertAt += 1
        }
    }

    private func wrappingHint(_ text: String) -> NSTextField {
        let hint = NSTextField(wrappingLabelWithString: text)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 2
        hint.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return hint
    }

    private func makeFormGrid() -> NSGridView {
        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.rowSpacing = 12
        grid.columnSpacing = 12
        grid.rowAlignment = .firstBaseline
        let labels = grid.column(at: 0)
        labels.xPlacement = .trailing
        labels.width = 150
        let controls = grid.column(at: 1)
        controls.xPlacement = .fill
        return grid
    }

    @discardableResult
    private func addFormRow(_ grid: NSGridView, _ label: String, _ control: NSView) -> NSGridRow {
        insertFormRow(grid, at: grid.numberOfRows, label, control)
    }

    @discardableResult
    private func insertFormRow(_ grid: NSGridView, at index: Int, _ label: String, _ control: NSView) -> NSGridRow {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.lineBreakMode = .byTruncatingTail
        title.preferredMaxLayoutWidth = 150
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return grid.insertRow(at: index, with: [title, control])
    }

    private func removeGridRows(_ rows: [NSGridRow], from grid: NSGridView) {
        for row in rows.reversed() {
            let index = grid.index(of: row)
            guard index != NSNotFound else { continue }
            // NSGridView.removeRow(at:) leaves the cell views in the grid; without this they stay
            // parked at their old frames and draw on top of the rows that replace them.
            for cell in 0..<row.numberOfCells {
                row.cell(at: cell).contentView?.removeFromSuperview()
            }
            grid.removeRow(at: index)
        }
    }

    private func scrollableForm(_ rows: [(String, NSView)]) -> NSView {
        let grid = makeFormGrid()
        for (label, control) in rows {
            addFormRow(grid, label, control)
        }
        return wrapFormGrid(grid)
    }

    private func wrapFormGrid(_ grid: NSGridView) -> NSView {
        grid.translatesAutoresizingMaskIntoConstraints = false
        let container = FlippedDocumentView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20),
            container.heightAnchor.constraint(greaterThanOrEqualTo: grid.heightAnchor, constant: 40),
        ])
        let scroll = scrollView(for: container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            container.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        return scroll
    }

    private func promptSection(_ title: String, _ textView: NSTextView, appDefault: String, variables: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        let varsHint = wrappingHint("Variables: \(variables)")

        let syncButton = NSButton(title: "Sync with app prompt", target: self, action: #selector(syncPromptWithApp(_:)))
        syncButton.controlSize = .small
        syncButton.font = .systemFont(ofSize: 11)
        syncButton.bezelStyle = .rounded
        syncButton.toolTip = "Replace this prompt with the one shipped in this version of NTranslate"
        syncButton.isHidden = true
        promptSyncButtons[ObjectIdentifier(textView)] = syncButton
        promptDefaults[ObjectIdentifier(textView)] = appDefault
        textView.delegate = self

        let header = NSStackView(views: [label, NSView(), syncButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        varsHint.setContentCompressionResistancePriority(.required, for: .vertical)

        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scroll = scrollView(for: textView)
        scroll.heightAnchor.constraint(equalToConstant: 160).isActive = true
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.setContentHuggingPriority(.required, for: .vertical)
        scroll.setContentCompressionResistancePriority(.required, for: .vertical)
        let section = NSStackView(views: [header, varsHint, scroll])
        section.orientation = .vertical
        section.alignment = .width
        section.spacing = 6
        header.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        varsHint.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    /// A prompt is out of sync when it differs from this build's default — that is either an update
    /// that changed the default, or a customization the user made on purpose. Either way the button
    /// only offers the swap; it never applies one behind their back.
    nonisolated static func promptNeedsSync(current: String, appDefault: String) -> Bool {
        current.trimmingCharacters(in: .whitespacesAndNewlines)
            != appDefault.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshPromptSyncButtons() {
        for (key, button) in promptSyncButtons {
            guard let appDefault = promptDefaults[key],
                  let textView = promptView(for: key)
            else { continue }
            button.isHidden = !Self.promptNeedsSync(current: textView.string, appDefault: appDefault)
        }
    }

    private func promptView(for key: ObjectIdentifier) -> NSTextView? {
        [systemPromptView, learnPromptView, sentenceLearnPromptView, grammarPromptView, imagePromptView, qaPromptView, weavePromptView]
            .first { ObjectIdentifier($0) == key }
    }

    @objc private func syncPromptWithApp(_ sender: NSButton) {
        guard let key = promptSyncButtons.first(where: { $0.value === sender })?.key,
              let appDefault = promptDefaults[key],
              let textView = promptView(for: key)
        else { return }
        textView.string = appDefault
        refreshPromptSyncButtons()
    }

    func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView,
              promptSyncButtons[ObjectIdentifier(textView)] != nil
        else { return }
        refreshPromptSyncButtons()
    }

    private func populate(config: AppConfig, apiKey: String, speechAPIKey: String) {
        workingConfig = config
        apiKeyField.stringValue = apiKey
        speechAPIKeyField.stringValue = speechAPIKey
        speechProviderPopup.selectItem(withTitle: config.speechProvider.displayName)
        updateSpeechProviderRows()
        apiBaseURLField.stringValue = config.apiBaseURL
        apiSpeechURLField.stringValue = config.apiSpeechURL
        modelField.stringValue = config.model
        themePopup.selectItem(withTitle: config.theme.displayName)
        maxTranslateLengthField.integerValue = config.maxTranslateLength
        dailyReviewLimitField.integerValue = config.learning.dailyReviewLimit
        systemPromptView.string = config.systemPrompt
        learnPromptView.string = config.learnPrompt
        sentenceLearnPromptView.string = config.sentenceLearnPrompt
        grammarPromptView.string = config.grammarPrompt
        imagePromptView.string = config.imagePrompt
        qaPromptView.string = config.qaPrompt
        weavePromptView.string = config.weavePrompt
        refreshPromptSyncButtons()
        let slowIndex = Self.speechSlowRates.firstIndex(of: config.speechSlowRate) ?? Self.speechSlowRates.firstIndex(of: 0.4) ?? 0
        speechSlowRatePopup.selectItem(at: slowIndex)
        autoPrefetchSpeechCheckbox.state = config.autoPrefetchSpeech ? .on : .off
        speechModelFields.removeAll()
        rebuildSpeechModelRows()
        for (language, field) in speechModelFields {
            field.stringValue = config.speechModels[language] ?? ""
        }
        speechFallbackModelField.stringValue = config.speechFallbackModel
        historyDirectoryField.stringValue = config.historyDirectory ?? ""
        densityPopup.selectItem(at: config.ui.density == "compact" ? 1 : 0)
        widthField.doubleValue = config.ui.width
        heightField.doubleValue = config.ui.height
        autoCopyCheckbox.state = config.ui.autoCopy ? .on : .off
        simulateCopyCheckbox.state = config.ui.simulateCopy ? .on : .off
        hotkeyFields.populate(config.hotkey)
        copyTranslateHotkeyFields.populate(config.copyTranslateHotkey)
        learnHotkeyFields.populate(config.learnHotkey)
        proofreadHotkeyFields.populate(config.proofreadHotkey)
        ocrHotkeyFields.populate(config.ocrHotkey)
        languagesTable.reloadData()
        targetLanguagesTable.reloadData()
        reloadLanguagePopups(
            source: config.sourceLang,
            target: config.targetLang,
            native: config.nativeLang
        )
        refreshHotkeyConflicts()
    }

    func reloadLanguagePopups(
        source: String? = nil,
        target: String? = nil,
        native: String? = nil
    ) {
        let sourceSelection = source ?? sourceLanguagePopup.titleOfSelectedItem ?? workingConfig.sourceLang
        let targetSelection = target ?? targetLanguagePopup.titleOfSelectedItem ?? workingConfig.targetLang
        let nativeSelection = native ?? nativeLanguagePopup.titleOfSelectedItem ?? workingConfig.nativeLang

        sourceLanguagePopup.removeAllItems()
        sourceLanguagePopup.addItems(withTitles: workingConfig.languages)
        sourceLanguagePopup.selectItem(withTitle: sourceSelection)
        targetLanguagePopup.removeAllItems()
        targetLanguagePopup.addItems(withTitles: workingConfig.targetLanguages)
        targetLanguagePopup.selectItem(withTitle: targetSelection)
        nativeLanguagePopup.removeAllItems()
        nativeLanguagePopup.addItems(withTitles: workingConfig.targetLanguages)
        if !workingConfig.targetLanguages.contains(nativeSelection) {
            nativeLanguagePopup.addItem(withTitle: nativeSelection)
        }
        nativeLanguagePopup.selectItem(withTitle: nativeSelection)
        rebuildSpeechModelRows()
        rebuildNativeVoiceRows()
    }

    @objc private func speechProviderChanged() {
        updateSpeechProviderRows()
    }

    private var isAPISpeechProvider: Bool {
        let title = speechProviderPopup.titleOfSelectedItem ?? AppConfig.SpeechProvider.api.displayName
        return title != AppConfig.SpeechProvider.native.displayName
    }

    private func updateSpeechProviderRows() {
        let isAPI = isAPISpeechProvider
        for row in speechAPIRows { row.isHidden = !isAPI }
        for row in speechModelRows { row.isHidden = !isAPI }
        for row in nativeVoiceRows { row.isHidden = isAPI }
        if !isAPI { rebuildNativeVoiceRows() }
    }

    /// Shows the resolved voice per language so a missing voice, or a compact one that explains
    /// why a language sounds worse than the API, is visible before the user plays anything.
    private func rebuildNativeVoiceRows() {
        guard let grid = speechGrid, speechAPIRows.count >= 3 else { return }
        removeGridRows(nativeVoiceRows, from: grid)
        nativeVoiceRows.removeAll()

        let fallbackIndex = grid.index(of: speechAPIRows[2])
        guard fallbackIndex != NSNotFound else { return }
        var insertAt = fallbackIndex
        let hide = isAPISpeechProvider
        for language in speechModelLanguages() {
            let description = NativeSpeechEngine.voiceDescription(for: language) ?? "Not installed"
            let value = NSTextField(wrappingLabelWithString: description)
            value.maximumNumberOfLines = 2
            value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            if NativeSpeechEngine.voiceDescription(for: language) == nil {
                value.textColor = .systemOrange
                value.toolTip = "Add a \(language) voice in \(NativeSpeechEngine.voiceSettingsPath)."
            } else {
                value.textColor = .secondaryLabelColor
            }
            let row = insertFormRow(grid, at: insertAt, "\(language) Voice", value)
            row.isHidden = hide
            nativeVoiceRows.append(row)
            insertAt += 1
        }
        let openButton = NSButton(
            title: "Manage Voices\u{2026}", target: self, action: #selector(openVoiceSettings)
        )
        let hint = wrappingHint("Higher-quality voices are a one-time download; playback stays offline.")
        let install = NSStackView(views: [openButton, hint])
        install.orientation = .vertical
        install.alignment = .leading
        install.spacing = 4
        install.setContentHuggingPriority(.defaultLow, for: .horizontal)
        hint.widthAnchor.constraint(equalTo: install.widthAnchor).isActive = true
        let installRow = insertFormRow(grid, at: insertAt, "Install Voices", install)
        installRow.isHidden = hide
        nativeVoiceRows.append(installRow)
    }

    @objc private func openVoiceSettings() {
        guard let url = URL(string: NativeSpeechEngine.voiceSettingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func collectConfig() throws -> AppConfig {
        window?.makeFirstResponder(nil)
        var config = workingConfig
        let providerTitle = speechProviderPopup.titleOfSelectedItem ?? AppConfig.SpeechProvider.api.displayName
        config.speechProvider = AppConfig.SpeechProvider.allCases
            .first { $0.displayName == providerTitle } ?? .api
        config.apiBaseURL = apiBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.apiSpeechURL = apiSpeechURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedThemeTitle = themePopup.titleOfSelectedItem ?? AppTheme.system.displayName
        config.theme = AppTheme.allCases.first(where: { $0.displayName == selectedThemeTitle }) ?? .system
        config.sourceLang = sourceLanguagePopup.titleOfSelectedItem ?? ""
        config.targetLang = targetLanguagePopup.titleOfSelectedItem ?? ""
        config.nativeLang = nativeLanguagePopup.titleOfSelectedItem ?? ""
        config.maxTranslateLength = maxTranslateLengthField.integerValue
        config.learning.dailyReviewLimit = max(1, dailyReviewLimitField.integerValue)
        config.systemPrompt = systemPromptView.string
        config.learnPrompt = learnPromptView.string
        config.sentenceLearnPrompt = sentenceLearnPromptView.string
        config.grammarPrompt = grammarPromptView.string
        config.imagePrompt = imagePromptView.string
        config.qaPrompt = qaPromptView.string
        config.weavePrompt = weavePromptView.string
        let slowRateIndex = speechSlowRatePopup.indexOfSelectedItem
        config.speechSlowRate = Self.speechSlowRates.indices.contains(slowRateIndex) ? Self.speechSlowRates[slowRateIndex] : 0.4
        config.autoPrefetchSpeech = autoPrefetchSpeechCheckbox.state == .on
        config.speechModels = speechModelFields.reduce(into: [:]) { result, entry in
            let value = entry.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result[entry.key] = value }
        }
        config.speechFallbackModel = speechFallbackModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let historyDirectory = historyDirectoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.historyDirectory = historyDirectory.isEmpty ? nil : historyDirectory
        config.ui.density = densityPopup.indexOfSelectedItem == 1 ? "compact" : "normal"
        config.ui.width = widthField.doubleValue
        config.ui.height = heightField.doubleValue
        config.ui.autoCopy = autoCopyCheckbox.state == .on
        config.ui.simulateCopy = simulateCopyCheckbox.state == .on
        config.hotkey = hotkeyFields.collect(fallbackKey: "D")
        config.copyTranslateHotkey = copyTranslateHotkeyFields.collect(fallbackKey: "D")
        config.learnHotkey = learnHotkeyFields.collect(fallbackKey: "L")
        config.proofreadHotkey = proofreadHotkeyFields.collect(fallbackKey: "P")
        config.ocrHotkey = ocrHotkeyFields.collect(fallbackKey: "A")

        let issues = config.validationIssues()
        if !issues.isEmpty { throw SettingsError.validation(issues) }
        return config
    }

    @objc private func saveClicked() {
        refreshHotkeyConflicts()
        if !hotkeyConflictLabel.isHidden {
            present(SettingsError.validation([hotkeyConflictLabel.stringValue]))
            return
        }
        do {
            let config = try collectConfig()
            try onSave(config, apiKeyField.stringValue, speechAPIKeyField.stringValue)
            originalConfig = config
            originalAPIKey = apiKeyField.stringValue
            originalSpeechAPIKey = speechAPIKeyField.stringValue
            workingConfig = config
            close()
        } catch {
            present(error)
        }
    }

    private func wireHotkeyConflictWatch() {
        for fields in [hotkeyFields, copyTranslateHotkeyFields, learnHotkeyFields, proofreadHotkeyFields, ocrHotkeyFields] {
            fields.popup.target = self
            fields.popup.action = #selector(hotkeyFieldsChanged)
            for box in [fields.option, fields.command, fields.control, fields.shift] {
                box.target = self
                box.action = #selector(hotkeyFieldsChanged)
            }
        }
        refreshHotkeyConflicts()
    }

    @objc private func hotkeyFieldsChanged() {
        refreshHotkeyConflicts()
    }

    private func refreshHotkeyConflicts() {
        let entries: [(name: String, hotkey: AppConfig.Hotkey, id: UInt32)] = [
            ("Global hotkey", hotkeyFields.collect(fallbackKey: "D"), 1),
            ("Copy & Translate hotkey", copyTranslateHotkeyFields.collect(fallbackKey: "D"), 2),
            ("Learn hotkey", learnHotkeyFields.collect(fallbackKey: "L"), 3),
            ("Proofread hotkey", proofreadHotkeyFields.collect(fallbackKey: "P"), 4),
            ("OCR Translate hotkey", ocrHotkeyFields.collect(fallbackKey: "A"), 5),
        ]
        let skipped = PopoverIntegrationPolicy.registrableHotkeys(entries).skipped
        if skipped.isEmpty {
            hotkeyConflictLabel.stringValue = ""
            hotkeyConflictLabel.isHidden = true
        } else {
            hotkeyConflictLabel.stringValue = "These hotkeys are duplicates and will not register: \(skipped.joined(separator: ", "))."
            hotkeyConflictLabel.isHidden = false
        }
    }

    @objc private func testConnectionClicked() {
        testConnectionStatus.stringValue = "Testing…"
        testConnectionStatus.textColor = .secondaryLabelColor
        var snapshot = workingConfig
        snapshot.apiBaseURL = apiBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.apiSpeechURL = apiSpeechURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        snapshot.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = apiKeyField.stringValue
        let translator = Translator(config: snapshot, apiKey: key, speechAPIKey: speechAPIKeyField.stringValue)
        translator.testConnection { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success:
                    self.testConnectionStatus.stringValue = "Connection OK"
                    self.testConnectionStatus.textColor = .systemGreen
                case let .failure(error):
                    self.testConnectionStatus.stringValue = PopoverFeedback.userFacingError(error)
                    self.testConnectionStatus.textColor = .systemRed
                }
            }
        }
    }

    @objc private func revertClicked() {
        populate(config: originalConfig, apiKey: originalAPIKey, speechAPIKey: originalSpeechAPIKey)
    }

    @objc private func cancelClicked() {
        close()
    }

    @objc private func chooseHistoryDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        historyDirectoryField.stringValue = url.path
        offerRestore(from: url)
    }

    /// A folder that already carries a config was written by another install of the app, so a fresh
    /// machine can adopt the whole setup instead of retyping it. The API keys are not in there:
    /// they live in the Keychain and still have to be entered once.
    private func offerRestore(from url: URL) {
        let mirror = url.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: mirror.path),
              case let .loaded(restored) = AppConfig.loadOutcome(at: mirror.path)
        else { return }

        let alert = NSAlert()
        alert.messageText = "Restore settings from this folder?"
        alert.informativeText = "This folder holds settings saved by NTranslate, including prompts, "
            + "hotkeys and speech models. Restoring replaces what is on screen. API keys live in the "
            + "Keychain and are not restored."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Keep Current")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        // The folder is the one the user just picked, whatever path the other machine wrote.
        var adopted = restored
        adopted.historyDirectory = url.path
        populate(config: adopted, apiKey: apiKeyField.stringValue, speechAPIKey: speechAPIKeyField.stringValue)
    }

    private func makeSettingsSplitView() -> NSSplitView {
        configureSidebar()
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.delegate = self
        split.addSubview(sidebarView)
        split.addSubview(detailHost)
        return split
    }

    private func configureSidebar() {
        sidebarView.material = .sidebar
        sidebarView.blendingMode = .behindWindow
        sidebarView.state = .followsWindowActiveState

        sidebarSearchField.placeholderString = "Search settings"
        sidebarSearchField.sendsSearchStringImmediately = true
        sidebarSearchField.sendsWholeSearchString = false
        sidebarSearchField.target = self
        sidebarSearchField.action = #selector(sidebarSearchChanged)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("pane"))
        sidebarOutline.addTableColumn(column)
        sidebarOutline.outlineTableColumn = column
        sidebarOutline.headerView = nil
        sidebarOutline.allowsEmptySelection = true
        sidebarOutline.allowsMultipleSelection = false
        sidebarOutline.style = .sourceList
        sidebarOutline.rowSizeStyle = .default
        sidebarOutline.indentationPerLevel = 0
        sidebarOutline.backgroundColor = .clear
        sidebarOutline.focusRingType = .none
        sidebarOutline.dataSource = self
        sidebarOutline.delegate = self

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = sidebarOutline

        sidebarSearchField.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(sidebarSearchField)
        sidebarView.addSubview(scroll)
        NSLayoutConstraint.activate([
            sidebarSearchField.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 8),
            sidebarSearchField.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -8),
            sidebarSearchField.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: sidebarSearchField.bottomAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor),
        ])
    }

    private func installPaneViews() {
        for pane in allPanes {
            let view = pane.contentView
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isHidden = true
            detailHost.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: detailHost.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: detailHost.trailingAnchor),
                view.topAnchor.constraint(equalTo: detailHost.topAnchor),
                view.bottomAnchor.constraint(equalTo: detailHost.bottomAnchor),
            ])
        }
    }

    private func displaySelectedPane() {
        let pane: SettingsSidebarItem?
        let row = sidebarOutline.selectedRow
        if visiblePanes.indices.contains(row) {
            pane = visiblePanes[row]
        } else {
            pane = nil
        }
        for item in allPanes {
            item.contentView.isHidden = item !== pane
        }
    }

    @objc private func sidebarSearchChanged() {
        let selected = visiblePanes.indices.contains(sidebarOutline.selectedRow)
            ? visiblePanes[sidebarOutline.selectedRow]
            : nil
        visiblePanes = allPanes.filter { $0.matches(sidebarSearchField.stringValue) }
        sidebarOutline.reloadData()
        if let selected, let index = visiblePanes.firstIndex(where: { $0 === selected }) {
            sidebarOutline.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !visiblePanes.isEmpty {
            sidebarOutline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        } else {
            sidebarOutline.deselectAll(nil)
        }
        displaySelectedPane()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        item == nil ? visiblePanes.count : 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        visiblePanes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        false
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let pane = item as? SettingsSidebarItem else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("SettingsPane")
        let cell: NSTableCellView
        if let reused = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = identifier
            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cell.addSubview(imageView)
            cell.addSubview(textField)
            cell.imageView = imageView
            cell.textField = textField
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 18),
                imageView.heightAnchor.constraint(equalToConstant: 18),
                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = pane.title
        cell.imageView?.image = NSImage(systemSymbolName: pane.symbolName, accessibilityDescription: pane.title)
        cell.imageView?.contentTintColor = .secondaryLabelColor
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        displaySelectedPane()
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        false
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        sidebarWidth
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        sidebarWidth
    }

    func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
        .zero
    }

    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
        let divider = splitView.dividerThickness
        let height = splitView.bounds.height
        let width = splitView.bounds.width
        sidebarView.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: height)
        detailHost.frame = NSRect(x: sidebarWidth + divider, y: 0, width: max(0, width - sidebarWidth - divider), height: height)
    }

    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        if let window { alert.beginSheetModal(for: window) }
    }
}

private enum SettingsError: LocalizedError {
    case validation([String])

    var errorDescription: String? {
        switch self {
        case let .validation(issues): issues.joined(separator: "\n")
        }
    }
}
