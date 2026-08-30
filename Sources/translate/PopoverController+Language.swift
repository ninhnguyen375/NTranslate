// Source/target language selection: dropdown menus, swap, and auto-detect resolution.
import AppKit

extension PopoverController {
    func selectedSourceLanguage() -> String {
        sourceLanguageSelection.isEmpty ? config.resolvedSourceLang : sourceLanguageSelection
    }

    func selectedTargetLanguage() -> String {
        targetLanguageSelection.isEmpty ? config.resolvedTargetLang : targetLanguageSelection
    }

    enum LanguageButtonKind: Int {
        case source = 1
        case target = 2
    }

    func selectLanguage(_ language: String, kind: LanguageButtonKind) {
        switch kind {
        case .source:
            sourceLanguageSelection = language
            styleLanguageButtonTitle(sourceLanguageButton, language: language)
        case .target:
            targetLanguageSelection = language
            styleLanguageButtonTitle(targetLanguageButton, language: language)
        }
    }

    func languageMenuFont() -> NSFont {
        .systemFont(ofSize: ChromeLayout.languageFontSize, weight: .regular)
    }

    func configureLanguageButton(_ button: NSButton, kind: LanguageButtonKind) {
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.imagePosition = .imageTrailing
        button.imageHugsTitle = true
        button.target = self
        button.action = #selector(showLanguageMenu(_:))
        button.tag = kind.rawValue
        button.font = languageMenuFont()
        button.contentTintColor = Palette.languageTint
        let chevron = NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)
        button.image = NSImage(
            systemSymbolName: "chevron.up.chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(chevron)
    }

    func styleLanguageButtonTitle(_ button: NSButton, language: String) {
        button.title = language
        button.attributedTitle = NSAttributedString(
            string: language,
            attributes: [
                .font: languageMenuFont(),
                .foregroundColor: Palette.languageTitle
            ]
        )
        button.toolTip = language
        button.setAccessibilityLabel(language)
    }

    func populateLanguageButton(
        _ button: NSButton,
        kind: LanguageButtonKind,
        languages: [String],
        selected: String
    ) {
        switch kind {
        case .source: sourceLanguageOptions = languages
        case .target: targetLanguageOptions = languages
        }
        selectLanguage(selected, kind: kind)
        configureLanguageButton(button, kind: kind)
        styleLanguageButtonTitle(button, language: selected)
    }

    @objc func showLanguageMenu(_ sender: NSButton) {
        guard let kind = LanguageButtonKind(rawValue: sender.tag) else { return }
        let languages = kind == .source ? sourceLanguageOptions : targetLanguageOptions
        let selected = kind == .source ? selectedSourceLanguage() : selectedTargetLanguage()
        let menu = NSMenu()
        let font = languageMenuFont()
        for language in languages {
            let item = NSMenuItem(
                title: language,
                action: #selector(languageMenuItemChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.attributedTitle = NSAttributedString(
                string: language,
                attributes: [
                    .font: font,
                    .foregroundColor: Palette.menuItemTitle
                ]
            )
            item.representedObject = language
            item.toolTip = language
            item.state = language == selected ? .on : .off
            item.tag = kind.rawValue
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc func languageMenuItemChosen(_ sender: NSMenuItem) {
        guard let kind = LanguageButtonKind(rawValue: sender.tag),
              let language = sender.representedObject as? String
        else { return }
        if kind == .source { resolvedSourceLanguage = nil }
        selectLanguage(language, kind: kind)
        languageSelectionChanged()
    }

    func previewLanguagePair(for text: String) -> (source: String, target: String) {
        LanguageDetector.resolvedPair(
            selectedSource: selectedSourceLanguage(),
            selectedTarget: selectedTargetLanguage(),
            text: text,
            recentTargets: recentTargets,
            languages: config.languages,
            targetLanguages: config.targetLanguages,
            nativeLang: config.resolvedNativeLang
        )
    }

    /// Updates MRU `recentTargets`. UI must use `previewLanguagePair`.
    func resolvedLanguagePair(for text: String, respectSelectedTarget: Bool = false) -> (source: String, target: String) {
        let pair = LanguageDetector.resolvedPair(
            selectedSource: selectedSourceLanguage(),
            selectedTarget: selectedTargetLanguage(),
            text: text,
            recentTargets: recentTargets,
            languages: config.languages,
            targetLanguages: config.targetLanguages,
            nativeLang: config.resolvedNativeLang,
            respectSelectedTarget: respectSelectedTarget
        )
        recentTargets.removeAll { $0 == pair.target }
        recentTargets.insert(pair.target, at: 0)
        return pair
    }

    func configureLanguageControls() {
        populateLanguageButton(
            sourceLanguageButton,
            kind: .source,
            languages: config.languages,
            selected: LanguageDetector.normalizeSource(config.resolvedSourceLang, languages: config.languages)
        )

        let savedTarget = UserDefaults.standard.string(forKey: Self.lastTargetLangKey) ?? config.resolvedTargetLang
        let normalizedTarget = LanguageDetector.normalizeTarget(
            savedTarget,
            targetLanguages: config.targetLanguages,
            fallback: config.resolvedNativeLang
        )
        populateLanguageButton(
            targetLanguageButton,
            kind: .target,
            languages: config.targetLanguages,
            selected: normalizedTarget
        )
        recentTargets = [normalizedTarget]

        swapLanguagesButton.title = ""
        let swapSymbol = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        swapLanguagesButton.image = NSImage(
            systemSymbolName: "arrow.left.arrow.right",
            accessibilityDescription: "Swap languages"
        )?.withSymbolConfiguration(swapSymbol)
        swapLanguagesButton.imagePosition = .imageOnly
        swapLanguagesButton.bezelStyle = .glass
        swapLanguagesButton.controlSize = .regular
        swapLanguagesButton.target = self
        swapLanguagesButton.action = #selector(swapLanguages)
        swapLanguagesButton.toolTip = "Swap languages"
        swapLanguagesButton.contentTintColor = Palette.chromeIconTint
        updatePaneLanguageLabels()
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === inputTextView else { return }
        if !inputContextLabel.isHidden {
            inputContextLabel.stringValue = ""
            inputContextLabel.toolTip = nil
            inputContextLabel.isHidden = true
        }
        hideFloatingSelectionBar()
        // Editing the main source invalidates whatever phrase the sub pane was explaining.
        removeSubSection()
        if pendingImage != nil { setPendingImage(nil) }
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        updateSpeakButtons()
        updatePaneLanguageLabels()
        reflowLayout()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard let obj = notification.object as? NSTextView,
              floatingSelectionCandidates().contains(where: { $0.textView === obj }) else { return }
        updateFloatingSelectionBar()
    }

    @objc func languageSelectionChanged() {
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        if pendingImage != nil {
            UserDefaults.standard.set(selectedTargetLanguage(), forKey: Self.lastTargetLangKey)
            updatePaneLanguageLabels()
            runTranslate()
            return
        }
        let text = inputTextView.string
        let pair = resolvedLanguagePair(for: text, respectSelectedTarget: true)
        if selectedSourceLanguage() != pair.source {
            selectLanguage(pair.source, kind: .source)
        }
        if selectedTargetLanguage() != pair.target {
            selectLanguage(pair.target, kind: .target)
        }
        UserDefaults.standard.set(pair.target, forKey: Self.lastTargetLangKey)
        updatePaneLanguageLabels()
        styleLanguageButtonTitle(sourceLanguageButton, language: selectedSourceLanguage())
        styleLanguageButtonTitle(targetLanguageButton, language: selectedTargetLanguage())
        if !inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runTranslate()
        }
    }

    @objc func swapLanguages() {
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let pair = LanguageDetector.swappedPair(
            selectedSource: selectedSourceLanguage(),
            selectedTarget: selectedTargetLanguage(),
            text: text,
            languages: config.languages,
            targetLanguages: config.targetLanguages,
            nativeLang: config.resolvedNativeLang
        )

        sourceLanguageSelection = pair.source
        targetLanguageSelection = pair.target

        styleLanguageButtonTitle(sourceLanguageButton, language: sourceLanguageSelection)
        styleLanguageButtonTitle(targetLanguageButton, language: targetLanguageSelection)
        updatePaneLanguageLabels()

        let oldSourceText = inputTextView.string
        inputTextView.string = textView.string
        setResultText(oldSourceText)

        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        UserDefaults.standard.set(pair.target, forKey: Self.lastTargetLangKey)
        updatePaneLanguageLabels()
        updateBusyState()
        reflowLayout()
    }
}