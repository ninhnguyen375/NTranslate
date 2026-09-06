// Learn / Proofread / Save Word / Copy-out and closing the popover.
import AppKit
import Carbon.HIToolbox

extension PopoverController {
    @objc func runLearn() {
        runLearn(bypassCache: false)
    }

    func runLearn(bypassCache: Bool = false) {
        guard pendingImage == nil, let translator else { return }
        lastExecutionMode = .learn
        invalidateCurrentRecord()
        invalidateSpeech(stopPlayback: true)
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { setResultText(PopoverFeedback.emptyInputHint); reflowLayout(); updateBusyState(); return }
        guard text.count <= config.maxTranslateLength else { setResultText(PopoverFeedback.textTooLong); reflowLayout(); updateBusyState(); return }
        let sourceWasAutoDetect = selectedSourceLanguage() == LanguageDetector.autoDetect
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        let generation = beginRequest()
        if !bypassCache, let record = historyStore.reusableRecord(
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
        if !bypassCache,
           Translator.isDictionaryTerm(text),
           let packed = VocabPack.shared.lookup(
               text,
               sourceLanguage: pair.source,
               targetLanguage: pair.target,
               sourceIsAutoDetect: sourceWasAutoDetect
           ) {
            // Materialize the pack hit into history before showing it: the reused-record path
            // assigns `currentRecordID`, and Save Word plus stored audio both resolve that ID
            // against the store. A pack entry that never lands there would break both.
            let record = TranslationRecord(
                id: UUID(), timestamp: Date(), mode: .learn, sourceText: text, resultText: packed,
                sourceLanguage: effectiveSourceLanguage(for: text), targetLanguage: pair.target,
                isSaved: false
            )
            do {
                let stored = try historyStore.appendIfAbsent(record)
                historyWindowController.reloadHistory()
                applyReusableRecord(stored, mode: .learn, generation: generation)
                finishRequest(generation: generation)
                return
            } catch {
                // History refused the record, so fall through and let the model answer as usual.
                setStatus("History failed: \(error.localizedDescription)", autoClearAfter: 12)
            }
        }
        setResultText(PopoverFeedback.learning)
        reflowLayout()
        // The source is known now, so its speech fetches alongside the model call.
        prefetchSpeech(sourceSpeechIdentity(recordID: nil), translationGeneration: generation)
        mainRequest = translator.learn(text, sourceLang: pair.source, targetLang: pair.target, onPartial: { [weak self] partial in
            Task { @MainActor in
                self?.appendStreamedResult(partial, generation: generation, scope: .main)
            }
        }) { [weak self] result in
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
                        let stored = try (bypassCache ? self.historyStore.upsertRecord(record) : self.historyStore.appendIfAbsent(record))
                        if stored.id != record.id && !bypassCache {
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
                    let message = PopoverFeedback.userFacingError(error)
                    if message == PopoverFeedback.stopped {
                        if self.lastStreamedMain.isEmpty {
                            self.setResultText(PopoverFeedback.stopped, style: .loading)
                        }
                    } else {
                        self.setResultText(message, style: .error)
                    }
                }
                self.reflowLayout()
                self.textView.scrollToBeginningOfDocument(nil)
                self.updateBusyState()
            }
        }
    }

    /// Grammar-checks the source text in its own language. Replaces the old "pick the same source
    /// and target language" trick, so the language dropdowns stay free for real translation.
    @objc func runProofread() {
        runProofread(bypassCache: false)
    }

    func runProofread(bypassCache: Bool = false) {
        guard pendingImage == nil, let translator else { return }
        lastExecutionMode = .proofread
        invalidateCurrentRecord()
        invalidateSpeech(stopPlayback: true)
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { setResultText(PopoverFeedback.emptyInputHint); reflowLayout(); updateBusyState(); return }
        guard text.count <= config.maxTranslateLength else { setResultText(PopoverFeedback.textTooLong); reflowLayout(); updateBusyState(); return }
        let lang = effectiveSourceLanguage(for: text)
        let generation = beginRequest()
        if !bypassCache, let record = historyStore.reusableRecord(
            mode: .proofread,
            sourceText: text,
            sourceLanguage: lang,
            targetLanguage: lang,
            sourceIsAutoDetect: false
        ) {
            applyReusableRecord(record, mode: .proofread, generation: generation)
            finishRequest(generation: generation)
            return
        }
        setResultText(PopoverFeedback.proofreading)
        reflowLayout()
        // The source is known now, so its speech fetches alongside the model call.
        prefetchSpeech(sourceSpeechIdentity(recordID: nil), translationGeneration: generation)
        mainRequest = translator.proofread(text, lang: lang, onPartial: { [weak self] partial in
            Task { @MainActor in
                self?.appendStreamedResult(partial, generation: generation, scope: .main)
            }
        }) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.finishRequest(generation: generation) }
                guard generation == self.requestGeneration else { return }
                switch result {
                case let .success(value):
                    self.setResultText(value)
                    let record = TranslationRecord(
                        id: UUID(), timestamp: Date(), mode: .proofread, sourceText: text, resultText: value,
                        sourceLanguage: lang, targetLanguage: lang, isSaved: false
                    )
                    do {
                        let stored = try (bypassCache ? self.historyStore.upsertRecord(record) : self.historyStore.appendIfAbsent(record))
                        if stored.id != record.id && !bypassCache {
                            self.applyReusableRecord(stored, mode: .proofread, generation: generation)
                        } else {
                            self.currentRecordID = stored.id
                            self.historyWindowController.reloadHistory()
                        }
                    } catch {
                        self.currentRecordID = nil
                        self.setStatus("History failed: \(error.localizedDescription)", autoClearAfter: 12)
                    }
                case let .failure(error):
                    self.invalidateCurrentRecord()
                    let message = PopoverFeedback.userFacingError(error)
                    if message == PopoverFeedback.stopped {
                        if self.lastStreamedMain.isEmpty {
                            self.setResultText(PopoverFeedback.stopped, style: .loading)
                        }
                    } else {
                        self.setResultText(message, style: .error)
                    }
                }
                self.reflowLayout()
                self.textView.scrollToBeginningOfDocument(nil)
                self.updateBusyState()
            }
        }
    }

    @objc func retryRequest() {
        clearAudioCache(recordID: currentRecordID)
        switch lastExecutionMode {
        case .translate:
            performTranslate(generation: nil, bypassCache: true)
        case .learn:
            runLearn(bypassCache: true)
        case .proofread:
            runProofread(bypassCache: true)
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
        let canSave = lastResultStyle == .normal && PopoverIntegrationPolicy.canSave(
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
            saveWordButton.image = NSImage(systemSymbolName: isSaved ? "bookmark.fill" : "bookmark", accessibilityDescription: label)?
                .withSymbolConfiguration(paneIconSymbolConfiguration)
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
        copyButton.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Copied")?
            .withSymbolConfiguration(paneIconSymbolConfiguration)
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = .systemGreen
        let work = DispatchWorkItem { [weak self] in
            self?.resetCopyButtonAppearance()
        }
        copyFlashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        announceAccessibility("Copied")
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
