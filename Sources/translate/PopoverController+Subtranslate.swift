// The secondary pane: build, layout, request, and teardown.
import AppKit
import QuartzCore

extension PopoverController {
    // MARK: - Subtranslate

    func makeSubSection() -> SubtranslateSection {
        let section = SubtranslateSection()

        section.splitHost.wantsLayer = true
        section.splitHost.layer?.cornerRadius = ChromeLayout.splitCornerRadius
        section.splitHost.layer?.cornerCurve = .continuous
        section.splitHost.layer?.masksToBounds = true

        stylePane(section.sourceCard)
        stylePane(section.resultCard)
        stylePaneHeaderBar(section.sourceHeaderBar)
        stylePaneHeaderBar(section.resultHeaderBar)
        configurePaneHeaderLabel(section.sourceHeaderLabel, title: sourceHeaderLabel.stringValue)
        configurePaneHeaderLabel(section.resultHeaderLabel, title: resultHeaderLabel.stringValue)
        section.dividerGradient = installDividerGradient(on: section.splitDivider)

        for textView in [section.sourceTextView, section.resultTextView] {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
            textView.textColor = Palette.bodyText
            textView.focusRingType = .none
            textView.textContainerInset = NSSize(width: 12, height: 10)
            textView.minSize = NSSize(width: 0, height: 40)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.isVerticallyResizable = true
            textView.isHorizontallyResizable = false
            textView.autoresizingMask = [.width]
            textView.textContainer?.widthTracksTextView = true
        }
        for (scroll, textView) in [
            (section.sourceScrollView, section.sourceTextView),
            (section.resultScrollView, section.resultTextView),
        ] {
            scroll.borderType = .noBorder
            scroll.drawsBackground = false
            scroll.focusRingType = .none
            scroll.hasVerticalScroller = true
            scroll.hasHorizontalScroller = false
            scroll.autohidesScrollers = true
            scroll.scrollerStyle = .overlay
            scroll.documentView = textView
        }

        configureIconButton(section.speakSourceButton, symbol: "speaker.wave.2", action: #selector(speakSubSource), label: "Speak subtranslate source")
        configureIconButton(section.speakResultButton, symbol: "speaker.wave.2", action: #selector(speakSubResult), label: "Speak subtranslate translation")
        configureIconButton(section.copyButton, symbol: "doc.on.doc", action: #selector(copySubResult), label: "Copy subtranslate")
        configureIconButton(section.saveWordButton, symbol: "bookmark", action: #selector(toggleSaveSubWord), label: "Save subtranslate")
        configureIconButton(section.closeButton, symbol: "xmark", action: #selector(closeSubtranslate), label: "Close subtranslate")

        section.sourceHeaderBar.addSubview(section.sourceHeaderLabel)
        section.sourceHeaderBar.addSubview(section.speakSourceButton)
        section.sourceCard.addSubview(section.sourceHeaderBar)
        section.sourceCard.addSubview(section.sourceScrollView)

        section.resultHeaderBar.addSubview(section.resultHeaderLabel)
        section.resultHeaderBar.addSubview(section.speakResultButton)
        section.resultHeaderBar.addSubview(section.copyButton)
        section.resultHeaderBar.addSubview(section.saveWordButton)
        section.resultHeaderBar.addSubview(section.closeButton)
        section.resultCard.addSubview(section.resultHeaderBar)
        section.resultCard.addSubview(section.resultScrollView)

        section.splitHost.addSubview(section.sourceCard)
        section.splitHost.addSubview(section.splitDivider)
        section.splitHost.addSubview(section.resultCard)
        chromeHost.addSubview(section.splitHost)
        return section
    }

    func layoutSubSection(
        _ section: SubtranslateSection,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        panes: (left: CGFloat, right: CGFloat)
    ) {
        let L = ChromeLayout.self
        section.splitHost.frame = NSRect(x: x, y: y, width: width, height: height)
        section.splitHost.layer?.borderWidth = 1
        section.splitHost.layer?.borderColor = Palette.cg(Palette.hairline, in: section.splitHost)
        section.splitHost.layer?.backgroundColor = Palette.cg(Palette.paneFill, in: section.splitHost)

        section.sourceCard.frame = NSRect(x: 0, y: 0, width: panes.left, height: height)
        section.splitDivider.frame = NSRect(x: panes.left, y: 14, width: max(1, L.dividerWidth), height: max(0, height - 28))
        section.dividerGradient?.frame = section.splitDivider.bounds
        section.dividerGradient?.colors = Self.dividerGradientColors(in: section.splitDivider)
        section.splitHost.addSubview(section.splitDivider, positioned: .above, relativeTo: nil)
        section.resultCard.frame = NSRect(x: panes.left + L.dividerWidth, y: 0, width: panes.right, height: height)

        let bodyHeight = max(0, height - L.paneHeaderHeight)
        layoutPaneChrome(
            headerBar: section.sourceHeaderBar,
            headerLabel: section.sourceHeaderLabel,
            scrollView: section.sourceScrollView,
            textView: section.sourceTextView,
            trailingIcons: [section.speakSourceButton],
            paneWidth: panes.left,
            bodyHeight: bodyHeight
        )
        layoutPaneChrome(
            headerBar: section.resultHeaderBar,
            headerLabel: section.resultHeaderLabel,
            scrollView: section.resultScrollView,
            textView: section.resultTextView,
            trailingIcons: [section.speakResultButton, section.copyButton, section.saveWordButton, section.closeButton],
            paneWidth: panes.right,
            bodyHeight: bodyHeight
        )
    }

    @objc func closeSubtranslate() {
        removeSubSection()
        reflowLayout()
    }

    func removeSubSection() {
        subGeneration += 1
        subSection?.removeFromSuperview()
        subSection = nil
    }

    func setSubResultText(_ section: SubtranslateSection, _ value: String) {
        let style = PopoverFeedback.resultStyle(for: value)
        let color: NSColor
        switch style {
        case .normal: color = Palette.bodyText
        case .loading: color = Palette.loadingText
        case .error: color = .systemRed
        }
        section.setResult(value, font: .systemFont(ofSize: ChromeLayout.bodyFontSize), color: color)
        updateSubButtons(section)
    }

    func updateSubButtons(_ section: SubtranslateSection) {
        let copyable = PopoverFeedback.isCopyableResult(section.resultText)
        section.copyButton.isEnabled = copyable
        updateSubSpeakButtons(section)
        section.saveWordButton.isHidden = !copyable
        let isSaved = section.recordID
            .flatMap { id in historyStore.records.first { $0.id == id } }?.isSaved == true
        section.saveWordButton.image = NSImage(
            systemSymbolName: isSaved ? "bookmark.fill" : "bookmark",
            accessibilityDescription: isSaved ? "Remove Saved Word" : "Save Word"
        )
        section.saveWordButton.contentTintColor = isSaved ? .controlAccentColor : Palette.iconTint
    }

    /// Runs Translate or Learn for a freshly selected phrase into the secondary pane, leaving the
    /// main pane untouched.
    func runSubRequest(text: String, mode: TranslationMode) {
        guard let translator else { return }
        guard text.count <= config.maxTranslateLength else {
            setStatus(PopoverFeedback.textTooLong)
            return
        }
        let section = subSection ?? makeSubSection()
        subSection = section
        subGeneration += 1
        let generation = subGeneration
        section.generation = generation
        section.recordID = nil

        let pair = LanguageDetector.resolvedPair(
            selectedSource: selectedSourceLanguage(),
            selectedTarget: selectedTargetLanguage(),
            text: text,
            recentTargets: recentTargets,
            languages: config.languages,
            targetLanguages: config.targetLanguages,
            nativeLang: config.resolvedNativeLang
        )
        let displaySource = pair.source == LanguageDetector.autoDetect
            ? LanguageDetector.detectedLanguage(text)
            : pair.source
        section.sourceLanguage = displaySource
        section.targetLanguage = pair.target
        section.sourceHeaderLabel.stringValue = paneLanguageCode(displaySource)
        section.resultHeaderLabel.stringValue = paneLanguageCode(pair.target)
        section.setSource(text, font: .systemFont(ofSize: ChromeLayout.bodyFontSize), color: Palette.bodyText)
        let waitingText: String
        switch mode {
        case .learn: waitingText = PopoverFeedback.learning
        case .proofread: waitingText = PopoverFeedback.proofreading
        case .translate: waitingText = PopoverFeedback.translating
        }
        setSubResultText(section, waitingText)
        reflowLayout()

        if let record = historyStore.reusableRecord(
            mode: mode,
            sourceText: text,
            sourceLanguage: displaySource,
            targetLanguage: pair.target,
            sourceIsAutoDetect: selectedSourceLanguage() == LanguageDetector.autoDetect
        ) {
            finishSubRequest(generation: generation, text: text, mode: mode, pair: (displaySource, pair.target), result: .success(record.resultText), existingRecord: record)
            return
        }

        let handler: @Sendable (Result<String, Error>) -> Void = { [weak self] result in
            Task { @MainActor in
                self?.finishSubRequest(
                    generation: generation, text: text, mode: mode,
                    pair: (displaySource, pair.target), result: result, existingRecord: nil
                )
            }
        }
        if mode == .proofread {
            translator.proofread(text, lang: displaySource, completion: handler)
        } else if mode == .learn {
            translator.learn(text, sourceLang: pair.source, targetLang: pair.target, parentContext: inputTextView.string, completion: handler)
        } else {
            let context = historyStore.recentContext(
                sourceLanguage: displaySource,
                targetLanguage: pair.target,
                excludingText: text
            ).reversed().map { ContextPair(source: $0.sourceText, target: $0.resultText) }
            translator.translate(text, sourceLang: pair.source, targetLang: pair.target, context: context, parentContext: inputTextView.string) { result in
                handler(result.map(\.text))
            }
        }
    }

    func finishSubRequest(
        generation: Int,
        text: String,
        mode: TranslationMode,
        pair: (source: String, target: String),
        result: Result<String, Error>,
        existingRecord: TranslationRecord?
    ) {
        guard let section = subSection, section.generation == generation, generation == subGeneration else { return }
        switch result {
        case let .success(value):
            setSubResultText(section, value)
            if let existingRecord {
                section.recordID = existingRecord.id
            } else {
                let record = TranslationRecord(
                    id: UUID(), timestamp: Date(), mode: mode, sourceText: text, resultText: value,
                    sourceLanguage: pair.source, targetLanguage: pair.target, isSaved: false
                )
                do {
                    section.recordID = try historyStore.appendIfAbsent(record).id
                    historyWindowController.reloadHistory()
                } catch {
                    setStatus("History failed: \(error.localizedDescription)", autoClearAfter: 12)
                }
            }
        case let .failure(error):
            setSubResultText(section, "Error: \(error.localizedDescription)")
        }
        updateSubButtons(section)
        reflowLayout()
        section.resultTextView.scrollToBeginningOfDocument(nil)
    }

    func subSpeechIdentity(kind: SpeechKind) -> SpeechIdentity? {
        guard let section = subSection else { return nil }
        let text = kind == .source ? section.sourceText : section.resultText
        guard kind == .source ? !text.isEmpty : PopoverFeedback.isCopyableResult(text) else { return nil }
        let language = kind == .source ? section.sourceLanguage : section.targetLanguage
        return SpeechIdentity(
            kind: kind,
            text: text,
            model: SpeechModelResolver.model(for: language, config: config),
            recordID: section.recordID
        )
    }

    @objc func speakSubSource() { playSpeech(subSpeechIdentity(kind: .source)) }
    @objc func speakSubResult() { playSpeech(subSpeechIdentity(kind: .result)) }

    @objc func copySubResult() {
        guard let section = subSection, PopoverFeedback.isCopyableResult(section.resultText) else { return }
        guard writePasteboard(section.resultText) else {
            setStatus("Copy failed")
            return
        }
        setStatus("Copied")
    }

    @objc func toggleSaveSubWord() {
        guard let section = subSection, let recordID = section.recordID,
              let record = historyStore.records.first(where: { $0.id == recordID })
        else { return }
        do {
            try historyStore.setSaved(!record.isSaved, recordID: recordID)
            historyWindowController.reloadHistory()
            updateSubButtons(section)
        } catch {
            setStatus("Save Word failed: \(error.localizedDescription)", autoClearAfter: 12)
        }
    }

    func openHistoryRecord(_ record: TranslationRecord) {
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        setPendingImage(nil)

        resolvedSourceLanguage = record.sourceLanguage
        sourceLanguageSelection = record.sourceLanguage
        targetLanguageSelection = record.targetLanguage
        styleLanguageButtonTitle(sourceLanguageButton, language: sourceLanguageSelection)
        styleLanguageButtonTitle(targetLanguageButton, language: targetLanguageSelection)

        inputTextView.string = record.sourceText
        setResultText(record.resultText)

        currentRecordID = record.id
        updateBusyState()
        updatePaneLanguageLabels()

        focusInputTextView()
        reflowLayout()
    }

    // MARK: - Floating Selection Toolbar

    func configureFloatingToolbar() {
        selectionFloatingBar.state = .active
        selectionFloatingBar.material = .hudWindow
        selectionFloatingBar.blendingMode = .withinWindow
        selectionFloatingBar.wantsLayer = true
        selectionFloatingBar.layer?.cornerRadius = 14
        selectionFloatingBar.layer?.cornerCurve = .continuous
        selectionFloatingBar.layer?.masksToBounds = true
        selectionFloatingBar.layer?.borderWidth = 1
        selectionFloatingBar.layer?.borderColor = Palette.cg(Palette.hairline, in: selectionFloatingBar)
        selectionFloatingBar.isHidden = true

        configureFloatingButton(floatingTranslateButton, symbol: "arrow.right.circle", action: #selector(floatingTranslateClicked), label: "Subtranslate")
        configureFloatingButton(floatingLearnButton, symbol: "brain.head.profile", action: #selector(floatingLearnClicked), label: "Learn Phrase")
        configureFloatingButton(floatingSpeakButton, symbol: "speaker.wave.2", action: #selector(floatingSpeakClicked), label: "Speak Phrase")
        configureFloatingButton(floatingCopyButton, symbol: "doc.on.doc", action: #selector(floatingCopyClicked), label: "Copy Phrase")

        let stack = NSStackView(views: [floatingTranslateButton, floatingLearnButton, floatingSpeakButton, floatingCopyButton])
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false

        selectionFloatingBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: selectionFloatingBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: selectionFloatingBar.trailingAnchor),
            stack.topAnchor.constraint(equalTo: selectionFloatingBar.topAnchor),
            stack.bottomAnchor.constraint(equalTo: selectionFloatingBar.bottomAnchor),
        ])
    }

    func configureFloatingButton(_ button: NSButton, symbol: String, action: Selector, label: String) {
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .inline
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.contentTintColor = Palette.iconTint
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 22),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    func updateFloatingSelectionBar() {
        let range = inputTextView.selectedRange()
        guard range.length > 0,
              let bounds = Range(range, in: inputTextView.string)
        else {
            hideFloatingSelectionBar()
            return
        }
        let text = inputTextView.string[bounds].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            hideFloatingSelectionBar()
            return
        }
        currentFloatingSelectedText = text

        guard let layoutManager = inputTextView.layoutManager,
              let textContainer = inputTextView.textContainer
        else {
            hideFloatingSelectionBar()
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rectInTextView = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let rectInScroll = inputTextView.convert(rectInTextView, to: inputScrollView)
        guard inputScrollView.bounds.intersects(rectInScroll) else {
            hideFloatingSelectionBar()
            return
        }

        let rectInChrome = inputTextView.convert(rectInTextView, to: chromeHost)
        let barWidth: CGFloat = 118
        let barHeight: CGFloat = 28
        let barX = max(ChromeLayout.padding, min(rectInChrome.midX - barWidth / 2, chromeHost.bounds.width - ChromeLayout.padding - barWidth))
        let barY = rectInChrome.maxY + 6

        selectionFloatingBar.frame = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
        selectionFloatingBar.isHidden = false
        chromeHost.addSubview(selectionFloatingBar, positioned: .above, relativeTo: nil)
    }

    func hideFloatingSelectionBar() {
        selectionFloatingBar.isHidden = true
        currentFloatingSelectedText = nil
    }

    @objc func floatingTranslateClicked() {
        guard let text = currentFloatingSelectedText else { return }
        runSubRequest(text: text, mode: .translate)
    }

    @objc func floatingLearnClicked() {
        guard let text = currentFloatingSelectedText else { return }
        runSubRequest(text: text, mode: .learn)
    }

    @objc func floatingSpeakClicked() {
        guard let text = currentFloatingSelectedText else { return }
        let lang = effectiveSourceLanguage(for: text)
        let model = SpeechModelResolver.model(for: lang, config: config)
        playSpeech(SpeechIdentity(kind: .source, text: text, model: model, recordID: nil))
    }

    @objc func floatingCopyClicked() {
        guard let text = currentFloatingSelectedText else { return }
        guard writePasteboard(text) else {
            setStatus("Copy failed")
            return
        }
        setStatus("Copied phrase")
    }
}