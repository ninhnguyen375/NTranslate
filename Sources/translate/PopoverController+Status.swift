// Result text, status line, and the busy/enabled state of the popup controls.
import AppKit

extension PopoverController {
    func setResultText(_ value: String, style: PopoverFeedback.ResultStyle? = nil) {
        let resolved = style ?? PopoverFeedback.resultStyle(for: value)
        lastResultStyle = resolved
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
        // Placeholder/error strings are literal; only real model output gets markdown.
        let display: NSAttributedString = resolved == .normal
            ? .markdownDisplay(value, font: font, color: color)
            : .plainDisplay(value, font: font, color: color)
        textView.textStorage?.setAttributedString(display)
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

    func throttleStreamReflow(scope: RequestScope) {
        let now = Date()
        let measured: CGFloat
        switch scope {
        case .main:
            measured = textView.attributedString().length == 0
                ? 0
                : PopoverLayoutMath.measuredTextHeight(textView.attributedString(), width: max(100, textView.bounds.width))
        case .sub:
            guard let section = subSection else { return }
            let attr = section.resultTextView.attributedString()
            measured = attr.length == 0
                ? 0
                : PopoverLayoutMath.measuredTextHeight(attr, width: max(100, section.resultTextView.bounds.width))
        }
        let last = scope == .main ? lastStreamedHeightMain : lastStreamedHeightSub
        let heightChanged = abs(measured - last) >= 1
        if heightChanged || now.timeIntervalSince(lastStreamReflow) >= 0.1 {
            lastStreamReflow = now
            if scope == .main {
                lastStreamedHeightMain = measured
            } else {
                lastStreamedHeightSub = measured
            }
            reflowLayout()
        }
    }

    func throttleQAStreamReflow() {
        guard let section = qaSection else { return }
        let now = Date()
        let attr = section.textView.attributedString()
        let measured = attr.length == 0
            ? 0
            : PopoverLayoutMath.measuredTextHeight(attr, width: max(100, section.textView.bounds.width))
        let heightChanged = abs(measured - lastStreamedHeightQA) >= 1
        if heightChanged || now.timeIntervalSince(lastStreamReflow) >= 0.1 {
            lastStreamReflow = now
            lastStreamedHeightQA = measured
            reflowLayout()
        }
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

    func updateBusyState() {
        let copyable = lastResultStyle == .normal
            && PopoverFeedback.isCopyableResult(textView.string, isStreaming: isRequestInFlight)
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
            && PopoverFeedback.isCopyableResult(textView.string, isStreaming: isRequestInFlight)
    }
}