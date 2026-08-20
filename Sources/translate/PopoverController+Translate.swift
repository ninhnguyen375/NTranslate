// Translate / Learn / Images requests, history records, and copy-out of the result.
import AppKit
import Carbon.HIToolbox

extension PopoverController {
    func translateAtCursor(forceSimulatedCopy: Bool = false) {
        // Read the selection once — simulated copy posts real key events, so a second read would
        // fire Command+C twice.
        guard let resolved = readSelection(forceSimulatedCopy: forceSimulatedCopy) else { return }
        if let text = subtranslateText(from: resolved) {
            runSubRequest(text: text, mode: .translate)
            return
        }
        guard prepareInputFromSelection(resolved) else { return }
        let generation = beginRequest()
        setResultText(PopoverFeedback.translating)
        reflowLayout()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        performTranslate(generation: generation)
    }

    /// Returns the selected text when it should land in the subtranslate pane instead of replacing
    /// the main pane. Returns nil when the caller should take the normal path.
    func subtranslateText(from resolved: TranslatableInputResolution) -> String? {
        guard PopoverIntegrationPolicy.usesSubtranslate(
            panelVisible: panel.isVisible,
            primaryResult: textView.string,
            hasPendingImage: pendingImage != nil
        ), case let .text(text) = resolved.input else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Re-firing on the same text the main pane already holds should refresh it, not spawn a
        // duplicate pane.
        guard !trimmed.isEmpty,
              trimmed != inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return trimmed
    }

    /// Reads the current selection. Returns nil after showing the relevant failure panel (missing
    /// Accessibility, empty selection, read error).
    func readSelection(forceSimulatedCopy: Bool) -> TranslatableInputResolution? {
        // Without Accessibility both paths are dead (no AXSelectedText, no synthetic Command+C),
        // so prompt and stop instead of silently translating stale clipboard content.
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermissionIfNeeded(forcePrompt: true)
            showEmptySelectionPanel(message: PopoverFeedback.accessibilityRequired)
            return nil
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        do {
            guard let value = try SelectionReader.resolveTranslatableInputWithDiagnostics(
                simulateCopy: PopoverIntegrationPolicy.shouldSimulateCopy(force: forceSimulatedCopy, configured: config.ui.simulateCopy),
                forceCopy: forceSimulatedCopy
            ) else {
                showEmptySelectionPanel()
                return nil
            }
            return value
        } catch {
            showEmptySelectionPanel(message: "Error: \(error)")
            return nil
        }
    }

    /// Loads an already-read selection into the main input pane. Returns false when it handled the
    /// failure path (over-length text) and the caller should stop.
    func prepareInputFromSelection(_ resolved: TranslatableInputResolution) -> Bool {
        if !panel.isVisible { showMousePoint = NSEvent.mouseLocation }
        if resolved.accessibilityError != nil {
            setStatus(PopoverFeedback.accessibilityFallbackNote(source: resolved.source))
        } else {
            clearStatus()
        }
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        switch resolved.input {
        case let .text(text):
            setPendingImage(nil)
            inputTextView.string = text
            guard text.count <= config.maxTranslateLength else {
                setResultText(PopoverFeedback.textTooLong)
                reflowLayout()
                updateBusyState()
                presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
                return false
            }
            updateLanguageSelection(for: text)
        case let .image(data):
            inputTextView.string = ""
            setPendingImage(data)
        }
        return true
    }

    @objc func runTranslate() {
        if let text = panelSelectionForSubtranslate() {
            runSubRequest(text: text, mode: .translate)
            return
        }
        invalidateSpeech(stopPlayback: true)
        performTranslate(generation: nil)
    }

    /// Text highlighted inside the popup that the Translate/Learn buttons should send to the
    /// subtranslate pane instead of re-running the whole input. Nil when nothing is selected or the
    /// popup isn't in a state that supports a secondary pane — the buttons then behave normally.
    func panelSelectionForSubtranslate() -> String? {
        guard PopoverIntegrationPolicy.usesSubtranslate(
            panelVisible: panel.isVisible,
            primaryResult: textView.string,
            hasPendingImage: pendingImage != nil
        ) else { return nil }
        let views = [inputTextView, textView] + (subSection.map { [$0.sourceTextView, $0.resultTextView] } ?? [])
        for view in views {
            let text = view.string
            let range = view.selectedRange()
            guard range.length > 0, let bounds = Range(range, in: text) else { continue }
            let trimmed = text[bounds].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  trimmed != inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            else { continue }
            return trimmed
        }
        return nil
    }

    func performTranslate(generation existingGeneration: Int?) {
        invalidateCurrentRecord()
        let generation = existingGeneration ?? beginRequest()
        guard let translator else {
            finishRequest(generation: generation)
            return
        }
        if existingGeneration == nil {
            setResultText(PopoverFeedback.translating)
            reflowLayout()
        }
        if let image = pendingImage {
            translator.translateImage(image, targetLang: selectedTargetLanguage()) { [weak self] result in
                Task { @MainActor in self?.finishImageTranslation(result, generation: generation) }
            }
            return
        }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            invalidateTranslationRequest()
            setResultText(PopoverFeedback.emptyInputHint)
            reflowLayout()
            updateBusyState()
            return
        }
        guard text.count <= config.maxTranslateLength else {
            invalidateTranslationRequest()
            setResultText(PopoverFeedback.textTooLong)
            reflowLayout()
            updateBusyState()
            return
        }
        let sourceWasAutoDetect = selectedSourceLanguage() == LanguageDetector.autoDetect
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        if let record = historyStore.reusableRecord(
            mode: .translate,
            sourceText: text,
            sourceLanguage: pair.source,
            targetLanguage: pair.target,
            sourceIsAutoDetect: sourceWasAutoDetect
        ) {
            applyReusableRecord(record, mode: .translate, generation: generation)
            finishRequest(generation: generation)
            return
        }
        if PopoverIntegrationPolicy.shouldPrefetchSource(
            enabled: config.autoPrefetchSpeech,
            hasPendingImage: pendingImage != nil,
            text: text
        ), PopoverIntegrationPolicy.shouldPrefetchSource(
            selected: selectedSourceLanguage(),
            resolved: resolvedSourceLanguage
        ) {
            prefetchSpeech(sourceSpeechIdentity(recordID: nil), translationGeneration: generation)
        }
        // Recent same-pair translations keep terminology and tone consistent across a document.
        let context = historyStore.recentContext(
            sourceLanguage: effectiveSourceLanguage(for: text),
            targetLanguage: pair.target,
            excludingText: text
        ).reversed().map { ContextPair(source: $0.sourceText, target: $0.resultText) }
        translator.translate(text, sourceLang: pair.source, targetLang: pair.target, context: context) { [weak self] result in
            Task { @MainActor in self?.finishTextTranslation(result, generation: generation, source: text, pair: pair) }
        }
    }

    func finishImageTranslation(_ result: Result<String, Error>, generation: Int) {
        defer { finishRequest(generation: generation) }
        guard generation == requestGeneration, pendingImage != nil else { return }
        invalidateCurrentRecord()
        switch result {
        case let .success(value):
            setResultText(value)
            prefetchSpeech(resultSpeechIdentity(), translationGeneration: nil)
        case let .failure(error):
            setResultText("Error: \(error.localizedDescription)")
        }
        reflowLayout()
        textView.scrollToBeginningOfDocument(nil)
        updateBusyState()
    }

    func finishTextTranslation(_ result: Result<TranslationResult, Error>, generation: Int, source: String, pair: (source: String, target: String)) {
        defer { finishRequest(generation: generation) }
        guard generation == requestGeneration, pendingImage == nil else { return }
        switch result {
        case let .success(value):
            if selectedSourceLanguage() == LanguageDetector.autoDetect {
                resolvedSourceLanguage = value.sourceLanguage
            }
            let sourceLanguage = effectiveSourceLanguage(for: source)
            let record = TranslationRecord(
                id: UUID(), timestamp: Date(), mode: .translate, sourceText: source, resultText: value.text,
                sourceLanguage: sourceLanguage, targetLanguage: pair.target,
                sourceAudioPath: nil, resultAudioPath: nil, isSaved: false
            )
            setResultText(value.text)
            do {
                let stored = try historyStore.appendIfAbsent(record)
                if stored.id != record.id {
                    pendingSourceSpeech.removeValue(forKey: generation)
                    applyReusableRecord(stored, mode: .translate, generation: generation)
                } else {
                    currentRecordID = stored.id
                    attachPendingSourceSpeech(for: generation, recordID: stored.id)
                    historyWindowController.reloadHistory()
                    prefetchSpeech(sourceSpeechIdentity(recordID: stored.id), translationGeneration: generation)
                    prefetchSpeech(resultSpeechIdentity(recordID: stored.id), translationGeneration: nil)
                    updatePaneLanguageLabels()
                    if config.ui.autoCopy {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value.text, forType: .string)
                        flashCopied()
                    }
                }
            } catch {
                currentRecordID = nil
                setStatus("History failed: \(error.localizedDescription)", autoClearAfter: 12)
            }
        case let .failure(error):
            invalidateCurrentRecord()
            setResultText("Error: \(error.localizedDescription)")
        }
        reflowLayout()
        textView.scrollToBeginningOfDocument(nil)
        updateBusyState()
    }

    @objc func runImages() {
        guard pendingImage == nil, let translator else { return }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= config.maxTranslateLength else { setStatus(PopoverFeedback.textTooLong); return }
        let generation = beginRequest()
        setStatus("Generating search query...")
        translator.imageSearchQuery(text) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.finishRequest(generation: generation) }
                guard generation == self.requestGeneration else { return }
                if let url = PopoverIntegrationPolicy.resolvedImageSearchURL(queryResult: result, fallbackText: text) {
                    NSWorkspace.shared.open(url)
                }
                switch result {
                case .success:
                    self.setStatus("Opened Google Images")
                case .failure:
                    self.setStatus("Image query failed; searched source text")
                }
                self.updateBusyState()
            }
        }
    }

    @objc func runLearn() {
        if let text = panelSelectionForSubtranslate() {
            runSubRequest(text: text, mode: .learn)
            return
        }
        guard pendingImage == nil, let translator else { return }
        invalidateCurrentRecord()
        invalidateSpeech(stopPlayback: true)
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { setResultText(PopoverFeedback.emptyInputHint); reflowLayout(); updateBusyState(); return }
        guard text.count <= config.maxTranslateLength else { setResultText(PopoverFeedback.textTooLong); reflowLayout(); updateBusyState(); return }
        let sourceWasAutoDetect = selectedSourceLanguage() == LanguageDetector.autoDetect
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        let generation = beginRequest()
        if let record = historyStore.reusableRecord(
            mode: .learn,
            sourceText: text,
            sourceLanguage: pair.source,
            targetLanguage: pair.target,
            sourceIsAutoDetect: sourceWasAutoDetect
        ) {
            applyReusableRecord(record, mode: .learn, generation: generation)
            finishRequest(generation: generation)
            return
        }
        setResultText(PopoverFeedback.learning)
        reflowLayout()
        translator.learn(text, sourceLang: pair.source, targetLang: pair.target) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.finishRequest(generation: generation) }
                guard generation == self.requestGeneration else { return }
                switch result {
                case let .success(value):
                    self.setResultText(value)
                    let record = TranslationRecord(
                        id: UUID(), timestamp: Date(), mode: .learn, sourceText: text, resultText: value,
                        sourceLanguage: self.effectiveSourceLanguage(for: text), targetLanguage: pair.target,
                        isSaved: false
                    )
                    do {
                        let stored = try self.historyStore.appendIfAbsent(record)
                        if stored.id != record.id {
                            self.applyReusableRecord(stored, mode: .learn, generation: generation)
                        } else {
                            self.currentRecordID = stored.id
                            self.historyWindowController.reloadHistory()
                            self.prefetchSpeech(self.sourceSpeechIdentity(recordID: stored.id), translationGeneration: generation)
                            self.prefetchSpeech(self.resultSpeechIdentity(recordID: stored.id), translationGeneration: nil)
                        }
                    } catch {
                        self.currentRecordID = nil
                        self.setStatus("History failed: \(error.localizedDescription)", autoClearAfter: 12)
                    }
                case let .failure(error):
                    self.invalidateCurrentRecord()
                    self.setResultText("Error: \(error.localizedDescription)")
                }
                self.reflowLayout()
                self.textView.scrollToBeginningOfDocument(nil)
                self.updateBusyState()
            }
        }
    }

    func applyReusableRecord(_ record: TranslationRecord, mode: TranslationMode, generation: Int) {
        guard generation == requestGeneration, pendingImage == nil else { return }
        if selectedSourceLanguage() == LanguageDetector.autoDetect {
            resolvedSourceLanguage = record.sourceLanguage
        }
        setResultText(record.resultText)
        currentRecordID = record.id
        hydrateStoredAudio(for: record)
        let sourceIdentity = sourceSpeechIdentity(recordID: record.id)
        let resultIdentity = resultSpeechIdentity(recordID: record.id)
        if sourceIdentity.map({ speechCache[$0] == nil }) == true {
            prefetchSpeech(sourceIdentity, translationGeneration: generation)
        }
        if resultIdentity.map({ speechCache[$0] == nil }) == true {
            prefetchSpeech(resultIdentity, translationGeneration: nil)
        }
        updatePaneLanguageLabels()
        updateSaveWordButton()
        if mode == .translate, config.ui.autoCopy {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(record.resultText, forType: .string)
            flashCopied()
        }
        reflowLayout()
        textView.scrollToBeginningOfDocument(nil)
        updateBusyState()
    }

    func invalidateCurrentRecord() {
        currentRecordID = nil
        updateSaveWordButton()
    }

    func updateSaveWordButton() {
        let reqInFlight = isRequestInFlight
        let canSave = PopoverIntegrationPolicy.canSave(
            sourceText: inputTextView.string,
            resultText: textView.string,
            isRequestInFlight: reqInFlight
        )
        let isSaved = currentRecordID.flatMap { id in historyStore.records.first { $0.id == id } }
            .map { PopoverIntegrationPolicy.matches($0, sourceText: inputTextView.string, resultText: textView.string) && $0.isSaved } == true

        saveWordButton.isHidden = !canSave
        saveWordButton.isEnabled = canSave && historyStore.loadError == nil && !isRequestInFlight
        if !saveWordButton.isHidden {
            let label = isSaved ? "Remove Saved Word" : "Save Word"
            saveWordButton.image = NSImage(systemSymbolName: isSaved ? "bookmark.fill" : "bookmark", accessibilityDescription: label)
            saveWordButton.toolTip = label
            saveWordButton.setAccessibilityLabel(label)
            saveWordButton.contentTintColor = isSaved ? .controlAccentColor : .secondaryLabelColor
        }
    }

    @objc func toggleSaveWord() {
        let source = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PopoverIntegrationPolicy.canSave(sourceText: source, resultText: result, isRequestInFlight: isRequestInFlight) else { return }
        do {
            if let recordID = currentRecordID,
               let record = historyStore.records.first(where: { $0.id == recordID }),
               PopoverIntegrationPolicy.matches(record, sourceText: source, resultText: result) {
                try historyStore.setSaved(!record.isSaved, recordID: recordID)
            } else {
                let pair = resolvedLanguagePair(for: source)
                let record = TranslationRecord(
                    id: UUID(), timestamp: Date(), sourceText: source, resultText: result,
                    sourceLanguage: pair.source, targetLanguage: pair.target,
                    sourceAudioPath: nil, resultAudioPath: nil, isSaved: true
                )
                try historyStore.append(record)
                currentRecordID = record.id
            }
            historyWindowController.reloadHistory()
            updateSaveWordButton()
        } catch {
            setStatus("Save Word failed: \(error.localizedDescription)", autoClearAfter: 12)
        }
    }

    @objc func copyResult() {
        guard let value = copyValue() else { return }
        guard writePasteboard(value) else {
            setStatus("Copy failed")
            return
        }
        flashCopied()
    }

    func flashCopied() {
        copyFlashWorkItem?.cancel()
        copyButton.title = ""
        copyButton.attributedTitle = NSAttributedString(string: "")
        copyButton.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Copied")
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = .systemGreen
        let work = DispatchWorkItem { [weak self] in
            self?.resetCopyButtonAppearance()
        }
        copyFlashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func copyValue() -> String? {
        let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PopoverFeedback.isCopyableResult(value) else { return nil }
        return value
    }

    func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    func writePasteboard(_ value: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }

    func pasteResultToPreviousApp() {
        guard !isPastingResult else { return }
        guard let value = copyValue(), writePasteboard(value) else {
            closePanel()
            return
        }
        isPastingResult = true
        let app = previousApp
        restoresPreviousAppOnClose = false
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            app?.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.postCommandV()
                self.isPastingResult = false
            }
        }
    }

    @objc func closePopover() {
        restoresPreviousAppOnClose = true
        closePanel()
    }
}