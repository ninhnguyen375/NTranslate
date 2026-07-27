import AppKit

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    typealias SaveHandler = (AppConfig, String) throws -> Void

    private var originalConfig: AppConfig
    private var originalAPIKey: String
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

    private let autoPrefetchSpeechCheckbox = NSButton(
        checkboxWithTitle: "Prefetch speech automatically",
        target: nil,
        action: nil
    )
    private let speechSourceModelField = NSTextField()
    private let speechSourceModelVietnameseField = NSTextField()
    private let speechSourceModelChineseField = NSTextField()
    private let speechTargetModelField = NSTextField()
    private let historyDirectoryField = NSTextField()
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
    private let hotkeyPopup = NSPopUpButton()
    private let optionCheckbox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let commandCheckbox = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    private let controlCheckbox = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    private let shiftCheckbox = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)

    init(config: AppConfig, apiKey: String, onSave: @escaping SaveHandler) {
        originalConfig = config
        originalAPIKey = apiKey
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
        populate(config: config, apiKey: apiKey)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showSettings(config: AppConfig, apiKey: String) {
        originalConfig = config
        originalAPIKey = apiKey
        workingConfig = config
        populate(config: config, apiKey: apiKey)
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
        cancel.keyEquivalent = "\u{1b}"
        let revert = NSButton(title: "Revert", target: self, action: #selector(revertClicked))
        let save = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        save.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [revert, spacer, cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let root = NSStackView(views: [tabs, buttons])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 12
        root.translatesAutoresizingMaskIntoConstraints = false
        tabs.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        tabs.setContentHuggingPriority(.defaultLow, for: .vertical)
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

    private func makeGeneralView() -> NSView {
        return scrollableForm([
            labeledRow("API Key", apiKeyField),
            labeledRow("API Base URL", apiBaseURLField),
            labeledRow("Speech URL", apiSpeechURLField),
            labeledRow("Model", modelField),
            labeledRow("Source Language", sourceLanguagePopup),
            labeledRow("Target Language", targetLanguagePopup),
            labeledRow("Native Language", nativeLanguagePopup),
            labeledRow("Maximum Length", maxTranslateLengthField),
        ])
    }

    private func makePromptsView() -> NSView {
        let stack = NSStackView(views: [
            promptSection("System Prompt", systemPromptView),
            promptSection("Learn Word Prompt", learnPromptView),
            promptSection("Learn Sentence Prompt", sentenceLearnPromptView),
            promptSection("Grammar Prompt", grammarPromptView),
        ])
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = scrollView(for: stack)
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
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

    private func makeAdvancedView() -> NSView {
        let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseHistoryDirectory))
        let historyRow = NSStackView(views: [historyDirectoryField, choose])
        historyRow.orientation = .horizontal
        historyRow.spacing = 8

        let dimensions = NSStackView(views: [widthField, NSTextField(labelWithString: "×"), heightField])
        dimensions.orientation = .horizontal
        dimensions.spacing = 8
        widthField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 90).isActive = true

        let hotkey = NSStackView(views: [
            hotkeyPopup,
            optionCheckbox,
            commandCheckbox,
            controlCheckbox,
            shiftCheckbox,
        ])
        hotkey.orientation = .horizontal
        hotkey.spacing = 8

        return scrollableForm([
            labeledRow("Source Speech Model", speechSourceModelField),
            labeledRow("Vietnamese Model", speechSourceModelVietnameseField),
            labeledRow("Chinese Model", speechSourceModelChineseField),
            labeledRow("Target Speech Model", speechTargetModelField),
            labeledRow("Speech", autoPrefetchSpeechCheckbox),
            labeledRow("History Directory", historyRow),
            labeledRow("Panel Width × Height", dimensions),
            labeledRow("Copy", autoCopyCheckbox),
            labeledRow("Paste", simulateCopyCheckbox),
            labeledRow("Global Hotkey", hotkey),
        ])
    }

    private func tab(title: String, view: NSView) -> NSTabViewItem {
        let item = NSTabViewItem()
        item.label = title
        item.view = view
        return item
    }

    private func labeledRow(_ label: String, _ control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.widthAnchor.constraint(equalToConstant: 150).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func scrollableForm(_ rows: [NSView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = scrollView(for: stack)
        stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }

    private func promptSection(_ title: String, _ textView: NSTextView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        let scroll = scrollView(for: textView)
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        let section = NSStackView(views: [label, scroll])
        section.orientation = .vertical
        section.alignment = .width
        section.spacing = 6
        scroll.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
        return section
    }

    private func languageGroup(title: String, table: NSTableView, buttons: NSStackView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        let scroll = scrollView(for: table)
        let group = NSStackView(views: [label, scroll, buttons])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 8
        scroll.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return group
    }

    private func scrollView(for documentView: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = documentView
        return scroll
    }

    private func integerFormatter(minimum: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: minimum)
        return formatter
    }

    private func configureLanguageTable(_ table: NSTableView, identifier: String) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = "Language"
        table.addTableColumn(column)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
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
        field.delegate = self
        return field
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field.identifier?.rawValue == "languages" || field.identifier?.rawValue == "targetLanguages"
        else { return }
        updateLanguage(field)
    }

    private func updateLanguage(_ field: NSTextField) {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if field.identifier?.rawValue == "languages", workingConfig.languages.indices.contains(field.tag) {
            workingConfig.languages[field.tag] = value
        } else if workingConfig.targetLanguages.indices.contains(field.tag) {
            workingConfig.targetLanguages[field.tag] = value
        }
        reloadLanguagePopups()
    }

    @objc private func addSourceLanguage() {
        workingConfig.languages.append("New Language")
        languagesTable.reloadData()
        let row = workingConfig.languages.count - 1
        languagesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        languagesTable.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func removeSourceLanguage() {
        guard workingConfig.languages.indices.contains(languagesTable.selectedRow) else { return }
        workingConfig.languages.remove(at: languagesTable.selectedRow)
        languagesTable.reloadData()
        reloadLanguagePopups()
    }

    @objc private func addTargetLanguage() {
        workingConfig.targetLanguages.append("New Language")
        targetLanguagesTable.reloadData()
        let row = workingConfig.targetLanguages.count - 1
        targetLanguagesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        targetLanguagesTable.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func removeTargetLanguage() {
        guard workingConfig.targetLanguages.indices.contains(targetLanguagesTable.selectedRow) else { return }
        workingConfig.targetLanguages.remove(at: targetLanguagesTable.selectedRow)
        targetLanguagesTable.reloadData()
        reloadLanguagePopups()
    }

    private func populate(config: AppConfig, apiKey: String) {
        workingConfig = config
        apiKeyField.stringValue = apiKey
        apiBaseURLField.stringValue = config.apiBaseURL
        apiSpeechURLField.stringValue = config.apiSpeechURL
        modelField.stringValue = config.model
        maxTranslateLengthField.integerValue = config.maxTranslateLength
        systemPromptView.string = config.systemPrompt
        learnPromptView.string = config.learnPrompt
        sentenceLearnPromptView.string = config.sentenceLearnPrompt
        grammarPromptView.string = config.grammarPrompt
        autoPrefetchSpeechCheckbox.state = config.autoPrefetchSpeech ? .on : .off
        speechSourceModelField.stringValue = config.speechSourceModel
        speechSourceModelVietnameseField.stringValue = config.speechSourceModelVietnamese
        speechSourceModelChineseField.stringValue = config.speechSourceModelChinese
        speechTargetModelField.stringValue = config.speechTargetModel
        historyDirectoryField.stringValue = config.historyDirectory ?? ""
        widthField.doubleValue = config.ui.width
        heightField.doubleValue = config.ui.height
        autoCopyCheckbox.state = config.ui.autoCopy ? .on : .off
        simulateCopyCheckbox.state = config.ui.simulateCopy ? .on : .off
        optionCheckbox.state = config.hotkey.option ? .on : .off
        commandCheckbox.state = config.hotkey.command ? .on : .off
        controlCheckbox.state = config.hotkey.control ? .on : .off
        shiftCheckbox.state = config.hotkey.shift ? .on : .off
        hotkeyPopup.selectItem(withTitle: config.hotkey.key.uppercased())
        languagesTable.reloadData()
        targetLanguagesTable.reloadData()
        reloadLanguagePopups(
            source: config.sourceLang,
            target: config.targetLang,
            native: config.nativeLang
        )
    }

    private func reloadLanguagePopups(
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
    }

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
        let historyDirectory = historyDirectoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.historyDirectory = historyDirectory.isEmpty ? nil : historyDirectory
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
        if !issues.isEmpty { throw SettingsError.validation(issues) }
        return config
    }

    @objc private func saveClicked() {
        do {
            let config = try collectConfig()
            try onSave(config, apiKeyField.stringValue)
            originalConfig = config
            originalAPIKey = apiKeyField.stringValue
            workingConfig = config
            close()
        } catch {
            present(error)
        }
    }

    @objc private func revertClicked() {
        populate(config: originalConfig, apiKey: originalAPIKey)
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
