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
        configureIconButton(section.speakSourceSlowButton, symbol: "tortoise", action: #selector(speakSubSourceSlow), label: "Speak subtranslate source slowly")
        configureIconButton(section.speakResultButton, symbol: "speaker.wave.2", action: #selector(speakSubResult), label: "Speak subtranslate translation")
        configureIconButton(section.speakResultSlowButton, symbol: "tortoise", action: #selector(speakSubResultSlow), label: "Speak subtranslate translation slowly")
        configureIconButton(section.retryButton, symbol: "arrow.clockwise", action: #selector(retrySubRequest), label: "Retry / Fetch fresh subtranslate")
        configureIconButton(section.copyButton, symbol: "doc.on.doc", action: #selector(copySubResult), label: "Copy subtranslate")
        configureIconButton(section.saveWordButton, symbol: "bookmark", action: #selector(toggleSaveSubWord), label: "Save subtranslate")
        configureIconButton(section.closeButton, symbol: "xmark", action: #selector(closeSubtranslate), label: "Close subtranslate")

        section.sourceHeaderBar.addSubview(section.sourceHeaderLabel)
        section.sourceHeaderBar.addSubview(section.speakSourceButton)
        section.sourceHeaderBar.addSubview(section.speakSourceSlowButton)
        section.sourceCard.addSubview(section.sourceHeaderBar)
        section.sourceCard.addSubview(section.sourceScrollView)

        section.resultHeaderBar.addSubview(section.resultHeaderLabel)
        section.resultHeaderBar.addSubview(section.speakResultButton)
        section.resultHeaderBar.addSubview(section.speakResultSlowButton)
        section.resultHeaderBar.addSubview(section.retryButton)
        section.resultHeaderBar.addSubview(section.copyButton)
        section.resultHeaderBar.addSubview(section.saveWordButton)
        section.resultHeaderBar.addSubview(section.closeButton)
        section.resultCard.addSubview(section.resultHeaderBar)
        section.resultCard.addSubview(section.resultScrollView)

        for textView in [section.sourceTextView, section.resultTextView] {
            textView.delegate = self
        }
        configureActionRow(section.actionRow, isSub: true)
        section.actionRow.addToSuperview(chromeHost)
        configureSectionDivider(section)
        chromeHost.addSubview(section.sectionDivider)

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
            trailingIcons: [section.speakSourceButton, section.speakSourceSlowButton],
            paneWidth: panes.left,
            bodyHeight: bodyHeight
        )
        layoutPaneChrome(
            headerBar: section.resultHeaderBar,
            headerLabel: section.resultHeaderLabel,
            scrollView: section.resultScrollView,
            textView: section.resultTextView,
            trailingIcons: [section.speakResultButton, section.speakResultSlowButton, section.retryButton, section.copyButton, section.saveWordButton, section.closeButton],
            paneWidth: panes.right,
            bodyHeight: bodyHeight
        )
    }

    func configureSectionDivider(_ section: SubtranslateSection) {
        section.sectionDividerLabel.stringValue = "Subtranslate"
        section.sectionDividerLabel.font = .systemFont(ofSize: 11, weight: .medium)
        section.sectionDividerLabel.textColor = Palette.mutedText
        section.sectionDividerLabel.alignment = .center
        section.sectionDividerLabel.isBezeled = false
        section.sectionDividerLabel.drawsBackground = false
        section.sectionDividerLabel.isEditable = false
        section.sectionDividerLabel.isSelectable = false
        section.sectionDividerLeft.wantsLayer = true
        section.sectionDividerRight.wantsLayer = true
        section.sectionDivider.addSubview(section.sectionDividerLeft)
        section.sectionDivider.addSubview(section.sectionDividerRight)
        section.sectionDivider.addSubview(section.sectionDividerLabel)
    }

    func layoutSectionDivider(_ section: SubtranslateSection, x: CGFloat, y: CGFloat, width: CGFloat) {
        let visualH = ChromeLayout.sectionDividerHeight
        let reserved = ChromeLayout.sectionDividerReserved
        section.sectionDivider.frame = NSRect(x: x, y: y, width: width, height: reserved)
        section.sectionDividerLabel.sizeToFit()
        let frames = PopoverLayoutMath.labeledHairlineDivider(
            width: width,
            height: visualH,
            labelWidth: ceil(section.sectionDividerLabel.fittingSize.width)
        )
        section.sectionDividerLeft.frame = frames.left
        section.sectionDividerLabel.frame = frames.label
        section.sectionDividerRight.frame = frames.right
        let lineColor = Palette.cg(Palette.hairline, in: section.sectionDivider)
        section.sectionDividerLeft.layer?.backgroundColor = lineColor
        section.sectionDividerRight.layer?.backgroundColor = lineColor
    }

    @objc func closeSubtranslate() {
        removeSubSection()
        reflowLayout()
    }

    func removeSubSection() {
        subGeneration += 1
        subSection?.requestInFlight = false
        if qaTargetsSub {
            qaTargetsSub = false
            qaInputField.placeholderString = "Ask follow-up questions about translation..."
        }
        if currentFloatingIsSub { hideFloatingSelectionBar() }
        subSection?.removeFromSuperview()
        subSection = nil
    }

    func setSubResultText(
        _ section: SubtranslateSection,
        _ value: String,
        streaming: Bool = false,
        style: PopoverFeedback.ResultStyle? = nil
    ) {
        let style = style ?? (streaming ? .loading : PopoverFeedback.resultStyle(for: value))
        let color: NSColor
        switch style {
        case .normal: color = Palette.bodyText
        case .loading: color = Palette.loadingText
        case .error: color = .systemRed
        }
        section.setResult(
            value,
            font: .systemFont(ofSize: ChromeLayout.bodyFontSize),
            color: color,
            markdown: style == .normal
        )
        updateSubButtons(section)
    }

    func updateSubButtons(_ section: SubtranslateSection) {
        let copyable = PopoverFeedback.isCopyableResult(section.resultText, isStreaming: section.requestInFlight)
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

        let canRun = !section.requestInFlight && !section.sourceText.isEmpty
        section.retryButton.isEnabled = canRun
        section.actionRow.applyEnabled(
            canRun: canRun,
            copyable: copyable,
            imagesEnabled: PopoverIntegrationPolicy.imagesEnabled(
                isRequestInFlight: section.requestInFlight,
                hasPendingImage: false,
                sourceText: section.sourceText
            )
        )
        applyStopAppearance(to: section.actionRow, stopping: section.requestInFlight, isSub: true)
    }

    /// The sub row's Translate / Learn / Proofread re-run against the sub pane's own source and
    /// overwrite the sub pane in place — they never spawn a third pane.
    func runSubMode(_ mode: TranslationMode) {
        guard let section = subSection, !section.sourceText.isEmpty, !section.requestInFlight else { return }
        runSubRequest(text: section.sourceText, mode: mode, bypassCache: true)
    }

    @objc func runSubTranslate() { runSubMode(.translate) }
    @objc func runSubLearn() { runSubMode(.learn) }
    @objc func runSubProofread() { runSubMode(.proofread) }

    /// Runs Translate or Learn for a freshly selected phrase into the secondary pane, leaving the
    /// main pane untouched.
    func runSubRequest(text: String, mode: TranslationMode, bypassCache: Bool = false) {
        guard let translator else { return }
        if let existing = subSection, existing.requestInFlight { return }
        guard text.count <= config.maxTranslateLength else {
            setStatus(PopoverFeedback.textTooLong)
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if !bypassCache,
           let existing = subSection,
           existing.mode == mode,
           existing.sourceText == trimmed {
            if existing.generation == subGeneration {
                return
            }
            if PopoverFeedback.isCopyableResult(existing.resultText),
               existing.sourceLanguage == displaySource,
               existing.targetLanguage == pair.target {
                return
            }
        }
        let section = subSection ?? makeSubSection()
        subSection = section
        subGeneration += 1
        let generation = subGeneration
        section.generation = generation
        section.mode = mode
        section.recordID = nil
        section.sourceLanguage = displaySource
        section.targetLanguage = pair.target
        section.sourceHeaderLabel.stringValue = paneLanguageCode(displaySource)
        section.resultHeaderLabel.stringValue = paneLanguageCode(pair.target)
        section.setSource(text, font: .systemFont(ofSize: ChromeLayout.bodyFontSize), color: Palette.bodyText)
        subRequest?.cancel()
        subRequest = nil
        lastStreamedSub = ""
        section.requestInFlight = true
        let waitingText: String
        switch mode {
        case .learn: waitingText = PopoverFeedback.learning
        case .proofread: waitingText = PopoverFeedback.proofreading
        case .translate: waitingText = PopoverFeedback.translating
        }
        setSubResultText(section, waitingText)
        reflowLayout()
        // The sub source is known now, so its speech fetches alongside the model call.
        prefetchSpeech(subSpeechIdentity(kind: .source), translationGeneration: nil)

        if !bypassCache, let record = reusableSubRecord(
            mode: mode,
            text: text,
            sourceLanguage: displaySource,
            targetLanguage: pair.target
        ) {
            finishSubRequest(generation: generation, text: text, mode: mode, pair: (displaySource, pair.target), result: .success(record.resultText), existingRecord: record)
            return
        }
        if !bypassCache, mode == .learn, Translator.isDictionaryTerm(text) {
            let parent = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            // Sub-learn normally explains a word inside its sentence. The pack was generated
            // without any context, so it may only answer when there is no parent sentence.
            if parent.isEmpty || parent == text,
               let packed = VocabPack.shared.lookup(
                   text,
                   sourceLanguage: displaySource,
                   targetLanguage: pair.target,
                   sourceIsAutoDetect: selectedSourceLanguage() == LanguageDetector.autoDetect
               ) {
                finishSubRequest(
                    generation: generation, text: text, mode: mode,
                    pair: (displaySource, pair.target), result: .success(packed), existingRecord: nil
                )
                return
            }
        }

        let handler: @Sendable (Result<String, Error>) -> Void = { [weak self] result in
            Task { @MainActor in
                self?.finishSubRequest(
                    generation: generation, text: text, mode: mode,
                    pair: (displaySource, pair.target), result: result, existingRecord: nil
                )
            }
        }
        let onPartial: @Sendable (String) -> Void = { [weak self] partial in
            Task { @MainActor in
                self?.appendStreamedResult(partial, generation: generation, scope: .sub)
            }
        }
        if mode == .proofread {
            subRequest = translator.proofread(text, lang: displaySource, onPartial: onPartial, completion: handler)
        } else if mode == .learn {
            subRequest = translator.learn(text, sourceLang: displaySource, targetLang: pair.target, parentContext: inputTextView.string, onPartial: onPartial, completion: handler)
        } else {
            let context = historyStore.recentContext(
                sourceLanguage: displaySource,
                targetLanguage: pair.target,
                excludingText: text
            ).reversed().map { ContextPair(source: $0.sourceText, target: $0.resultText) }
            subRequest = translator.translate(
                text,
                sourceLang: displaySource,
                targetLang: pair.target,
                context: context,
                parentContext: inputTextView.string,
                onPartial: onPartial
            ) { result in
                handler(result.map(\.text))
            }
        }
    }

    func reusableSubRecord(
        mode: TranslationMode,
        text: String,
        sourceLanguage: String,
        targetLanguage: String
    ) -> TranslationRecord? {
        let autoDetect = selectedSourceLanguage() == LanguageDetector.autoDetect
        if let record = historyStore.reusableRecord(
            mode: mode,
            sourceText: text,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceIsAutoDetect: autoDetect
        ) {
            return record
        }
        guard mode == .learn else { return nil }
        let parent = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !parent.isEmpty, parent != text else { return nil }
        return historyStore.reusableRecord(
            mode: mode,
            sourceText: "\(text) (context: \(parent))",
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            sourceIsAutoDetect: autoDetect
        )
    }

    @objc func retrySubRequest() {
        guard let section = subSection, !section.sourceText.isEmpty, !section.requestInFlight else { return }
        clearAudioCache(recordID: section.recordID)
        runSubRequest(text: section.sourceText, mode: section.mode, bypassCache: true)
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
        section.requestInFlight = false
        subRequest = nil
        switch result {
        case let .success(value):
            lastStreamedSub = ""
            setSubResultText(section, value)
            if let existingRecord {
                section.recordID = existingRecord.id
            } else {
                let parent = self.inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
                let recordedSource: String
                if mode == .learn && !parent.isEmpty && parent != text {
                    recordedSource = "\(text) (context: \(parent))"
                } else {
                    recordedSource = text
                }
                let record = TranslationRecord(
                    id: UUID(), timestamp: Date(), mode: mode, sourceText: recordedSource, resultText: value,
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
            let message = PopoverFeedback.userFacingError(error)
            if message == PopoverFeedback.stopped {
                if lastStreamedSub.isEmpty {
                    setSubResultText(section, PopoverFeedback.stopped)
                }
            } else if !lastStreamedSub.isEmpty,
                      (lastStreamedSub.hasPrefix("{") || lastStreamedSub.hasPrefix("```")),
                      error is Translator.ResponseError {
                setSubResultText(section, lastStreamedSub, style: .error)
            } else {
                setSubResultText(section, message)
            }
        }
        updateSubButtons(section)
        prefetchSpeech(subSpeechIdentity(kind: .source), translationGeneration: nil)
        prefetchSpeech(subSpeechIdentity(kind: .result), translationGeneration: nil)
        reflowLayout()
        section.resultTextView.scrollToBeginningOfDocument(nil)
    }

    func subSpeechIdentity(kind: SpeechKind) -> SpeechIdentity? {
        guard let section = subSection else { return nil }
        let text = kind == .source ? section.sourceText : section.resultText
        guard kind == .source
            ? !text.isEmpty
            : PopoverFeedback.isCopyableResult(text, isStreaming: section.requestInFlight)
        else { return nil }
        let language = kind == .source ? section.sourceLanguage : section.targetLanguage
        return SpeechIdentity(
            kind: kind,
            text: text,
            model: SpeechModelResolver.model(for: language, config: config),
            recordID: section.recordID
        )
    }

    @objc func speakSubSource() { playSpeech(subSpeechIdentity(kind: .source), speed: 1.0) }
    @objc func speakSubSourceSlow() { playSpeech(subSpeechIdentity(kind: .source), speed: config.speechSlowRate) }
    @objc func speakSubResult() { playSpeech(subSpeechIdentity(kind: .result), speed: 1.0) }
    @objc func speakSubResultSlow() { playSpeech(subSpeechIdentity(kind: .result), speed: config.speechSlowRate) }

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

        let sourceText = record.sourceText
        if let range = sourceText.range(of: " (context: ") {
            let term = String(sourceText[..<range.lowerBound])
            var context = String(sourceText[range.upperBound...])
            if context.hasSuffix(")") {
                context = String(context.dropLast())
            }
            inputTextView.string = term
            inputContextLabel.stringValue = "Context: \(context)"
            inputContextLabel.toolTip = context
            inputContextLabel.isHidden = false
        } else {
            inputTextView.string = sourceText
            inputContextLabel.stringValue = ""
            inputContextLabel.toolTip = nil
            inputContextLabel.isHidden = true
        }
        setResultText(record.resultText)

        currentRecordID = record.id
        lastExecutionMode = record.mode
        updateBusyState()
        updatePaneLanguageLabels()

        focusInputTextView()
        reflowLayout()
    }

    // MARK: - Floating Selection Toolbar

    func configureFloatingToolbar() {
        selectionFloatingBar.state = .active
        // `.hudWindow` stays dark in light mode, which washes out the dark icon tint.
        selectionFloatingBar.material = .menu
        selectionFloatingBar.blendingMode = .withinWindow
        selectionFloatingBar.wantsLayer = true
        selectionFloatingBar.layer?.cornerRadius = 14
        selectionFloatingBar.layer?.cornerCurve = .continuous
        selectionFloatingBar.layer?.masksToBounds = true
        selectionFloatingBar.layer?.borderWidth = 1
        selectionFloatingBar.isHidden = true

        configureFloatingButton(floatingQuickButton, symbol: "bolt.horizontal.circle", action: #selector(floatingQuickTranslateClicked), label: "Quick Translate")
        configureFloatingButton(floatingTranslateButton, symbol: "arrow.right.circle", action: #selector(floatingTranslateClicked), label: "Subtranslate")
        configureFloatingButton(floatingLearnButton, symbol: "brain.head.profile", action: #selector(floatingLearnClicked), label: "Learn Phrase")
        configureFloatingButton(floatingSpeakButton, symbol: "speaker.wave.2", action: #selector(floatingSpeakClicked), label: "Speak Phrase")
        configureFloatingButton(floatingCopyButton, symbol: "doc.on.doc", action: #selector(floatingCopyClicked), label: "Copy Phrase")

        floatingResultLabel.font = .systemFont(ofSize: ChromeLayout.bodyFontSize - 1)
        floatingResultLabel.textColor = Palette.bodyText
        floatingResultLabel.lineBreakMode = .byWordWrapping
        floatingResultLabel.maximumNumberOfLines = 0
        floatingResultLabel.isSelectable = true
        floatingResultLabel.isHidden = true

        let buttonRow = NSStackView(views: [floatingQuickButton, floatingTranslateButton, floatingLearnButton, floatingSpeakButton, floatingCopyButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 4

        let stack = NSStackView(views: [buttonRow, floatingResultLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
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

    /// Every pane the floating selection bar can attach to: main source/result plus, when the
    /// subtranslate pane is open, its own source/result.
    func floatingSelectionCandidates() -> [(textView: NSTextView, scrollView: NSScrollView, isResult: Bool, isSub: Bool)] {
        var list: [(NSTextView, NSScrollView, Bool, Bool)] = [
            (inputTextView, inputScrollView, false, false),
            (textView, textScrollView, true, false),
        ]
        if let sub = subSection {
            list.append((sub.sourceTextView, sub.sourceScrollView, false, true))
            list.append((sub.resultTextView, sub.resultScrollView, true, true))
        }
        return list.map { (textView: $0.0, scrollView: $0.1, isResult: $0.2, isSub: $0.3) }
    }

    func updateFloatingSelectionBar() {
        let candidates = floatingSelectionCandidates()
        let firstResponder = panel.firstResponder as? NSTextView
        let selected = candidates.filter { $0.textView.selectedRange().length > 0 }
        // The focused pane wins; otherwise only an unambiguous single selection counts.
        guard let active = selected.first(where: { $0.textView === firstResponder })
            ?? (selected.count == 1 ? selected[0] : nil)
        else {
            hideFloatingSelectionBar()
            return
        }
        let activeTextView = active.textView
        let activeScrollView = active.scrollView

        let range = activeTextView.selectedRange()
        guard let bounds = Range(range, in: activeTextView.string) else {
            hideFloatingSelectionBar()
            return
        }
        let text = activeTextView.string[bounds].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            hideFloatingSelectionBar()
            return
        }
        if text != floatingResultForText { applyFloatingResultLabel(nil) }
        currentFloatingSelectedText = text
        currentFloatingIsResult = active.isResult
        currentFloatingIsSub = active.isSub

        guard let layoutManager = activeTextView.layoutManager,
              let textContainer = activeTextView.textContainer
        else {
            hideFloatingSelectionBar()
            return
        }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rectInTextView = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        let rectInScroll = activeTextView.convert(rectInTextView, to: activeScrollView)
        guard activeScrollView.bounds.intersects(rectInScroll) else {
            hideFloatingSelectionBar()
            return
        }

        let rectInChrome = activeTextView.convert(rectInTextView, to: chromeHost)
        let availableWidth = max(0, chromeHost.bounds.width - ChromeLayout.padding * 2)
        let preferredWidth = floatingResultLabel.isHidden ? 140 : min(300, max(160, availableWidth))
        let barWidth = min(preferredWidth, availableWidth)
        floatingResultLabel.preferredMaxLayoutWidth = max(0, barWidth - 12)
        let barHeight: CGFloat = floatingResultLabel.isHidden
            ? 28
            : 32 + ceil(floatingResultLabel.intrinsicContentSize.height)
        let barX = max(ChromeLayout.padding, min(rectInChrome.midX - barWidth / 2, chromeHost.bounds.width - ChromeLayout.padding - barWidth))
        let barY: CGFloat
        let gap: CGFloat = 12
        if rectInChrome.minY - barHeight - gap >= ChromeLayout.paddingBottom {
            barY = rectInChrome.minY - barHeight - gap
        } else {
            barY = min(chromeHost.bounds.height - barHeight - ChromeLayout.padding, rectInChrome.maxY + gap)
        }

        selectionFloatingBar.frame = NSRect(x: barX, y: barY, width: barWidth, height: barHeight)
        selectionFloatingBar.layer?.borderColor = Palette.cg(Palette.hairline, in: selectionFloatingBar)
        updateSpeechButton(floatingSpeakButton, identity: floatingSpeechIdentity(), baseLabel: "phrase")
        selectionFloatingBar.isHidden = false
        chromeHost.addSubview(selectionFloatingBar, positioned: .above, relativeTo: nil)
    }

    /// Translate a selected phrase for the floating bar. History cache is checked first, so a
    /// repeated phrase costs no API call.
    func runFloatingTranslate(_ text: String) {
        guard let translator else { return }
        guard text.count <= config.maxTranslateLength else {
            setStatus(PopoverFeedback.textTooLong)
            return
        }
        floatingRequestGeneration += 1
        let generation = floatingRequestGeneration
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
        var target = pair.target
        if target == displaySource {
            let selected = selectedSourceLanguage()
            target = selected != LanguageDetector.autoDetect && selected != displaySource
                ? selected
                : config.resolvedNativeLang
        }
        guard target != displaySource else {
            setFloatingResult(nil)
            setStatus("Already in \(paneLanguageCode(target))")
            return
        }
        if let record = reusableSubRecord(mode: .translate, text: text, sourceLanguage: displaySource, targetLanguage: target),
           PopoverFeedback.isCopyableResult(record.resultText) {
            setFloatingResult(record.resultText)
            return
        }

        setFloatingResult(PopoverFeedback.translating)
        let context = historyStore.recentContext(
            sourceLanguage: displaySource,
            targetLanguage: target,
            excludingText: text
        ).reversed().map { ContextPair(source: $0.sourceText, target: $0.resultText) }
        translator.translate(text, sourceLang: displaySource, targetLang: target, context: context, parentContext: inputTextView.string, stream: false) { [weak self] result in
            Task { @MainActor in
                guard let self, self.floatingRequestGeneration == generation,
                      self.currentFloatingSelectedText == text else { return }
                switch result {
                case .success(let value): self.setFloatingResult(value.text)
                case .failure(let error): self.setFloatingResult("Error: \(error.localizedDescription)")
                }
            }
        }
    }

    private func applyFloatingResultLabel(_ text: String?) {
        let value = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        floatingResultForText = value.isEmpty ? nil : currentFloatingSelectedText
        guard value != floatingResultLabel.stringValue else { return }
        floatingResultLabel.stringValue = value
        floatingResultLabel.isHidden = value.isEmpty
    }

    /// Show or clear the inline result, then re-lay the bar around the current selection.
    func setFloatingResult(_ text: String?) {
        let previous = floatingResultLabel.stringValue
        applyFloatingResultLabel(text)
        if previous != floatingResultLabel.stringValue, !selectionFloatingBar.isHidden {
            updateFloatingSelectionBar()
        }
    }

    func hideFloatingSelectionBar() {
        floatingRequestGeneration += 1
        applyFloatingResultLabel(nil)
        selectionFloatingBar.isHidden = true
        currentFloatingSelectedText = nil
        currentFloatingIsResult = false
        currentFloatingIsSub = false
    }

    @objc func floatingQuickTranslateClicked() {
        guard let text = currentFloatingSelectedText else { return }
        runFloatingTranslate(text)
    }

    @objc func floatingTranslateClicked() {
        guard let text = currentFloatingSelectedText else { return }
        runSubRequest(text: text, mode: .translate, bypassCache: false)
    }

    @objc func floatingLearnClicked() {
        guard let text = currentFloatingSelectedText else { return }
        runSubRequest(text: text, mode: .learn, bypassCache: false)
    }

    /// Speech identity for whatever phrase the floating bar is currently attached to. A phrase picked
    /// inside the subtranslate pane takes that pane's languages, not the main selectors'.
    func floatingSpeechIdentity() -> SpeechIdentity? {
        guard let text = currentFloatingSelectedText, !text.isEmpty else { return nil }
        let isResult = currentFloatingIsResult
        let paneLang: String
        if currentFloatingIsSub, let sub = subSection {
            paneLang = isResult ? sub.targetLanguage : sub.sourceLanguage
        } else {
            paneLang = isResult ? selectedTargetLanguage() : effectiveSourceLanguage(for: text)
        }
        // The pane language describes the whole text; a selected phrase can be another language,
        // so detection on the phrase itself wins when it is confident.
        let lang = LanguageDetector.detectedPhraseLanguage(text, candidates: config.languages) ?? paneLang
        let model = SpeechModelResolver.model(for: lang, config: config)
        return SpeechIdentity(kind: isResult ? .result : .source, text: text, model: model, recordID: nil)
    }

    @objc func floatingSpeakClicked() {
        playSpeech(floatingSpeechIdentity(), speed: 1.0)
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