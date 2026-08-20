// Text-to-speech: identity resolution, prefetch, cache, playback, and speak-button state.
import AppKit
import AVFoundation

extension PopoverController {
    func updateSpeakButtons() {
        updateSpeechButton(speakSourceButton, identity: sourceSpeechIdentity(), baseLabel: "source")
        updateSpeechButton(speakResultButton, identity: resultSpeechIdentity(), baseLabel: "translation")
        if let section = subSection {
            updateSubSpeakButtons(section)
        }
    }

    /// Same play/loading/pause/resume presentation as the main pane, for the subtranslate pane.
    func updateSubSpeakButtons(_ section: SubtranslateSection) {
        updateSpeechButton(section.speakSourceButton, identity: subSpeechIdentity(kind: .source), baseLabel: "subtranslate source")
        updateSpeechButton(section.speakResultButton, identity: subSpeechIdentity(kind: .result), baseLabel: "subtranslate translation")
    }

    func updateSpeechButton(_ button: NSButton, identity: SpeechIdentity?, baseLabel: String) {
        let action = identity.map { identity in
            prefetchingSpeech.contains(where: { speechMatches($0, identity) })
                ? SpeechButtonAction.loading
                : speechState.action(for: identity)
        } ?? .play
        let presentation: (symbol: String, verb: String, enabled: Bool)
        switch action {
        case .play: presentation = ("speaker.wave.2", "Play", identity != nil)
        case .loading: presentation = ("hourglass", "Loading", false)
        case .pause: presentation = ("pause.fill", "Pause", true)
        case .resume: presentation = ("play.fill", "Resume", true)
        }
        let label = "\(presentation.verb) \(baseLabel)"
        button.title = ""
        button.image = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.contentTintColor = Palette.iconTint
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.isEnabled = presentation.enabled && !isRequestInFlight
    }

    func speechMatches(_ lhs: SpeechIdentity, _ rhs: SpeechIdentity) -> Bool {
        lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.model == rhs.model
    }

    func sourceSpeechIdentity(recordID: UUID? = nil) -> SpeechIdentity? {
        guard pendingImage == nil else { return nil }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SpeechIdentity(kind: .source, text: text, model: sourceSpeechModel(for: text), recordID: recordID ?? currentRecordID)
    }

    func resultSpeechIdentity(recordID: UUID? = nil) -> SpeechIdentity? {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PopoverFeedback.isCopyableResult(text) else { return nil }
        return SpeechIdentity(
            kind: .result,
            text: text,
            model: SpeechModelResolver.model(for: selectedTargetLanguage(), config: config),
            recordID: recordID ?? currentRecordID
        )
    }

    func effectiveSourceLanguage(for text: String) -> String {
        PopoverIntegrationPolicy.effectiveSourceLanguage(
            selected: selectedSourceLanguage(),
            resolved: resolvedSourceLanguage,
            text: text
        )
    }

    func sourceSpeechModel(for text: String) -> String {
        SpeechModelResolver.model(for: effectiveSourceLanguage(for: text), config: config)
    }

    func hydrateStoredAudio(for record: TranslationRecord) {
        let identities: [(TranslationAudioKind, SpeechIdentity?)] = [
            (.source, sourceSpeechIdentity(recordID: record.id)),
            (.result, resultSpeechIdentity(recordID: record.id))
        ]
        for (kind, identity) in identities {
            guard let identity,
                  let data = try? historyStore.audioData(for: record.id, kind: kind),
                  SpeechAudioPolicy.isValid(data)
            else { continue }
            speechCache[identity] = data
        }
    }

    func prefetchSpeech(_ identity: SpeechIdentity?, translationGeneration: Int?) {
        guard config.autoPrefetchSpeech, let identity, let translator else { return }
        if let data = speechCache[identity] {
            acceptPrefetchedSpeech(data, identity: identity, translationGeneration: translationGeneration)
            return
        }
        guard !prefetchingSpeech.contains(identity) else { return }
        let generation = prefetchGeneration
        prefetchingSpeech.insert(identity)
        updateSpeakButtons()
        translator.speak(identity.text, model: identity.model) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.prefetchingSpeech.remove(identity)
                self.updateSpeakButtons()
                guard generation == self.prefetchGeneration, case let .success(data) = result,
                      SpeechAudioPolicy.isValid(data)
                else { return }
                self.speechCache[identity] = data
                self.acceptPrefetchedSpeech(data, identity: identity, translationGeneration: translationGeneration)
            }
        }
    }

    func acceptPrefetchedSpeech(_ data: Data, identity: SpeechIdentity, translationGeneration: Int?) {
        if identity.kind == .source, let translationGeneration {
            if let recordedIdentity = PopoverIntegrationPolicy.recordedSpeechIdentity(
                identity, translationGeneration: translationGeneration,
                currentGeneration: requestGeneration, recordID: currentRecordID
            ) {
                speechCache[recordedIdentity] = data
                attachAudio(data, identity: recordedIdentity)
            } else {
                pendingSourceSpeech[translationGeneration] = PendingSourceSpeech(identity: identity, data: data)
            }
        } else {
            attachAudio(data, identity: identity)
        }
    }

    func playSpeech(_ identity: SpeechIdentity?) {
        guard let identity,
              !prefetchingSpeech.contains(where: { speechMatches($0, identity) })
        else { return }
        switch speechState.action(for: identity) {
        case .pause:
            audioPlayer?.pause()
            _ = speechState.pause(identity)
            updateSpeakButtons()
        case .resume:
            guard audioPlayer?.play() == true else { resetSpeechPlayback(); return }
            _ = speechState.resume(identity)
            updateSpeakButtons()
        case .loading: break
        case .play:
            stopCurrentSpeech()
            if let data = speechCache[identity] { startPlayback(data, identity: identity) }
            else { loadAndPlaySpeech(identity) }
        }
    }

    func loadAndPlaySpeech(_ identity: SpeechIdentity) {
        guard let translator else { return }
        let generation = speechState.beginLoading(identity)
        updateSpeakButtons()
        translator.speak(identity.text, model: identity.model) { [weak self] result in
            Task { @MainActor in
                guard let self, self.speechState.accepts(generation: generation, identity: identity) else { return }
                switch result {
                case let .success(data):
                    guard SpeechAudioPolicy.isValid(data),
                          self.startPlayback(data, identity: identity, loadingGeneration: generation)
                    else {
                        _ = self.speechState.finishLoading(generation: generation, identity: identity)
                        self.setStatus("Speak failed: Invalid audio response")
                        self.updateSpeakButtons()
                        return
                    }
                    self.speechCache[identity] = data
                    self.attachAudio(data, identity: identity)
                case let .failure(error):
                    _ = self.speechState.finishLoading(generation: generation, identity: identity)
                    self.setStatus("Speak failed: \(error.localizedDescription)")
                    self.updateSpeakButtons()
                }
            }
        }
    }

    @discardableResult
    func startPlayback(_ data: Data, identity: SpeechIdentity, loadingGeneration: Int? = nil) -> Bool {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.enableRate = true
            player.rate = speechRate
            player.prepareToPlay()
            guard player.play() else { throw NSError(domain: "Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio could not be played"]) }
            audioPlayer = player
            if let loadingGeneration {
                guard speechState.markPlaying(generation: loadingGeneration, identity: identity) else { player.stop(); return false }
            } else {
                speechState.beginPlaying(identity)
            }
            updateSpeakButtons()
            return true
        } catch {
            resetSpeechPlayback()
            setStatus("Speak failed: \(error.localizedDescription)")
            return false
        }
    }

    func stopCurrentSpeech() {
        audioPlayer?.stop()
        audioPlayer = nil
        speechState.reset()
    }

    func resetSpeechPlayback() {
        audioPlayer = nil
        speechState.reset()
        updateSpeakButtons()
    }

    func invalidateSpeech(stopPlayback: Bool) {
        prefetchGeneration += 1
        prefetchingSpeech.removeAll()
        pendingSourceSpeech.removeAll()
        speechState.invalidateRequests()
        if stopPlayback { stopCurrentSpeech() }
        updateSpeakButtons()
    }

    func attachPendingSourceSpeech(for generation: Int, recordID: UUID) {
        guard let pending = pendingSourceSpeech.removeValue(forKey: generation) else { return }
        let identity = SpeechIdentity(kind: .source, text: pending.identity.text, model: pending.identity.model, recordID: recordID)
        speechCache[identity] = pending.data
        attachAudio(pending.data, identity: identity)
    }

    func attachAudio(_ data: Data, identity: SpeechIdentity) {
        guard PopoverIntegrationPolicy.canAttachAudio(identity: identity, currentRecordID: currentRecordID),
              let recordID = identity.recordID,
              historyStore.records.contains(where: { $0.id == recordID })
        else { return }
        do {
            try historyStore.attachAudio(data, kind: identity.kind == .source ? .source : .result, recordID: recordID)
            historyWindowController.reloadHistory()
        } catch {
            setStatus("History audio failed: \(error.localizedDescription)", autoClearAfter: 12)
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer else { return }
        resetSpeechPlayback()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audioPlayer else { return }
        resetSpeechPlayback()
        if let error { setStatus("Speak failed: \(error.localizedDescription)") }
    }

    @objc func speakInput() { playSpeech(sourceSpeechIdentity()) }
    @objc func speakResult() { playSpeech(resultSpeechIdentity()) }

    @objc func speechRateChanged(_ sender: NSMenuItem) {
        guard let rate = sender.representedObject as? Float else { return }
        speechRate = rate
        audioPlayer?.rate = rate
    }
}