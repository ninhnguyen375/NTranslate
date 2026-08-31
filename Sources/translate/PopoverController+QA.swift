import AppKit

extension PopoverController: NSTextFieldDelegate {
    // MARK: - QA Setup & Actions

    func configureQAInputBar() {
        qaInputField.placeholderString = "Ask follow-up questions about translation..."
        qaInputField.font = .systemFont(ofSize: ChromeLayout.controlFontSize)
        qaInputField.textColor = Palette.bodyText
        qaInputField.backgroundColor = NSColor.clear
        qaInputField.isBordered = false
        qaInputField.isEditable = true
        qaInputField.usesSingleLineMode = true
        qaInputField.lineBreakMode = .byClipping
        qaInputField.cell?.wraps = false
        qaInputField.cell?.isScrollable = true
        qaInputField.isSelectable = true
        qaInputField.focusRingType = .default
        qaInputField.wantsLayer = true
        qaInputField.layer?.cornerRadius = 14
        qaInputField.layer?.masksToBounds = true
        qaInputField.layer?.borderWidth = 1
        applyQAInputChrome()
        qaInputField.target = self
        qaInputField.action = #selector(qaInputSubmitted(_:))
        qaInputField.delegate = self
    }

    /// Layer colors are baked CGColors — the reflow re-runs this so the field follows
    /// a light/dark switch instead of keeping the appearance it was built in.
    func applyQAInputChrome() {
        qaInputField.layer?.borderColor = Palette.cg(Palette.hairline, in: qaInputField)
        qaInputField.layer?.backgroundColor = Palette.cg(Palette.paneFill, in: qaInputField)
    }

    func makeQASection() -> QAPaneSection {
        let section = QAPaneSection()
        section.host.wantsLayer = true
        section.host.layer?.cornerRadius = ChromeLayout.splitCornerRadius
        section.host.layer?.cornerCurve = .continuous
        section.host.layer?.masksToBounds = true

        section.targetsSub = qaTargetsSub
        stylePane(section.card)
        stylePaneHeaderBar(section.headerBar)
        configurePaneHeaderLabel(section.headerLabel, title: section.headerTitle)

        section.textView.isEditable = false
        section.textView.isSelectable = true
        section.textView.delegate = self
        section.textView.onResignFirstResponder = { [weak self] in
            self?.hideFloatingSelectionBar()
        }
        section.textView.drawsBackground = false
        section.textView.font = .systemFont(ofSize: ChromeLayout.qaFontSize)
        section.textView.textColor = Palette.bodyText
        section.textView.focusRingType = .default
        section.textView.textContainerInset = NSSize(width: 12, height: 10)
        section.textView.minSize = NSSize(width: 0, height: 40)
        section.textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        section.textView.isVerticallyResizable = true
        section.textView.isHorizontallyResizable = false
        section.textView.autoresizingMask = [.width]
        section.textView.textContainer?.widthTracksTextView = true

        section.scrollView.borderType = .noBorder
        section.scrollView.drawsBackground = false
        section.scrollView.focusRingType = .default
        section.scrollView.hasVerticalScroller = true
        section.scrollView.hasHorizontalScroller = false
        section.scrollView.autohidesScrollers = true
        section.scrollView.scrollerStyle = .overlay
        section.scrollView.documentView = section.textView

        configureIconButton(section.copyButton, symbol: "doc.on.doc", action: #selector(copyQAResult), label: "Copy Q&A transcript")
        configureIconButton(section.closeButton, symbol: "xmark", action: #selector(closeQASection), label: "Close Q&A answer")

        section.headerBar.addSubview(section.headerLabel)
        section.headerBar.addSubview(section.copyButton)
        section.headerBar.addSubview(section.closeButton)
        section.card.addSubview(section.headerBar)
        section.card.addSubview(section.scrollView)
        section.host.addSubview(section.card)

        chromeHost.addSubview(section.host)
        return section
    }

    func layoutQASection(
        _ section: QAPaneSection,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        let L = ChromeLayout.self
        section.host.frame = NSRect(x: x, y: y, width: width, height: height)
        section.host.layer?.borderWidth = 1
        section.host.layer?.borderColor = Palette.cg(Palette.hairline, in: section.host)
        section.host.layer?.backgroundColor = Palette.cg(Palette.paneFill, in: section.host)

        section.card.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let bodyHeight = max(0, height - L.paneHeaderHeight)

        layoutPaneChrome(
            headerBar: section.headerBar,
            headerLabel: section.headerLabel,
            scrollView: section.scrollView,
            textView: section.textView,
            trailingIcons: [section.copyButton, section.closeButton],
            paneWidth: width,
            bodyHeight: bodyHeight
        )
    }

    @objc func askButtonClicked() { presentQAInput(forSub: false) }
    @objc func askSubClicked() { presentQAInput(forSub: true) }

    /// One Q&A input serves both panes; `forSub` decides which pane's texts the question is asked about.
    func presentQAInput(forSub: Bool) {
        let switchedPane = qaTargetsSub != forSub
        qaTargetsSub = forSub
        updateQAPlaceholder()
        if switchedPane, qaSection != nil {
            removeQASection()
        }
        if qaInputField.isHidden || switchedPane {
            qaInputField.isHidden = false
            reflowLayout()
            panel.makeFirstResponder(qaInputField)
        } else if qaInputField.stringValue.isEmpty {
            qaInputField.isHidden = true
            reflowLayout()
        } else {
            panel.makeFirstResponder(qaInputField)
        }
    }

    func updateQAPlaceholder() {
        qaInputField.placeholderString = qaTargetsSub
            ? "Ask follow-up questions about the sub-translation..."
            : "Ask follow-up questions about translation..."
    }

    func qaTargets() -> (source: String, result: String, sourceLang: String, targetLang: String)? {
        if qaTargetsSub, let sub = subSection {
            let result = sub.resultText
            guard !result.isEmpty, PopoverFeedback.isCopyableResult(result) else { return nil }
            return (sub.sourceText, result, sub.sourceLanguage, sub.targetLanguage)
        }
        let source = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty, PopoverFeedback.isCopyableResult(result) else { return nil }
        return (source, result, selectedSourceLanguage(), selectedTargetLanguage())
    }

    /// Main pane source + translation, attached when Ask runs from the sub row.
    func qaParentContext() -> String? {
        guard qaTargetsSub else { return nil }
        let source = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines: [String] = []
        if !source.isEmpty { lines.append("Source: \(source)") }
        if !result.isEmpty { lines.append("Translation: \(result)") }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    func removeQASection() {
        qaRequest?.cancel()
        qaRequest = nil
        qaGeneration += 1
        qaSection?.removeFromSuperview()
        qaSection = nil
    }

    @objc func closeQASection() {
        removeQASection()
        reflowLayout()
    }

    @objc func copyQAResult() {
        guard let section = qaSection, !section.answerText.isEmpty else { return }
        let payload = section.turns.count > 1 ? section.transcriptText : section.answerText
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
        flashCopyButton(section.copyButton)
    }

    func flashCopyButton(_ button: NSButton) {
        let original = button.image
        button.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "Copied")
        button.contentTintColor = .systemGreen
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            button.image = original
            button.contentTintColor = Palette.iconTint
        }
    }

    @objc func qaInputSubmitted(_ sender: NSTextField) {
        let question = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        guard let targets = qaTargets() else {
            setStatus("No translation available for Q&A")
            return
        }

        guard let translator else {
            setStatus("API key is not configured")
            return
        }

        if let existing = qaSection, existing.targetsSub != qaTargetsSub {
            removeQASection()
        }
        let section = qaSection ?? makeQASection()
        qaSection = section
        qaRequest?.cancel()
        qaGeneration += 1
        let generation = qaGeneration
        section.generation = generation

        // Prior turns go to the model before the new question, so follow-ups can refer back.
        let history = section.completedTurns
        section.appendQuestion(question, placeholder: "Answering...")
        renderQASection(section)
        sender.stringValue = ""
        reflowLayout()
        scrollQAToBottom(section)

        qaRequest = translator.ask(
            question,
            sourceText: targets.source,
            translatedText: targets.result,
            sourceLang: targets.sourceLang,
            targetLang: targets.targetLang,
            history: history,
            parentContext: qaParentContext(),
            onPartial: { [weak self] partial in
                Task { @MainActor in
                    guard let self, self.qaGeneration == generation, let currentSection = self.qaSection else { return }
                    currentSection.updateLastAnswer(partial)
                    self.renderQASection(currentSection)
                    self.throttleQAStreamReflow()
                    self.scrollQAToBottom(currentSection)
                }
            }
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.qaGeneration == generation, let currentSection = self.qaSection else { return }
                self.qaRequest = nil
                switch result {
                case let .success(answer):
                    currentSection.completeLastTurn(with: answer)
                case let .failure(error):
                    let message = PopoverFeedback.userFacingError(error)
                    if message == PopoverFeedback.stopped {
                        currentSection.completeLastTurn(with: currentSection.turns.last?.answer ?? PopoverFeedback.stopped, failed: false)
                    } else {
                        currentSection.completeLastTurn(with: message, failed: true)
                    }
                }
                self.renderQASection(currentSection)
                self.reflowLayout()
                self.scrollQAToBottom(currentSection)
            }
        }
    }

    func renderQASection(_ section: QAPaneSection) {
        section.render(
            font: .systemFont(ofSize: ChromeLayout.qaFontSize),
            questionColor: Palette.titleText,
            answerColor: Palette.bodyText,
            pendingColor: Palette.loadingText,
            errorColor: .systemRed
        )
    }

    func scrollQAToBottom(_ section: QAPaneSection) {
        section.textView.scrollToEndOfDocument(nil)
    }
}
