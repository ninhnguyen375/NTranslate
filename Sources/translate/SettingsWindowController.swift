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

@MainActor
final class SettingsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSTextViewDelegate {
    typealias SaveHandler = (AppConfig, String) throws -> Void

    private var originalConfig: AppConfig
    private var originalAPIKey: String
    var workingConfig: AppConfig
    private let onSave: SaveHandler

    private let apiKeyField = NSSecureTextField()
    private let apiBaseURLField = NSTextField()
    private let apiSpeechURLField = NSTextField()
    private let modelField = NSTextField()
    private let themePopup = NSPopUpButton()
    private let sourceLanguagePopup = NSPopUpButton()
    private let targetLanguagePopup = NSPopUpButton()
    private let nativeLanguagePopup = NSPopUpButton()
    private let maxTranslateLengthField = NSTextField()

    private let systemPromptView = NSTextView()
    private let learnPromptView = NSTextView()
    private let sentenceLearnPromptView = NSTextView()
    private let grammarPromptView = NSTextView()
    private let imagePromptView = NSTextView()
    private let qaPromptView = NSTextView()

    /// Each editable prompt paired with the default this build ships, so the Prompts tab can offer
    /// "Sync with app prompt" when an update changes a default the user never customized.
    private var promptSyncButtons: [ObjectIdentifier: NSButton] = [:]
    private var promptDefaults: [ObjectIdentifier: String] = [:]

    let languagesTable = NSTableView()
    let targetLanguagesTable = NSTableView()

    private let autoPrefetchSpeechCheckbox = NSButton(
        checkboxWithTitle: "Prefetch speech automatically",
        target: nil,
        action: nil
    )
    /// Rebuilt whenever the Languages tab changes; one row per language plus a fallback row.
    private let speechModelsStack = NSStackView()
    private var speechModelFields: [String: NSTextField] = [:]
    private let speechFallbackModelField = NSTextField()
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
    private let hotkeyFields = HotkeyFields()
    private let copyTranslateHotkeyFields = HotkeyFields()
    private let learnHotkeyFields = HotkeyFields()
    private let proofreadHotkeyFields = HotkeyFields()

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
        [hotkeyFields, copyTranslateHotkeyFields, learnHotkeyFields, proofreadHotkeyFields].forEach { $0.configure() }
        speechModelsStack.orientation = .vertical
        speechModelsStack.alignment = .width
        speechModelsStack.spacing = 12

        [systemPromptView, learnPromptView, sentenceLearnPromptView, grammarPromptView, imagePromptView, qaPromptView].forEach {
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
        themePopup.removeAllItems()
        AppTheme.allCases.forEach { themePopup.addItem(withTitle: $0.displayName) }
        return scrollableForm([
            labeledRow("Theme", themePopup),
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
            promptSection("System Prompt", systemPromptView, appDefault: AppConfig.default.systemPrompt),
            promptSection("Learn Word Prompt", learnPromptView, appDefault: AppConfig.defaultLearnPrompt),
            promptSection("Learn Sentence Prompt", sentenceLearnPromptView, appDefault: AppConfig.defaultSentenceLearnPrompt),
            promptSection("Grammar Prompt", grammarPromptView, appDefault: AppConfig.defaultGrammarPrompt),
            promptSection("Image Prompt", imagePromptView, appDefault: AppConfig.defaultImagePrompt),
            promptSection("Q&A Prompt", qaPromptView, appDefault: AppConfig.defaultQAPrompt),
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
        let historyFields = NSStackView(views: [historyDirectoryField, choose])
        historyFields.orientation = .horizontal
        historyFields.spacing = 8

        // The label column is a fixed 150pt, so the sync hint goes under the field instead.
        let historyHint = NSTextField(labelWithString: "Point at a folder your Macs already share (iCloud Drive, Dropbox, Syncthing) to sync history across devices.")
        historyHint.font = .systemFont(ofSize: 11)
        historyHint.textColor = .secondaryLabelColor
        historyHint.lineBreakMode = .byWordWrapping
        historyHint.maximumNumberOfLines = 2
        let historyRow = NSStackView(views: [historyFields, historyHint])
        historyRow.orientation = .vertical
        historyRow.alignment = .leading
        historyRow.spacing = 4
        historyHint.widthAnchor.constraint(equalTo: historyRow.widthAnchor).isActive = true

        let dimensions = NSStackView(views: [widthField, NSTextField(labelWithString: "×"), heightField])
        dimensions.orientation = .horizontal
        dimensions.spacing = 8
        widthField.widthAnchor.constraint(equalToConstant: 90).isActive = true
        heightField.widthAnchor.constraint(equalToConstant: 90).isActive = true

        return scrollableForm([
            speechModelsStack,
            labeledRow("Fallback Model", speechFallbackModelField),
            labeledRow("Speech", autoPrefetchSpeechCheckbox),
            labeledRow("History Folder", historyRow),
            labeledRow("Panel Width × Height", dimensions),
            labeledRow("Copy", autoCopyCheckbox),
            labeledRow("Paste", simulateCopyCheckbox),
            labeledRow("Global Hotkey", hotkeyFields.makeRow()),
            labeledRow("Copy & Translate Hotkey", copyTranslateHotkeyFields.makeRow()),
            labeledRow("Learn Hotkey", learnHotkeyFields.makeRow()),
            labeledRow("Proofread Hotkey", proofreadHotkeyFields.makeRow()),
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

        speechModelsStack.arrangedSubviews.forEach {
            speechModelsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for language in languages {
            guard let field = speechModelFields[language] else { continue }
            speechModelsStack.addArrangedSubview(labeledRow("\(language) Model", field))
        }
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
        row.alignment = .top
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

        let container = FlippedDocumentView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor),
            container.heightAnchor.constraint(greaterThanOrEqualTo: stack.heightAnchor)
        ])

        let scroll = scrollView(for: container)
        container.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }

    private func promptSection(_ title: String, _ textView: NSTextView, appDefault: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)

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

        let scroll = scrollView(for: textView)
        scroll.heightAnchor.constraint(equalToConstant: 150).isActive = true
        let section = NSStackView(views: [header, scroll])
        section.orientation = .vertical
        section.alignment = .width
        section.spacing = 6
        header.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
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
        [systemPromptView, learnPromptView, sentenceLearnPromptView, grammarPromptView, imagePromptView, qaPromptView]
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

    private func populate(config: AppConfig, apiKey: String) {
        workingConfig = config
        apiKeyField.stringValue = apiKey
        apiBaseURLField.stringValue = config.apiBaseURL
        apiSpeechURLField.stringValue = config.apiSpeechURL
        modelField.stringValue = config.model
        themePopup.selectItem(withTitle: config.theme.displayName)
        maxTranslateLengthField.integerValue = config.maxTranslateLength
        systemPromptView.string = config.systemPrompt
        learnPromptView.string = config.learnPrompt
        sentenceLearnPromptView.string = config.sentenceLearnPrompt
        grammarPromptView.string = config.grammarPrompt
        imagePromptView.string = config.imagePrompt
        qaPromptView.string = config.qaPrompt
        refreshPromptSyncButtons()
        autoPrefetchSpeechCheckbox.state = config.autoPrefetchSpeech ? .on : .off
        speechModelFields.removeAll()
        rebuildSpeechModelRows()
        for (language, field) in speechModelFields {
            field.stringValue = config.speechModels[language] ?? ""
        }
        speechFallbackModelField.stringValue = config.speechFallbackModel
        historyDirectoryField.stringValue = config.historyDirectory ?? ""
        widthField.doubleValue = config.ui.width
        heightField.doubleValue = config.ui.height
        autoCopyCheckbox.state = config.ui.autoCopy ? .on : .off
        simulateCopyCheckbox.state = config.ui.simulateCopy ? .on : .off
        hotkeyFields.populate(config.hotkey)
        copyTranslateHotkeyFields.populate(config.copyTranslateHotkey)
        learnHotkeyFields.populate(config.learnHotkey)
        proofreadHotkeyFields.populate(config.proofreadHotkey)
        languagesTable.reloadData()
        targetLanguagesTable.reloadData()
        reloadLanguagePopups(
            source: config.sourceLang,
            target: config.targetLang,
            native: config.nativeLang
        )
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
    }

    private func collectConfig() throws -> AppConfig {
        window?.makeFirstResponder(nil)
        var config = workingConfig
        config.apiBaseURL = apiBaseURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.apiSpeechURL = apiSpeechURLField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedThemeTitle = themePopup.titleOfSelectedItem ?? AppTheme.system.displayName
        config.theme = AppTheme.allCases.first(where: { $0.displayName == selectedThemeTitle }) ?? .system
        config.sourceLang = sourceLanguagePopup.titleOfSelectedItem ?? ""
        config.targetLang = targetLanguagePopup.titleOfSelectedItem ?? ""
        config.nativeLang = nativeLanguagePopup.titleOfSelectedItem ?? ""
        config.maxTranslateLength = maxTranslateLengthField.integerValue
        config.systemPrompt = systemPromptView.string
        config.learnPrompt = learnPromptView.string
        config.sentenceLearnPrompt = sentenceLearnPromptView.string
        config.grammarPrompt = grammarPromptView.string
        config.imagePrompt = imagePromptView.string
        config.qaPrompt = qaPromptView.string
        config.autoPrefetchSpeech = autoPrefetchSpeechCheckbox.state == .on
        config.speechModels = speechModelFields.reduce(into: [:]) { result, entry in
            let value = entry.value.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { result[entry.key] = value }
        }
        config.speechFallbackModel = speechFallbackModelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let historyDirectory = historyDirectoryField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.historyDirectory = historyDirectory.isEmpty ? nil : historyDirectory
        config.ui.width = widthField.doubleValue
        config.ui.height = heightField.doubleValue
        config.ui.autoCopy = autoCopyCheckbox.state == .on
        config.ui.simulateCopy = simulateCopyCheckbox.state == .on
        config.hotkey = hotkeyFields.collect(fallbackKey: "D")
        config.copyTranslateHotkey = copyTranslateHotkeyFields.collect(fallbackKey: "D")
        config.learnHotkey = learnHotkeyFields.collect(fallbackKey: "L")
        config.proofreadHotkey = proofreadHotkeyFields.collect(fallbackKey: "P")

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
