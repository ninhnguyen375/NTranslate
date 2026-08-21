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
        qaInputField.isSelectable = true
        qaInputField.focusRingType = .none
        qaInputField.wantsLayer = true
        qaInputField.layer?.cornerRadius = 14
        qaInputField.layer?.masksToBounds = true
        qaInputField.layer?.borderWidth = 1
        qaInputField.layer?.borderColor = Palette.cg(Palette.hairline, in: qaInputField)
        qaInputField.layer?.backgroundColor = Palette.cg(Palette.paneFill, in: qaInputField)
        qaInputField.target = self
        qaInputField.action = #selector(qaInputSubmitted(_:))
        qaInputField.delegate = self
    }

    func makeQASection() -> QAPaneSection {
        let section = QAPaneSection()
        section.host.wantsLayer = true
        section.host.layer?.cornerRadius = ChromeLayout.splitCornerRadius
        section.host.layer?.cornerCurve = .continuous
        section.host.layer?.masksToBounds = true

        stylePane(section.card)
        stylePaneHeaderBar(section.headerBar)
        configurePaneHeaderLabel(section.headerLabel, title: "Q&A")

        section.textView.isEditable = false
        section.textView.isSelectable = true
        section.textView.drawsBackground = false
        section.textView.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
        section.textView.textColor = Palette.bodyText
        section.textView.focusRingType = .none
        section.textView.textContainerInset = NSSize(width: 12, height: 10)
        section.textView.minSize = NSSize(width: 0, height: 40)
        section.textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        section.textView.isVerticallyResizable = true
        section.textView.isHorizontallyResizable = false
        section.textView.autoresizingMask = [.width]
        section.textView.textContainer?.widthTracksTextView = true

        section.scrollView.borderType = .noBorder
        section.scrollView.drawsBackground = false
        section.scrollView.focusRingType = .none
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

    func removeQASection() {
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

        let sourceText = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let resultText = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !resultText.isEmpty, PopoverFeedback.isCopyableResult(resultText) else {
            setStatus("No translation available for Q&A")
            return
        }

        guard let translator else {
            setStatus("API key is not configured")
            return
        }

        let section = qaSection ?? makeQASection()
        qaSection = section
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

        let sourceLang = selectedSourceLanguage()
        let targetLang = selectedTargetLanguage()

        translator.ask(
            question,
            sourceText: sourceText,
            translatedText: resultText,
            sourceLang: sourceLang,
            targetLang: targetLang,
            history: history
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.qaGeneration == generation, let currentSection = self.qaSection else { return }
                switch result {
                case let .success(answer):
                    currentSection.completeLastTurn(with: answer)
                case let .failure(error):
                    currentSection.completeLastTurn(with: "Error: \(error.localizedDescription)")
                }
                self.renderQASection(currentSection)
                self.reflowLayout()
                self.scrollQAToBottom(currentSection)
            }
        }
    }

    func renderQASection(_ section: QAPaneSection) {
        section.render(
            font: .systemFont(ofSize: ChromeLayout.bodyFontSize),
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
