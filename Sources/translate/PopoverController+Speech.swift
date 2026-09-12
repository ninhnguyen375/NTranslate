// Text-to-speech: identity resolution, prefetch, cache, playback, and speak-button state.
import AppKit
import AVFoundation

extension PopoverController {
    func updateSpeakButtons() {
        let source = sourceSpeechIdentity()
        updateSpeechButton(speakSourceButton, identity: source, baseLabel: "source", speed: 1.0, idleSymbol: "speaker.wave.2")
        updateSpeechButton(speakSourceSlowButton, identity: source, baseLabel: "source slowly", speed: config.speechSlowRate, idleSymbol: "tortoise")
        updateSpeechButton(learnCardView.speakButton, identity: source, baseLabel: "source", speed: 1.0, idleSymbol: "speaker.wave.2")
        updateSpeechButton(speakResultButton, identity: resultSpeechIdentity(), baseLabel: "translation", speed: 1.0, idleSymbol: "speaker.wave.2")
        updateSpeechButton(speakResultSlowButton, identity: resultSpeechIdentity(), baseLabel: "translation slowly", speed: config.speechSlowRate, idleSymbol: "tortoise")
        if let section = subSection {
            updateSubSpeakButtons(section)
        }
        if !selectionFloatingBar.isHidden {
            updateSpeechButton(floatingSpeakButton, identity: floatingSpeechIdentity(), baseLabel: "phrase", speed: 1.0, idleSymbol: "speaker.wave.2")
        }
    }

    /// Same play/loading/pause/resume presentation as the main pane, for the subtranslate pane.
    func updateSubSpeakButtons(_ section: SubtranslateSection) {
        updateSpeechButton(section.speakSourceButton, identity: subSpeechIdentity(kind: .source), baseLabel: "subtranslate source", speed: 1.0, idleSymbol: "speaker.wave.2")
        updateSpeechButton(section.speakSourceSlowButton, identity: subSpeechIdentity(kind: .source), baseLabel: "subtranslate source slowly", speed: config.speechSlowRate, idleSymbol: "tortoise")
        updateSpeechButton(section.speakResultButton, identity: subSpeechIdentity(kind: .result), baseLabel: "subtranslate translation", speed: 1.0, idleSymbol: "speaker.wave.2")
        updateSpeechButton(section.speakResultSlowButton, identity: subSpeechIdentity(kind: .result), baseLabel: "subtranslate translation slowly", speed: config.speechSlowRate, idleSymbol: "tortoise")
        updateSpeechButton(section.learnCardView.speakButton, identity: subSpeechIdentity(kind: .source), baseLabel: "subtranslate source", speed: 1.0, idleSymbol: "speaker.wave.2")
    }

    func updateSpeechButton(
        _ button: NSButton,
        identity: SpeechIdentity?,
        baseLabel: String,
        speed: Float = 1.0,
        idleSymbol: String = "speaker.wave.2"
    ) {
        let isActiveSpeed = abs(activeSpeechRate - speed) < 0.01
        let action = identity.map { identity -> SpeechButtonAction in
            if prefetchingSpeech.contains(where: { speechMatches($0, identity) }) {
                return isActiveSpeed ? .loading : .play
            }
            let state = speechState.action(for: identity)
            return isActiveSpeed ? state : .play
        } ?? .play
        let presentation: (symbol: String, verb: String, enabled: Bool)
        switch action {
        case .play: presentation = (idleSymbol, speed < 1 ? "Speak slowly" : "Play", identity != nil)
        case .loading: presentation = ("hourglass", "Loading", false)
        case .pause: presentation = ("pause.fill", "Pause", true)
        case .resume: presentation = ("play.fill", "Resume", true)
        }
        let label = "\(presentation.verb) \(baseLabel)"
        button.title = ""
        button.image = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(paneIconSymbolConfiguration)
        button.imagePosition = .imageOnly
        button.contentTintColor = Palette.iconTint
        button.toolTip = label
        button.setAccessibilityLabel(label)
        // Speech runs on its own request; an in-flight translation must not block cached playback.
        button.isEnabled = presentation.enabled
    }

    /// Decodes the clip off the main thread to learn where the audible part starts and ends.
    func cacheSpeechTrim(_ data: Data, identity: SpeechIdentity) {
        guard speechTrim[identity] == nil else { return }
        Task.detached(priority: .utility) {
            guard let bounds = SpeechTrim.bounds(of: data) else { return }
            await MainActor.run { [weak self] in self?.speechTrim[identity] = bounds }
        }
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
        // A half-streamed translation is not worth speaking, and the speak button no longer
        // hides behind a global in-flight gate.
        guard PopoverFeedback.isCopyableResult(text, isStreaming: isRequestInFlight) else { return nil }
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

    func hydrateStoredAudio(for record: TranslationRecord) async {
        let jobs: [(SpeechIdentity, URL)] = [
            (.source, sourceSpeechIdentity(recordID: record.id)),
            (.result, resultSpeechIdentity(recordID: record.id))
        ].compactMap { kind, identity in
            guard let identity,
                  let url = try? historyStore.audioFileURL(for: record.id, kind: kind)
            else { return nil }
            return (identity, url)
        }
        guard !jobs.isEmpty else { return }
        let loaded = await Task.detached(priority: .utility) {
            jobs.compactMap { identity, url -> (SpeechIdentity, Data)? in
                guard let data = try? Data(contentsOf: url), SpeechAudioPolicy.isValid(data) else { return nil }
                return (identity, data)
            }
        }.value
        for (identity, data) in loaded {
            speechCache[identity] = data
            cacheSpeechTrim(data, identity: identity)
        }
    }

    /// Speech fetched before its history record existed is cached under a nil record ID. Adopting
    /// it once the ID is known keeps the later prefetch from paying for the same audio twice.
    func adoptCachedSpeech(for identity: SpeechIdentity) {
        guard identity.recordID != nil, speechCache[identity] == nil else { return }
        let orphan = SpeechIdentity(kind: identity.kind, text: identity.text, model: identity.model)
        guard let data = speechCache[orphan] else { return }
        speechCache[identity] = data
        speechTrim[identity] = speechTrim[orphan]
    }

    func prefetchSpeech(_ identity: SpeechIdentity?, translationGeneration: Int?) {
        guard config.autoPrefetchSpeech, let identity,
              identity.text.count <= config.speechPrefetchMaxLength,
              let translator
        else { return }
        adoptCachedSpeech(for: identity)
        if let data = speechCache[identity] {
            acceptPrefetchedSpeech(data, identity: identity, translationGeneration: translationGeneration)
            return
        }
        guard !prefetchingSpeech.contains(identity) else { return }
        let generation = prefetchGeneration
        prefetchingSpeech.insert(identity)
        updateSpeakButtons()
        translator.speak(identity.text, model: identity.model, speed: 1.0) { [weak self] result in
            // Still on the network queue: decode here so playback never waits on the analysis.
            let bounds = (try? result.get()).flatMap(SpeechTrim.bounds)
            Task { @MainActor in
                guard let self else { return }
                self.prefetchingSpeech.remove(identity)
                self.updateSpeakButtons()
                guard generation == self.prefetchGeneration, case let .success(data) = result,
                      SpeechAudioPolicy.isValid(data)
                else { return }
                self.speechCache[identity] = data
                self.speechTrim[identity] = bounds
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

    func playSpeech(_ identity: SpeechIdentity?, speed: Float = 1.0) {
        guard let identity,
              !prefetchingSpeech.contains(where: { speechMatches($0, identity) })
        else { return }
        let sameActive = abs(activeSpeechRate - speed) < 0.01
        if sameActive {
            switch speechState.action(for: identity) {
            case .pause:
                audioPlayer?.pause()
                _ = speechState.pause(identity)
                updateSpeakButtons()
                return
            case .resume:
                guard let player = audioPlayer, player.play() else { resetSpeechPlayback(); return }
                _ = speechState.resume(identity)
                updateSpeakButtons()
                return
            case .loading:
                return
            case .play:
                break
            }
        }
        stopCurrentSpeech()
        activeSpeechRate = speed
        if let data = speechCache[identity] { startPlayback(data, identity: identity, speed: speed) }
        else { loadAndPlaySpeech(identity, speed: speed) }
    }

    func loadAndPlaySpeech(_ identity: SpeechIdentity, speed: Float = 1.0) {
        guard let translator else { return }
        activeSpeechRate = speed
        let generation = speechState.beginLoading(identity)
        updateSpeakButtons()
        translator.speak(identity.text, model: identity.model, speed: 1.0) { [weak self] result in
            let bounds = (try? result.get()).flatMap(SpeechTrim.bounds)
            Task { @MainActor in
                guard let self, self.speechState.accepts(generation: generation, identity: identity) else { return }
                self.speechTrim[identity] = bounds
                switch result {
                case let .success(data):
                    guard SpeechAudioPolicy.isValid(data),
                          self.startPlayback(data, identity: identity, speed: speed, loadingGeneration: generation)
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
    func startPlayback(_ data: Data, identity: SpeechIdentity, speed: Float = 1.0, loadingGeneration: Int? = nil) -> Bool {
        do {
            audioPlayer?.stop()
            audioPlayer = nil
            let player = try AVAudioPlayer(data: SpeechGain.boosted(data, volume: config.speechVolume))
            player.delegate = self
            player.enableRate = true
            player.rate = speed
            player.prepareToPlay()
            let bounds = speechTrim[identity]
            if let bounds, bounds.lead >= SpeechTrim.minimumGain {
                player.currentTime = bounds.lead
            }
            guard player.play() else { throw NSError(domain: "Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio could not be played"]) }
            audioPlayer = player
            activeSpeechRate = speed
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

    /// Drops every cached clip for one record, in memory and on disk, so the next play goes back
    /// to whichever speech provider is configured now. Both retry buttons and a speech settings
    /// change route through here — `invalidateSpeech` alone only bumps generations and would
    /// leave the old audio in `speechCache` and in the history store.
    func clearAudioCache(recordID: UUID?) {
        invalidateSpeech(stopPlayback: true)
        // Keep only clips belonging to *other* records. Orphans (nil record ID, cached before the
        // record existed) go too, or `adoptCachedSpeech` would pull the stale clip right back in.
        speechCache = speechCache.filter { $0.key.recordID != nil && $0.key.recordID != recordID }
        speechTrim = speechTrim.filter { $0.key.recordID != nil && $0.key.recordID != recordID }
        guard let recordID else { return }
        do {
            try historyStore.removeAudio(recordID: recordID)
            _historyWindowController?.reloadHistory()
        } catch {
            setStatus("Could not clear stored audio: \(error.localizedDescription)", autoClearAfter: 12)
        }
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
            _historyWindowController?.reloadHistory()
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

    @objc func speakInput() { playSpeech(sourceSpeechIdentity(), speed: 1.0) }
    @objc func speakInputSlow() { playSpeech(sourceSpeechIdentity(), speed: config.speechSlowRate) }
    @objc func speakResult() { playSpeech(resultSpeechIdentity(), speed: 1.0) }
    @objc func speakResultSlow() { playSpeech(resultSpeechIdentity(), speed: config.speechSlowRate) }
}