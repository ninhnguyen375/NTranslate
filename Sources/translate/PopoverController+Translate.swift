// Translate / Learn / Images requests, history records, and copy-out of the result.
import AppKit
import Carbon.HIToolbox

extension PopoverController {
    func translateAtCursor(forceSimulatedCopy: Bool = false) {
        beginAtCursor(loading: PopoverFeedback.translating, forceSimulatedCopy: forceSimulatedCopy) { [weak self] resolved in
            guard let self else { return }
            guard self.prepareInputFromSelection(resolved) else { return }
            self.lastExecutionMode = .translate
            let generation = self.beginRequest()
            self.setResultText(PopoverFeedback.translating)
            self.reflowLayout()
            self.presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
            self.performTranslate(generation: generation)
        }
    }

    /// Shows the panel right away with `loading`, then resolves the selection off the main thread
    /// and hands the result back on main. The read waits for modifier release and polls the
    /// pasteboard for up to ~1s, which used to delay the panel by that whole amount.
    ///
    /// The panel is shown without activating the app: the simulated Command+C has to land in
    /// whichever app owns the selection, so activation only happens once the read is done.
    func beginAtCursor(
        loading: String,
        forceSimulatedCopy: Bool = false,
        handler: @escaping @MainActor (TranslatableInputResolution) -> Void
    ) {
        // Without Accessibility both paths are dead (no AXSelectedText, no synthetic Command+C),
        // so prompt and stop instead of silently translating stale clipboard content.
        guard AXIsProcessTrusted() else {
            requestAccessibilityPermissionIfNeeded(forcePrompt: true)
            showEmptySelectionPanel(message: PopoverFeedback.accessibilityRequired)
            return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        let pointer = NSEvent.mouseLocation
        if !panel.isVisible {
            showMousePoint = pointer
            invalidateTranslationRequest()
            invalidateSpeech(stopPlayback: true)
            setPendingImage(nil)
            inputTextView.string = ""
            clearStatus()
            setResultText(loading)
            reflowLayout()
            updateBusyState()
            presentPanel(activatesApp: false, restoresPreviousAppOnCloseValue: false)
        } else if !isPinned {
            movePanelToPointer(pointer)
            panel.makeKeyAndOrderFront(nil)
        }

        let hotkeyStart = DispatchTime.now()
        let simulateCopy = PopoverIntegrationPolicy.shouldSimulateCopy(
            force: forceSimulatedCopy,
            configured: config.ui.simulateCopy
        )
        DispatchQueue.global(qos: .userInitiated).async {
            var resolved: TranslatableInputResolution?
            var failure: String?
            do {
                resolved = try SelectionReader.resolveTranslatableInputWithDiagnostics(
                    simulateCopy: simulateCopy,
                    forceCopy: forceSimulatedCopy
                )
            } catch {
                failure = "Error: \(error)"
            }
            let result = resolved
            let message = failure
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                NSLog("[NTranslate][timing] hotkey to handler=\(SelectionReader.ms(since: hotkeyStart))")
                if let message {
                    self.showEmptySelectionPanel(message: message)
                } else if let result {
                    handler(result)
                } else {
                    self.showEmptySelectionPanel()
                }
            }
        }
    }

    /// Loads an already-read selection into the main input pane. Returns false when it handled the
    /// failure path (over-length text) and the caller should stop.
    func prepareInputFromSelection(_ resolved: TranslatableInputResolution) -> Bool {
        if !isPinned { showMousePoint = NSEvent.mouseLocation }
        if resolved.accessibilityError != nil {
            setStatus(PopoverFeedback.accessibilityFallbackNote(source: resolved.source))
        } else {
            clearStatus()
        }
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        inputContextLabel.stringValue = ""
        inputContextLabel.toolTip = nil
        inputContextLabel.isHidden = true
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
        lastExecutionMode = .translate
        invalidateSpeech(stopPlayback: true)
        performTranslate(generation: nil)
    }

    func performTranslate(generation existingGeneration: Int?, bypassCache: Bool = false) {
        invalidateCurrentRecord()
        removeQASection()
        qaInputField.stringValue = ""
        qaInputField.isHidden = true
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
            // The image's language is unknown until the model reads it, so a fixed target can end up
            // equal to the source ("translate Vietnamese into Vietnamese") and the model just echoes
            // the transcription back. Send the auto-detect target instead and let the prompt switch
            // away when the two collide.
            let targetLang = LanguageDetector.normalizeTarget(
                selectedTargetLanguage(),
                targetLanguages: config.targetLanguages,
                fallback: config.resolvedNativeLang
            )
            mainRequest = translator.translateImage(image, targetLang: targetLang) { [weak self] result in
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
        if !bypassCache, let record = historyStore.reusableRecord(
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
        mainRequest = translator.translate(
            text,
            sourceLang: pair.source,
            targetLang: pair.target,
            context: context,
            onPartial: { [weak self] partial in
                Task { @MainActor in
                    self?.appendStreamedResult(partial, generation: generation, scope: .main)
                }
            }
        ) { [weak self] result in
            Task { @MainActor in self?.finishTextTranslation(result, generation: generation, source: text, pair: pair, bypassCache: bypassCache) }
        }
    }

    func finishImageTranslation(_ result: Result<Translator.ImageTranslation, Error>, generation: Int) {
        defer { finishRequest(generation: generation) }
        guard generation == requestGeneration, pendingImage != nil else { return }
        invalidateCurrentRecord()
        switch result {
        case let .success(value):
            // Once the model returns a transcription, drop image mode: the source pane now holds
            // real text, so speak / subtranslate / Q&A / save all work as they do for text input.
            if !value.sourceText.isEmpty {
                inputTextView.string = value.sourceText
                setPendingImage(nil)
                applyImageLanguages(value)
            }
            setResultText(value.translation)
            if !value.sourceText.isEmpty {
                prefetchSpeech(sourceSpeechIdentity(), translationGeneration: nil)
            }
            prefetchSpeech(resultSpeechIdentity(), translationGeneration: nil)
        case let .failure(error):
            if PopoverFeedback.userFacingError(error) == PopoverFeedback.stopped { return }
            setResultText(PopoverFeedback.userFacingError(error), style: .error)
        }
        reflowLayout()
        textView.scrollToBeginningOfDocument(nil)
        updateBusyState()
    }

    /// Adopts the languages the model reported for an image, so the pane labels, speech models and
    /// any follow-up translation match what was actually transcribed and produced.
    func applyImageLanguages(_ value: Translator.ImageTranslation) {
        let source = value.sourceLanguage.isEmpty
            ? LanguageDetector.detectedLanguage(value.sourceText)
            : value.sourceLanguage
        selectLanguage(source, kind: .source)
        resolvedSourceLanguage = source
        if !value.targetLanguage.isEmpty, value.targetLanguage != source {
            selectLanguage(value.targetLanguage, kind: .target)
            UserDefaults.standard.set(value.targetLanguage, forKey: Self.lastTargetLangKey)
        }
        updatePaneLanguageLabels()
    }

    func finishTextTranslation(_ result: Result<TranslationResult, Error>, generation: Int, source: String, pair: (source: String, target: String), bypassCache: Bool = false) {
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
                let stored = try (bypassCache ? historyStore.upsertRecord(record) : historyStore.appendIfAbsent(record))
                if stored.id != record.id && !bypassCache {
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
                    maybeHintSubtranslate()
                }
            } catch {
                currentRecordID = nil
                setStatus("History failed: \(error.localizedDescription)", autoClearAfter: 12)
            }
        case let .failure(error):
            invalidateCurrentRecord()
            let message = PopoverFeedback.userFacingError(error)
            if message == PopoverFeedback.stopped {
                if lastStreamedMain.isEmpty {
                    setResultText(PopoverFeedback.stopped, style: .loading)
                } else {
                    setResultText(lastStreamedMain, style: .loading)
                }
            } else if let raw = Optional(lastStreamedMain), !raw.isEmpty,
                      (raw.hasPrefix("{") || raw.hasPrefix("```")),
                      error is Translator.ResponseError {
                setResultText(raw, style: .error)
            } else {
                setResultText(message, style: .error)
            }
        }
        reflowLayout()
        textView.scrollToBeginningOfDocument(nil)
        updateBusyState()
    }

    @objc func runImages() {
        runImageSearch(text: inputTextView.string)
    }

    @objc func runSubImages() {
        runImageSearch(text: subSection?.sourceText ?? "")
    }

    func runImageSearch(text: String) {
        guard pendingImage == nil, let translator else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard trimmed.count <= config.maxTranslateLength else { setStatus(PopoverFeedback.textTooLong); return }
        setStatus("Generating search query...")
        translator.imageSearchQuery(trimmed) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if let url = PopoverIntegrationPolicy.resolvedImageSearchURL(queryResult: result, fallbackText: trimmed) {
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
}
