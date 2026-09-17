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

        (qaInputField.cell as? VerticallyCenteredTextFieldCell)?.trailingInset = 22
        let quick = NSButton(frame: .zero)
        configureIconButton(quick, symbol: "text.bubble", action: #selector(showQuickQuestions(_:)), label: "Quick questions")
        quick.autoresizingMask = [.minXMargin, .minYMargin, .maxYMargin]
        qaInputField.addSubview(quick)
    }

    static let recentQuestionsKey = "qaRecentQuestions"
    static let pinnedQuestionsKey = "qaPinnedQuestions"
    static let defaultQuickQuestions = [
        "Cho tôi nghĩa cốt lõi của từ này",
        "Cho tôi nghĩa cốt lõi của từ này bằng tiếng Anh và tiếng Việt",
    ]

    /// Starred questions shown above Recent; starts as the built-in defaults.
    static var pinnedQuestions: [String] {
        get { UserDefaults.standard.stringArray(forKey: pinnedQuestionsKey) ?? defaultQuickQuestions }
        set { UserDefaults.standard.set(newValue, forKey: pinnedQuestionsKey) }
    }

    /// Keeps the quick-question button pinned to the field's trailing edge after any reflow.
    func layoutQuickQuestionButton() {
        guard let quick = qaInputField.subviews.first(where: { $0 is NSButton }) else { return }
        let size: CGFloat = 22
        let b = qaInputField.bounds
        quick.frame = NSRect(x: b.maxX - size - 6, y: (b.height - size) / 2, width: size, height: size)
    }

    @objc func showQuickQuestions(_ sender: NSButton) {
        if quickQuestionsPanel != nil {
            closeQuickQuestions()
            return
        }
        let pinned = Self.pinnedQuestions
        let recent = (UserDefaults.standard.stringArray(forKey: Self.recentQuestionsKey) ?? [])
            .filter { !pinned.contains($0) }

        let rowHeight: CGFloat = 26
        let width = max(260, qaInputField.bounds.width)
        let stack = QuickQuestionsDocumentView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        func addRow(_ question: String, isPinned: Bool) {
            let button = NSButton(title: question, target: self, action: #selector(quickQuestionPicked(_:)))
            button.isBordered = false
            button.alignment = .left
            button.lineBreakMode = .byTruncatingTail
            button.contentTintColor = Palette.bodyText
            button.toolTip = question
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            button.widthAnchor.constraint(equalToConstant: width - 16 - rowHeight).isActive = true
            let star = NSButton(frame: .zero)
            configureIconButton(star, symbol: isPinned ? "star.fill" : "star", action: #selector(toggleQuickQuestionPin(_:)), label: isPinned ? "Unpin question" : "Pin question")
            star.identifier = NSUserInterfaceItemIdentifier(question)
            star.translatesAutoresizingMaskIntoConstraints = false
            star.widthAnchor.constraint(equalToConstant: rowHeight).isActive = true
            star.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            let row = NSStackView(views: [button, star])
            row.spacing = 0
            stack.addArrangedSubview(row)
        }
        pinned.forEach { addRow($0, isPinned: true) }
        if !recent.isEmpty {
            let header = NSTextField(labelWithString: "Recent")
            header.font = .systemFont(ofSize: 11, weight: .semibold)
            header.textColor = .secondaryLabelColor
            header.heightAnchor.constraint(equalToConstant: 22).isActive = true
            stack.addArrangedSubview(header)
            recent.forEach { addRow($0, isPinned: false) }
        }
        stack.layoutSubtreeIfNeeded()
        let contentHeight = stack.fittingSize.height
        // ponytail: fixed cap of ~6 rows, scroll beyond that.
        let height = min(contentHeight, rowHeight * 6 + 30)
        stack.frame = NSRect(x: 0, y: 0, width: width, height: contentHeight)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = contentHeight > height
        scroll.autohidesScrollers = true
        scroll.documentView = stack

        let effect = NSVisualEffectView(frame: scroll.frame)
        effect.material = .menu
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 8
        effect.layer?.masksToBounds = true
        effect.addSubview(scroll)

        let fieldRect = qaInputField.window?.convertToScreen(qaInputField.convert(qaInputField.bounds, to: nil)) ?? .zero
        let quickPanel = NSPanel(
            contentRect: NSRect(x: fieldRect.maxX - width, y: fieldRect.maxY + 4, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        quickPanel.isOpaque = false
        quickPanel.backgroundColor = .clear
        quickPanel.hasShadow = true
        quickPanel.contentView = effect
        panel.addChildWindow(quickPanel, ordered: .above)
        quickQuestionsPanel = quickPanel

        // Click outside or Escape closes it; keys otherwise pass through to the field.
        quickQuestionsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
            guard let self, let quickPanel = self.quickQuestionsPanel else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    self.closeQuickQuestions()
                    return nil
                }
                return event
            }
            if event.window !== quickPanel, !(event.window === self.panel && sender.frame.contains(sender.superview?.convert(event.locationInWindow, from: nil) ?? .zero)) {
                self.closeQuickQuestions()
            }
            return event
        }
    }

    func closeQuickQuestions() {
        if let monitor = quickQuestionsMonitor { NSEvent.removeMonitor(monitor) }
        quickQuestionsMonitor = nil
        guard let quickPanel = quickQuestionsPanel else { return }
        panel.removeChildWindow(quickPanel)
        quickPanel.orderOut(nil)
        quickQuestionsPanel = nil
    }

    @objc func toggleQuickQuestionPin(_ sender: NSButton) {
        guard let question = sender.identifier?.rawValue,
              let quick = qaInputField.subviews.first(where: { $0 is NSButton }) as? NSButton else { return }
        var pinned = Self.pinnedQuestions
        if pinned.contains(question) {
            pinned.removeAll { $0 == question }
            rememberRecentQuestion(question)
        } else {
            pinned.append(question)
        }
        Self.pinnedQuestions = pinned
        closeQuickQuestions()
        showQuickQuestions(quick)
    }

    @objc func quickQuestionPicked(_ sender: NSButton) {
        closeQuickQuestions()
        qaInputField.stringValue = sender.title
        qaInputSubmitted(qaInputField)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === qaInputField else { return }
        closeQuickQuestions()
    }

    func rememberRecentQuestion(_ question: String) {
        guard !Self.pinnedQuestions.contains(question) else { return }
        var recent = UserDefaults.standard.stringArray(forKey: Self.recentQuestionsKey) ?? []
        recent.removeAll { $0 == question }
        recent.insert(question, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(3)), forKey: Self.recentQuestionsKey)
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
            let wasHidden = qaInputField.isHidden
            qaInputField.isHidden = false
            reflowLayout()
            panel.makeFirstResponder(qaInputField)
            // Opening from hidden goes straight to the quick questions; async so the field has its frame.
            if wasHidden, let quick = qaInputField.subviews.first(where: { $0 is NSButton }) as? NSButton {
                DispatchQueue.main.async { [weak self] in self?.showQuickQuestions(quick) }
            }
        } else if qaInputField.stringValue.isEmpty {
            closeQuickQuestions()
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

    /// Sub and Q&A panes explain the previous source; drop them once the source text differs.
    func closeFollowUpPanesIfSourceChanged(_ source: String) {
        defer { lastRunSource = source }
        guard source != lastRunSource else { return }
        removeSubSection()
        removeQASection()
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
        rememberRecentQuestion(question)
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

/// Top-down stacking inside the scroll view, so the list starts at the first question.
final class QuickQuestionsDocumentView: NSStackView {
    override var isFlipped: Bool { true }
}
