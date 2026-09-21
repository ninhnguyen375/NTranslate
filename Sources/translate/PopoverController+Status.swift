// Result text, status line, and the busy/enabled state of the popup controls.
import AppKit

extension PopoverController {
    func setResultText(_ value: String, style: PopoverFeedback.ResultStyle? = nil) {
        let resolved = style ?? PopoverFeedback.resultStyle(for: value)
        lastResultStyle = resolved
        lastResultRaw = value
        let color: NSColor
        switch resolved {
        case .normal:
            color = Palette.bodyText
        case .loading:
            color = Palette.loadingText
        case .error:
            color = .systemRed
        }
        let font = NSFont.systemFont(ofSize: ChromeLayout.bodyFontSize)
        let wasBadgeHidden = learnBadgeView.isHidden
        let textToDisplay = learnBadgeView.apply(to: value, live: resolved != .error)
        // Placeholder/error strings are literal; only real model output gets markdown.
        let display: NSAttributedString = resolved == .normal
            ? .markdownDisplay(textToDisplay, font: font, color: color)
            : .plainDisplay(textToDisplay, font: font, color: color)
        textView.textStorage?.setAttributedString(display)
        textView.toolTip = nil
        applyStructuredLearnCard(raw: value, style: resolved)
        if wasBadgeHidden != learnBadgeView.isHidden, panel.contentView != nil {
            reflowLayout()
        }
        let isError = resolved == .error
        inPaneRetryButton.isHidden = !isError
        if !isError {
            setupOpenSettingsButton.isHidden = true
            setupGrantAccessButton.isHidden = true
        }
        if isError {
            announceAccessibility(value)
        }
    }

    /// Hiện thẻ có cấu trúc khi parse đủ phiên âm cùng một dòng nghĩa, mọi mode.
    func applyStructuredLearnCard(raw: String, style: PopoverFeedback.ResultStyle) {
        let show = LearnCard.shouldPresentStructured(raw, isError: style == .error)
        pinLearnCardToTop = show
        // Parsing and rebuilding the card is the most expensive thing a chunk can trigger, and the
        // stream delivers many chunks a second. While the card is already up and still loading,
        // rebuild it on the same window the layout uses. The success path ends with a non-loading
        // call; Stop ends with a loading one and resets `lastLearnCardRender` to get past this.
        if show, style == .loading, isShowingStructuredLearnCard,
           Date().timeIntervalSince(lastLearnCardRender) < Self.streamReflowInterval {
            return
        }
        if show { lastLearnCardRender = Date() }
        if show {
            let card = LearnCard.parse(raw)
            learnCardView.applyUsage(from: raw, live: false)
            learnCardView.display(card)
            if style == .normal { prefetchChipWords(card) }
            let imageTerm = LearnRelatedImage.searchTerm(from: card)
            let seed = imageTerm.isEmpty ? inputTextView.string : imageTerm
            learnRelatedImageStrip.refresh(term: seed, rewriteSource: LearnRelatedImage.senseSource(card: card, sourceText: inputTextView.string))
        } else if isShowingStructuredLearnCard {
            learnCardView.resetScrollState()
            learnCardView.applyUsage(from: "", live: false)
            learnRelatedImageStrip.clear()
        }
        if isShowingStructuredLearnCard != show {
            isShowingStructuredLearnCard = show
            textScrollView.isHidden = show
            learnCardScrollView.isHidden = !show
        }
        if show, panel.contentView != nil {
            reflowLayout()
            scrollLearnCardToTop(learnCardScrollView)
        }
    }

    func scrollLearnCardToTop(_ scrollView: NSScrollView) {
        scrollView.layoutSubtreeIfNeeded()
        guard let document = scrollView.documentView else {
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            return
        }
        let point = NSPoint(
            x: 0,
            y: document.isFlipped ? 0 : max(0, document.frame.height - scrollView.contentView.bounds.height)
        )
        document.scroll(point)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func measuredStructuredLearnCardHeight() -> CGFloat {
        let width = structuredLearnCardMeasureWidth()
        let reserve = LearnStructuredCardView.headerReserve(
            hidesPaneHeader: ChromeLayout.density.hidesPaneHeader,
            iconButtonSize: ChromeLayout.iconButtonSize
        )
        learnCardView.applyChromeReserve(reserve)
        return learnCardView.preferredHeight(fittingWidth: max(120, width))
    }

    func structuredLearnCardMeasureWidth() -> CGFloat {
        let L = ChromeLayout.self
        let contentWidth = max(0, CGFloat(config.ui.width) - L.padding * 2)
        let panes = PopoverLayoutMath.splitPaneWidth(
            contentWidth: contentWidth,
            divider: L.dividerWidth,
            ratio: mainSplitRatio
        )
        return panes.right
    }

    func measuredStructuredSubLearnCardHeight(_ section: SubtranslateSection) -> CGFloat {
        let width = structuredSubLearnCardMeasureWidth(mode: section.mode)
        let reserve = LearnStructuredCardView.headerReserve(
            hidesPaneHeader: ChromeLayout.density.hidesPaneHeader,
            iconButtonSize: ChromeLayout.iconButtonSize
        )
        section.learnCardView.applyChromeReserve(reserve)
        return section.learnCardView.preferredHeight(fittingWidth: max(120, width))
    }

    func structuredSubLearnCardMeasureWidth(mode: TranslationMode) -> CGFloat {
        let L = ChromeLayout.self
        let contentWidth = max(0, CGFloat(config.ui.width) - L.padding * 2)
        return subSectionPanes(contentWidth: contentWidth, mode: mode).right
    }

    func announceAccessibility(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: trimmed
        ])
    }

    func setStatus(_ message: String, autoClearAfter: TimeInterval = 4) {
        statusClearWorkItem?.cancel()
        statusLabel.stringValue = message
        statusLabel.isHidden = message.isEmpty
        applyStatusOverlay()
        if !message.isEmpty {
            announceAccessibility(message)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.statusLabel.stringValue = ""
                self.statusLabel.isHidden = true
                self.applyStatusOverlay()
            }
            statusClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + autoClearAfter, execute: work)
        }
    }

    func clearStatus() {
        statusClearWorkItem?.cancel()
        statusClearWorkItem = nil
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        applyStatusOverlay()
    }

    /// Only the main pane is reset here; the subtranslate pane and Q&A keep running.
    func beginRequest() -> Int {
        mainRequest?.cancel()
        mainRequest = nil
        requestGeneration += 1
        pendingSourceSpeech = pendingSourceSpeech.filter { $0.key >= requestGeneration }
        isRequestInFlight = true
        lastStreamedMain = ""
        updateBusyState()
        return requestGeneration
    }

    func finishRequest(generation: Int) {
        guard generation == requestGeneration else { return }
        isRequestInFlight = false
        mainRequest = nil
        updateBusyState()
        DispatchQueue.main.async { [weak self] in
            self?.pinLearnCardToTop = false
        }
        if lastResultStyle == .normal {
            announceAccessibility("Translation finished")
        }
    }

    func cancelRequest(scope: RequestScope) {
        switch scope {
        case .main:
            requestGeneration += 1
            mainRequest?.cancel()
            mainRequest = nil
            isRequestInFlight = false
            let current = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty || PopoverFeedback.resultStyle(for: current) == .loading, lastStreamedMain.isEmpty {
                setResultText(PopoverFeedback.stopped, style: .loading)
            }
        case .sub:
            subGeneration += 1
            subRequest?.cancel()
            subRequest = nil
            if let section = subSection {
                section.requestInFlight = false
                section.generation = subGeneration
                let current = section.resultText
                if current.isEmpty || PopoverFeedback.resultStyle(for: current) == .loading, lastStreamedSub.isEmpty {
                    setSubResultText(section, PopoverFeedback.stopped)
                }
            }
        }
        updateBusyState()
    }

    @objc func cancelMainRequest() {
        cancelRequest(scope: .main)
    }

    @objc func cancelSubRequest() {
        cancelRequest(scope: .sub)
    }

    func appendStreamedResult(_ text: String, generation: Int, scope: RequestScope = .main) {
        switch scope {
        case .main:
            guard generation == requestGeneration else { return }
            lastStreamedMain = text
            setResultText(text, style: .loading)
        case .sub:
            guard generation == subGeneration, let section = subSection else { return }
            lastStreamedSub = text
            setSubResultText(section, text, streaming: true)
        }
        throttleStreamReflow(scope: scope)
        updateCopyButtonEnabled()
    }

    /// Streaming used to measure the pane on every chunk and reflow whenever the height moved by a
    /// point. The measure itself is a full TextKit layout of the whole answer, and the layout pass
    /// that followed measured it a second time at a different width — two full layouts per chunk.
    /// A plain 100ms window costs one, and 100ms of lag is invisible while text is still arriving.
    func throttleStreamReflow(scope: RequestScope) {
        // A request outlives the panel now, so a hidden panel must not pay for layout; `presentPanel`
        // reflows when it comes back.
        guard panel.isVisible else { return }
        let lastReflow = scope == .main ? lastStreamReflowMain : lastStreamReflowSub
        guard PopoverLayoutMath.shouldReflowStream(now: Date(), last: lastReflow, interval: Self.streamReflowInterval) else {
            scheduleTrailingStreamReflow()
            return
        }
        if scope == .main {
            lastStreamReflowMain = Date()
        } else {
            lastStreamReflowSub = Date()
        }
        reflowLayout()
    }

    func throttleQAStreamReflow() {
        guard qaSection != nil else { return }
        guard PopoverLayoutMath.shouldReflowStream(now: Date(), last: lastStreamReflowQA, interval: Self.streamReflowInterval) else {
            scheduleTrailingStreamReflow()
            return
        }
        lastStreamReflowQA = Date()
        reflowLayout()
    }

    /// The chunk that arrives inside a throttle window still has to be laid out. Completion
    /// handlers reflow, but Stop does not, so a trailing pass closes that gap.
    private func scheduleTrailingStreamReflow() {
        guard streamReflowTrailing == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.streamReflowTrailing = nil
            self.reflowLayout()
        }
        streamReflowTrailing = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.streamReflowInterval, execute: work)
    }

    func applyStopAppearance(to row: ActionRowSection, stopping: Bool, isSub: Bool) {
        let previousTitle = PopoverLayoutMath.visibleActionChipTitle(of: row.translateButton)
        if stopping {
            applyAccentButtonTitle(row.translateButton, title: "Stop", symbol: "stop.circle")
            row.translateButton.toolTip = "Stop the current request"
            row.translateButton.setAccessibilityLabel("Stop")
            row.translateButton.setAccessibilityHelp("Stop the current request")
            row.translateButton.target = self
            row.translateButton.action = isSub ? #selector(cancelSubRequest) : #selector(cancelMainRequest)
            row.translateButton.isEnabled = true
        } else {
            applyAccentButtonTitle(row.translateButton, title: "Translate", symbol: "arrow.right.circle")
            row.translateButton.target = self
            row.translateButton.action = isSub ? #selector(runSubTranslate) : #selector(runTranslate)
            applyShortcutLabels(to: row)
        }
        let newTitle = stopping ? "Stop" : "Translate"
        if previousTitle != newTitle, panel.contentView != nil {
            reflowLayout()
        }
    }

    func invalidateTranslationRequest() {
        requestGeneration += 1
        isRequestInFlight = false
        mainRequest?.cancel()
        mainRequest = nil
        resolvedSourceLanguage = nil
        pendingSourceSpeech.removeAll()
        invalidateCurrentRecord()
        updateBusyState()
    }

    /// Shared entry guard for the text modes. Translate, Learn and Proofread each repeated the same
    /// empty / over-length checks with the same feedback; one copy keeps them from drifting apart.
    func isSourceTextRunnable(_ text: String, invalidatingRequest: Bool = false) -> Bool {
        let message: String
        if text.isEmpty {
            message = PopoverFeedback.emptyInputHint
        } else if text.count > config.maxTranslateLength {
            message = PopoverFeedback.textTooLong
        } else {
            return true
        }
        if invalidatingRequest { invalidateTranslationRequest() }
        setResultText(message)
        reflowLayout()
        updateBusyState()
        return false
    }

    func updateBusyState() {
        let copyable = lastResultStyle == .normal
            && PopoverFeedback.isCopyableResult(lastResultRaw, isStreaming: isRequestInFlight)
        mainActionRow.applyEnabled(
            canRun: !isRequestInFlight,
            copyable: copyable,
            imagesEnabled: PopoverIntegrationPolicy.imagesEnabled(
                isRequestInFlight: isRequestInFlight,
                hasPendingImage: pendingImage != nil,
                sourceText: inputTextView.string
            ),
            textActionsEnabled: !isRequestInFlight && pendingImage == nil
        )
        applyStopAppearance(to: mainActionRow, stopping: isRequestInFlight, isSub: false)
        swapLanguagesButton.isEnabled = !isRequestInFlight && pendingImage == nil
        sourceLanguageButton.isEnabled = !isRequestInFlight && PopoverIntegrationPolicy.sourceControlsEnabled(hasPendingImage: pendingImage != nil)
        targetLanguageButton.isEnabled = !isRequestInFlight
        retryButton.isEnabled = !isRequestInFlight && (!inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil)
        inPaneRetryButton.isEnabled = retryButton.isEnabled
        updateSpeakButtons()
        updateCopyButtonEnabled()
        updateSaveWordButton()
        updateContextButton()
        if let sub = subSection {
            updateSubButtons(sub)
        }
    }

    /// Hover tooltip on the source pane language code, only when Translate would carry reference pairs.
    func updateContextButton() {
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pendingImage == nil, !text.isEmpty else {
            sourceHeaderLabel.toolTip = nil
            return
        }
        let pair = previewLanguagePair(for: text)
        let tooltip = PopoverFeedback.contextTooltip(
            historyStore.recentContext(
                sourceLanguage: effectiveSourceLanguage(for: text),
                targetLanguage: pair.target,
                excludingText: text
            ).reversed().map { (source: $0.sourceText, target: $0.resultText) }
        )
        sourceHeaderLabel.toolTip = tooltip
        sourceHeaderLabel.setAccessibilityLabel(tooltip ?? sourceHeaderLabel.stringValue)
    }

    func updateCopyButtonEnabled() {
        copyButton.isEnabled = lastResultStyle == .normal
            && PopoverFeedback.isCopyableResult(lastResultRaw, isStreaming: isRequestInFlight)
    }
}
extension PopoverController {
    /// Cmd+Plus / Cmd+Minus / Cmd+0 on the popup. Only the source and translation body text moves.
    func applyTextZoom(_ delta: Int) {
        guard TextZoom.nudge(delta) else { return }
        TextZoom.apply(to: inputTextView)
        TextZoom.apply(to: textView)
        if let section = subSection {
            TextZoom.apply(to: section.sourceTextView)
            TextZoom.apply(to: section.resultTextView)
            if section.isShowingStructuredLearnCard {
                section.learnCardView.applyZoom()
            }
        }
        if isShowingStructuredLearnCard {
            learnCardView.applyZoom()
        }
        reflowLayout()
    }

    @objc func openLearnRelatedImage() {
        openLearnRelatedImage(strip: learnRelatedImageStrip)
    }

    func openLearnRelatedImage(strip: LearnRelatedImageStrip) {
        guard let url = strip.pageURL else { return }
        NSWorkspace.shared.open(url)
    }
}
