// Result text, status line, and the busy/enabled state of the popup controls.
import AppKit

extension PopoverController {
    func setResultText(_ value: String, style: PopoverFeedback.ResultStyle? = nil) {
        let resolved = style ?? PopoverFeedback.resultStyle(for: value)
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
    }

    func setStatus(_ message: String, autoClearAfter: TimeInterval = 4) {
        statusClearWorkItem?.cancel()
        let wasHidden = statusLabel.isHidden
        statusLabel.stringValue = message
        statusLabel.isHidden = message.isEmpty
        if wasHidden != statusLabel.isHidden {
            reflowLayout()
        }
        if !message.isEmpty {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.statusLabel.stringValue = ""
                if !self.statusLabel.isHidden {
                    self.statusLabel.isHidden = true
                    self.reflowLayout()
                }
            }
            statusClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + autoClearAfter, execute: work)
        }
    }

    func clearStatus() {
        statusClearWorkItem?.cancel()
        statusClearWorkItem = nil
        let wasHidden = statusLabel.isHidden
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        if !wasHidden {
            reflowLayout()
        }
    }

    func beginRequest() -> Int {
        requestGeneration += 1
        pendingSourceSpeech = pendingSourceSpeech.filter { $0.key >= requestGeneration }
        isRequestInFlight = true
        updateBusyState()
        return requestGeneration
    }

    func finishRequest(generation: Int) {
        guard generation == requestGeneration else { return }
        isRequestInFlight = false
        updateBusyState()
    }

    func invalidateTranslationRequest() {
        requestGeneration += 1
        isRequestInFlight = false
        resolvedSourceLanguage = nil
        pendingSourceSpeech.removeAll()
        invalidateCurrentRecord()
        updateBusyState()
    }

    func updateBusyState() {
        translateButton.isEnabled = !isRequestInFlight
        learnButton.isEnabled = !isRequestInFlight && pendingImage == nil
        proofreadButton.isEnabled = !isRequestInFlight && pendingImage == nil
        imagesButton.isEnabled = PopoverIntegrationPolicy.imagesEnabled(
            isRequestInFlight: isRequestInFlight,
            hasPendingImage: pendingImage != nil,
            sourceText: inputTextView.string
        )
        swapLanguagesButton.isEnabled = !isRequestInFlight && pendingImage == nil
        sourceLanguageButton.isEnabled = !isRequestInFlight && PopoverIntegrationPolicy.sourceControlsEnabled(hasPendingImage: pendingImage != nil)
        targetLanguageButton.isEnabled = !isRequestInFlight
        retryButton.isEnabled = !isRequestInFlight && (!inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil)
        updateSpeakButtons()
        updateCopyButtonEnabled()
        updateSaveWordButton()
        updateContextButton()
        if let sub = subSection {
            updateSubButtons(sub)
        }
    }

    /// Shows the context indicator only when the next Translate would actually carry reference pairs.
    func updateContextButton() {
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pendingImage == nil, !text.isEmpty else {
            contextButton.isHidden = true
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
        contextButton.toolTip = tooltip
        contextButton.setAccessibilityLabel(tooltip ?? "Translation context")
        contextButton.isHidden = tooltip == nil
    }

    /// Clicking the indicator surfaces the same list as the tooltip, for keyboard/VoiceOver users.
    @objc func showContextTooltip() {
        guard let tooltip = contextButton.toolTip else { return }
        setStatus(tooltip.replacingOccurrences(of: "\n", with: "  "), autoClearAfter: 10)
    }

    func updateCopyButtonEnabled() {
        copyButton.isEnabled = PopoverFeedback.isCopyableResult(textView.string)
    }
}