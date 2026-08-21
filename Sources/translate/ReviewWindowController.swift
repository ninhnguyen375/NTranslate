import AppKit
import AVFoundation

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate, @preconcurrency AVAudioPlayerDelegate {
    private let store: TranslationHistoryStore
    var translator: Translator?
    var config: AppConfig?
    private var recordsToReview: [TranslationRecord] = []
    private var currentIndex: Int = 0
    private var isAnswerRevealed: Bool = false
    private var audioPlayer: AVAudioPlayer?
    private var isPracticeMode: Bool = false

    private let progressLabel = NSTextField(labelWithString: "")
    private let completedImageView = NSImageView()
    private let sourceContainer = NSStackView()
    private let termLabel = NSTextField(wrappingLabelWithString: "")
    private let contextLabel = NSTextField(wrappingLabelWithString: "")
    private let readMoreButton = NSButton()
    private let speakSourceButton = NSButton()
    private let speakSlowSourceButton = NSButton()
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let revealButton = NSButton()
    private let againButton = NSButton()
    private let hardButton = NSButton()
    private let easyButton = NSButton()
    private let buttonStack = NSStackView()
    private let cardView = NSVisualEffectView()

    private var currentContext: String?
    private var isContextExpanded: Bool = false
    private var speechState = SpeechPlaybackState()
    private var activeSpeechIdentity: SpeechIdentity?
    private var activeSpeechRate: Float = 1.0

    // Completed state view & buttons
    private let completedStack = NSStackView()
    private let reviewAllButton = NSButton()
    private let reviewAllShuffledButton = NSButton()
    private let cardScrollView = NSScrollView()
    private let cardDocumentView = FlippedDocumentView()

    var onReviewsCompleted: (() -> Void)?

    init(store: TranslationHistoryStore, translator: Translator? = nil, config: AppConfig? = nil) {
        self.store = store
        self.translator = translator
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 480, height: 360)
        window.isReleasedWhenClosed = false
        window.title = "Review SRS (Spaced Repetition)"
        window.setFrameAutosaveName("ReviewSRSWindow")

        super.init(window: window)
        window.delegate = self
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showReview() {
        isPracticeMode = false
        recordsToReview = store.dueReviews()
        currentIndex = 0
        isAnswerRevealed = false
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        loadCurrentCard()
    }

    private func configureUI() {
        guard let window else { return }
        let content = NSView()
        window.contentView = content

        cardView.material = .contentBackground
        cardView.blendingMode = .withinWindow
        cardView.state = .followsWindowActiveState
        cardView.wantsLayer = true
        cardView.layer?.cornerRadius = 16
        cardView.layer?.masksToBounds = true
        cardView.translatesAutoresizingMaskIntoConstraints = false

        cardScrollView.borderType = .noBorder
        cardScrollView.drawsBackground = false
        cardScrollView.hasVerticalScroller = true
        cardScrollView.hasHorizontalScroller = false
        cardScrollView.autohidesScrollers = true
        cardScrollView.scrollerStyle = .overlay
        cardScrollView.translatesAutoresizingMaskIntoConstraints = false

        cardDocumentView.translatesAutoresizingMaskIntoConstraints = false
        cardScrollView.documentView = cardDocumentView

        progressLabel.font = .systemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.alignment = .center

        termLabel.font = .systemFont(ofSize: 22, weight: .bold)
        termLabel.textColor = .labelColor
        termLabel.alignment = .center
        termLabel.lineBreakMode = .byWordWrapping

        contextLabel.font = .systemFont(ofSize: 13, weight: .regular)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.alignment = .center
        contextLabel.lineBreakMode = .byWordWrapping

        readMoreButton.title = "Read more"
        readMoreButton.isBordered = false
        readMoreButton.font = .systemFont(ofSize: 12, weight: .medium)
        readMoreButton.contentTintColor = .systemBlue
        readMoreButton.target = self
        readMoreButton.action = #selector(toggleContextExpansion)
        readMoreButton.isHidden = true

        speakSourceButton.image = makeSymbolImage(name: "speaker.wave.2", description: "Speak source (1.0x)")
        speakSourceButton.isBordered = false
        speakSourceButton.target = self
        speakSourceButton.action = #selector(speakCurrentSource)
        speakSourceButton.toolTip = "Speak source (1.0x)"
        speakSourceButton.setAccessibilityLabel("Speak source (1.0x)")
        speakSourceButton.imageScaling = .scaleProportionallyUpOrDown
        speakSourceButton.contentTintColor = .secondaryLabelColor
        speakSourceButton.translatesAutoresizingMaskIntoConstraints = false
        speakSourceButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        speakSourceButton.heightAnchor.constraint(equalToConstant: 20).isActive = true

        speakSlowSourceButton.image = makeSymbolImage(name: "tortoise", description: "Speak source slowly (0.5x)")
        speakSlowSourceButton.isBordered = false
        speakSlowSourceButton.target = self
        speakSlowSourceButton.action = #selector(speakCurrentSourceSlow)
        speakSlowSourceButton.toolTip = "Speak source slowly (0.5x)"
        speakSlowSourceButton.setAccessibilityLabel("Speak source slowly (0.5x)")
        speakSlowSourceButton.imageScaling = .scaleProportionallyUpOrDown
        speakSlowSourceButton.contentTintColor = .secondaryLabelColor
        speakSlowSourceButton.translatesAutoresizingMaskIntoConstraints = false
        speakSlowSourceButton.widthAnchor.constraint(equalToConstant: 20).isActive = true
        speakSlowSourceButton.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let termStack = NSStackView(views: [termLabel, speakSourceButton, speakSlowSourceButton])
        termStack.orientation = .horizontal
        termStack.spacing = 8
        termStack.alignment = .centerY

        sourceContainer.orientation = .vertical
        sourceContainer.spacing = 6
        sourceContainer.alignment = .centerX
        sourceContainer.addArrangedSubview(termStack)
        sourceContainer.addArrangedSubview(contextLabel)
        sourceContainer.addArrangedSubview(readMoreButton)

        resultLabel.font = .systemFont(ofSize: 14, weight: .regular)
        resultLabel.textColor = .labelColor
        resultLabel.alignment = .left
        resultLabel.lineBreakMode = .byWordWrapping

        styleActionButton(revealButton, title: "Show Answer (Space)", symbol: "eye", action: #selector(revealAnswer), key: " ")

        configureGradeButton(againButton, title: "Again (1)", symbol: "arrow.uturn.backward", grade: .again, color: .systemRed, key: "1")
        configureGradeButton(hardButton, title: "Hard (2)", symbol: "tortoise", grade: .hard, color: .systemOrange, key: "2")
        configureGradeButton(easyButton, title: "Easy (3)", symbol: "hand.thumbsup", grade: .easy, color: .systemGreen, key: "3")

        buttonStack.orientation = .horizontal
        buttonStack.spacing = 12
        buttonStack.distribution = .fillEqually
        buttonStack.addArrangedSubview(againButton)
        buttonStack.addArrangedSubview(hardButton)
        buttonStack.addArrangedSubview(easyButton)

        styleActionButton(reviewAllButton, title: "Review All Saved Cards", symbol: "arrow.clockwise", action: #selector(startReviewAll))
        styleActionButton(reviewAllShuffledButton, title: "Review All (Shuffled)", symbol: "shuffle", action: #selector(startReviewAllShuffled))

        completedStack.orientation = .horizontal
        completedStack.spacing = 12
        completedStack.distribution = .fillEqually
        completedStack.addArrangedSubview(reviewAllButton)
        completedStack.addArrangedSubview(reviewAllShuffledButton)

        completedImageView.image = NSImage(
            systemSymbolName: "checkmark.seal.fill",
            accessibilityDescription: "Review completed"
        )
        completedImageView.contentTintColor = .systemGreen
        completedImageView.imageScaling = .scaleProportionallyUpOrDown
        completedImageView.translatesAutoresizingMaskIntoConstraints = false
        completedImageView.widthAnchor.constraint(equalToConstant: 56).isActive = true
        completedImageView.heightAnchor.constraint(equalToConstant: 56).isActive = true
        completedImageView.isHidden = true

        let innerStack = NSStackView(views: [completedImageView, progressLabel, sourceContainer, resultLabel])
        innerStack.orientation = .vertical
        innerStack.spacing = 18
        innerStack.alignment = .centerX
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        let actionAreaStack = NSStackView(views: [revealButton, buttonStack, completedStack])
        actionAreaStack.orientation = .vertical
        actionAreaStack.spacing = 0
        actionAreaStack.alignment = .centerX
        actionAreaStack.translatesAutoresizingMaskIntoConstraints = false

        revealButton.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        completedStack.translatesAutoresizingMaskIntoConstraints = false

        cardDocumentView.addSubview(innerStack)
        cardView.addSubview(cardScrollView)
        cardView.addSubview(actionAreaStack)
        content.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cardView.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            cardView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),

            cardScrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            cardScrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            cardScrollView.topAnchor.constraint(equalTo: cardView.topAnchor),
            cardScrollView.bottomAnchor.constraint(equalTo: actionAreaStack.topAnchor, constant: -16),

            cardDocumentView.leadingAnchor.constraint(equalTo: cardScrollView.leadingAnchor),
            cardDocumentView.trailingAnchor.constraint(equalTo: cardScrollView.trailingAnchor),
            cardDocumentView.topAnchor.constraint(equalTo: cardScrollView.topAnchor),
            cardDocumentView.widthAnchor.constraint(equalTo: cardScrollView.widthAnchor),
            cardDocumentView.heightAnchor.constraint(greaterThanOrEqualTo: cardScrollView.heightAnchor),

            innerStack.leadingAnchor.constraint(equalTo: cardDocumentView.leadingAnchor, constant: 24),
            innerStack.trailingAnchor.constraint(equalTo: cardDocumentView.trailingAnchor, constant: -24),
            innerStack.centerYAnchor.constraint(equalTo: cardDocumentView.centerYAnchor),
            innerStack.topAnchor.constraint(greaterThanOrEqualTo: cardDocumentView.topAnchor, constant: 24),
            innerStack.bottomAnchor.constraint(lessThanOrEqualTo: cardDocumentView.bottomAnchor, constant: -24),

            actionAreaStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            actionAreaStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            actionAreaStack.bottomAnchor.constraint(equalTo: cardView.bottomAnchor, constant: -24),

            revealButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            revealButton.heightAnchor.constraint(equalToConstant: 38),
            againButton.heightAnchor.constraint(equalToConstant: 38),
            hardButton.heightAnchor.constraint(equalToConstant: 38),
            easyButton.heightAnchor.constraint(equalToConstant: 38),
            reviewAllButton.heightAnchor.constraint(equalToConstant: 38),
            reviewAllShuffledButton.heightAnchor.constraint(equalToConstant: 38),
            buttonStack.widthAnchor.constraint(equalTo: actionAreaStack.widthAnchor, multiplier: 0.85),
            completedStack.widthAnchor.constraint(equalTo: actionAreaStack.widthAnchor, multiplier: 0.85)
        ])
    }

    private func styleActionButton(_ button: NSButton, title: String, symbol: String, action: Selector, key: String? = nil) {
        button.title = "  " + title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.target = self
        button.action = action
        if let key {
            button.keyEquivalent = key
        }
    }

    private func configureGradeButton(_ button: NSButton, title: String, symbol: String, grade: SRSGrade, color: NSColor, key: String) {
        button.title = "  " + title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.target = self
        button.action = #selector(gradeClicked(_:))
        button.tag = grade.rawValue
        button.keyEquivalent = key
    }

    private func updateContextDisplay() {
        guard let context = currentContext, !context.isEmpty else {
            contextLabel.stringValue = ""
            contextLabel.isHidden = true
            readMoreButton.isHidden = true
            return
        }

        contextLabel.isHidden = false
        if context.count > 100 {
            readMoreButton.isHidden = false
            if isContextExpanded {
                contextLabel.stringValue = "Context: \(context)"
                readMoreButton.title = "Show less"
            } else {
                let truncated = String(context.prefix(100)) + "..."
                contextLabel.stringValue = "Context: \(truncated)"
                readMoreButton.title = "Read more"
            }
        } else {
            contextLabel.stringValue = "Context: \(context)"
            readMoreButton.isHidden = true
        }
    }

    @objc private func toggleContextExpansion() {
        isContextExpanded.toggle()
        updateContextDisplay()
    }

    private func loadCurrentCard() {
        if recordsToReview.isEmpty || currentIndex >= recordsToReview.count {
            showCompletedState()
            return
        }

        completedImageView.isHidden = true
        let record = recordsToReview[currentIndex]
        let modePrefix = isPracticeMode ? "Practice" : "Card"
        progressLabel.stringValue = "\(modePrefix) \(currentIndex + 1) of \(recordsToReview.count)  ·  \(record.sourceLanguage) → \(record.targetLanguage)"

        let sourceText = record.sourceText
        if let range = sourceText.range(of: " (context: ") {
            let term = String(sourceText[..<range.lowerBound])
            var context = String(sourceText[range.upperBound...])
            if context.hasSuffix(")") {
                context = String(context.dropLast())
            }
            termLabel.stringValue = term
            currentContext = context
            isContextExpanded = false
            updateContextDisplay()
        } else {
            termLabel.stringValue = sourceText
            currentContext = nil
            isContextExpanded = false
            updateContextDisplay()
        }

        sourceContainer.isHidden = false
        speakSourceButton.isHidden = false
        speakSlowSourceButton.isHidden = false
        resultLabel.stringValue = record.resultText
        resultLabel.isHidden = true
        revealButton.isHidden = false
        buttonStack.isHidden = true
        completedStack.isHidden = true
        isAnswerRevealed = false
        stopAudio()
        updateSpeakButtonUI()

        // Auto play source speech ONLY if cached locally
        if let data = try? store.audioData(for: record.id, kind: .source), SpeechAudioPolicy.isValid(data) {
            playAudio(data, speed: 1.0)
        }
    }

    private func showCompletedState() {
        let savedCount = store.records.filter { $0.isSaved }.count
        completedImageView.isHidden = false
        progressLabel.stringValue = isPracticeMode ? "Practice Completed!" : "Completed!"
        let msg = isPracticeMode
            ? "You have finished reviewing all cards in practice mode."
            : (savedCount > 0
                ? "You have completed all review cards for today."
                : "No saved words found in bookmark.")
        termLabel.stringValue = msg
        currentContext = nil
        isContextExpanded = false
        updateContextDisplay()
        sourceContainer.isHidden = false
        speakSourceButton.isHidden = true
        speakSlowSourceButton.isHidden = true
        resultLabel.stringValue = ""
        resultLabel.isHidden = true
        revealButton.isHidden = true
        buttonStack.isHidden = true
        completedStack.isHidden = savedCount == 0
        stopAudio()
        if !isPracticeMode {
            onReviewsCompleted?()
        }
    }

    @objc private func startReviewAll() {
        startPracticeReview(shuffled: false)
    }

    @objc private func startReviewAllShuffled() {
        startPracticeReview(shuffled: true)
    }

    private func startPracticeReview(shuffled: Bool) {
        var saved = store.records.filter { $0.isSaved }
        guard !saved.isEmpty else { return }
        if shuffled {
            saved.shuffle()
        }
        isPracticeMode = true
        recordsToReview = saved
        currentIndex = 0
        isAnswerRevealed = false
        loadCurrentCard()
    }

    @objc private func revealAnswer() {
        guard !recordsToReview.isEmpty, currentIndex < recordsToReview.count else { return }
        isAnswerRevealed = true
        resultLabel.isHidden = false
        revealButton.isHidden = true
        buttonStack.isHidden = false
        speakSourceButton.isHidden = false

        adjustWindowHeightForContentIfNeeded()
    }

    private func adjustWindowHeightForContentIfNeeded() {
        guard let window else { return }
        let resultText = resultLabel.stringValue
        guard !resultText.isEmpty else { return }

        // Expand height ~1.7x when translation result is long
        let targetHeight: CGFloat = (resultText.count > 150 || resultText.contains("\n\n")) ? 700 : 480
        let currentFrame = window.frame
        if currentFrame.height < targetHeight {
            let heightDiff = targetHeight - currentFrame.height
            let newFrame = NSRect(
                x: currentFrame.origin.x,
                y: max(0, currentFrame.origin.y - heightDiff),
                width: currentFrame.width,
                height: targetHeight
            )
            window.setFrame(newFrame, display: true, animate: true)
        }
    }

    private func currentSourceSpeechIdentity() -> SpeechIdentity? {
        guard !recordsToReview.isEmpty, currentIndex < recordsToReview.count else { return nil }
        let record = recordsToReview[currentIndex]
        let rawText = record.sourceText
        let textToSpeak: String
        if let range = rawText.range(of: " (context: ") {
            textToSpeak = String(rawText[..<range.lowerBound])
        } else {
            textToSpeak = rawText
        }
        let speechCfg = config ?? AppConfig.load()
        let model = SpeechModelResolver.model(for: record.sourceLanguage, config: speechCfg)
        return SpeechIdentity(kind: .source, text: textToSpeak, model: model, recordID: record.id)
    }

    private func makeSymbolImage(name: String, description: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        let img = NSImage(systemSymbolName: name, accessibilityDescription: description)
        return img?.withSymbolConfiguration(config)
    }

    private func updateSpeakButtonUI() {
        guard let identity = currentSourceSpeechIdentity() else {
            speakSourceButton.isEnabled = false
            speakSlowSourceButton.isEnabled = false
            return
        }

        let action = speechState.action(for: identity)
        let isNormalPlaying = activeSpeechIdentity == identity && activeSpeechRate == 1.0
        let isSlowPlaying = activeSpeechIdentity == identity && activeSpeechRate < 1.0

        // Normal speed button (1.0x)
        if isNormalPlaying {
            switch action {
            case .pause:
                speakSourceButton.image = makeSymbolImage(name: "pause.fill", description: "Pause source")
                speakSourceButton.toolTip = "Pause source"
            case .resume:
                speakSourceButton.image = makeSymbolImage(name: "play.fill", description: "Resume source")
                speakSourceButton.toolTip = "Resume source"
            case .loading:
                speakSourceButton.image = makeSymbolImage(name: "hourglass", description: "Loading speech")
                speakSourceButton.toolTip = "Loading speech..."
            case .play:
                speakSourceButton.image = makeSymbolImage(name: "speaker.wave.2", description: "Speak source (1.0x)")
                speakSourceButton.toolTip = "Speak source (1.0x)"
            }
        } else {
            speakSourceButton.image = makeSymbolImage(name: "speaker.wave.2", description: "Speak source (1.0x)")
            speakSourceButton.toolTip = "Speak source (1.0x)"
        }

        // Slow speed button (0.5x)
        if isSlowPlaying {
            switch action {
            case .pause:
                speakSlowSourceButton.image = makeSymbolImage(name: "pause.fill", description: "Pause slow source")
                speakSlowSourceButton.toolTip = "Pause slow source"
            case .resume:
                speakSlowSourceButton.image = makeSymbolImage(name: "play.fill", description: "Resume slow source")
                speakSlowSourceButton.toolTip = "Resume slow source"
            case .loading:
                speakSlowSourceButton.image = makeSymbolImage(name: "hourglass", description: "Loading slow speech")
                speakSlowSourceButton.toolTip = "Loading speech..."
            case .play:
                speakSlowSourceButton.image = makeSymbolImage(name: "tortoise", description: "Speak source slowly (0.5x)")
                speakSlowSourceButton.toolTip = "Speak source slowly (0.5x)"
            }
        } else {
            speakSlowSourceButton.image = makeSymbolImage(name: "tortoise", description: "Speak source slowly (0.5x)")
            speakSlowSourceButton.toolTip = "Speak source slowly (0.5x)"
        }

        speakSourceButton.isEnabled = true
        speakSlowSourceButton.isEnabled = true
    }

    @objc private func speakCurrentSource() {
        handleSpeechPlay(speed: 1.0)
    }

    @objc private func speakCurrentSourceSlow() {
        handleSpeechPlay(speed: 0.5)
    }

    private func handleSpeechPlay(speed: Float) {
        guard let identity = currentSourceSpeechIdentity() else { return }

        // If clicking same speed while active, follow pause/resume/play cycle
        if activeSpeechIdentity == identity && activeSpeechRate == speed {
            switch speechState.action(for: identity) {
            case .pause:
                audioPlayer?.pause()
                _ = speechState.pause(identity)
                updateSpeakButtonUI()
            case .resume:
                guard audioPlayer?.play() == true else {
                    stopAudio()
                    return
                }
                _ = speechState.resume(identity)
                updateSpeakButtonUI()
            case .loading:
                break
            case .play:
                playSpeech(identity: identity, speed: speed)
            }
        } else {
            // Different speed or new item: stop existing and start fresh with requested speed
            stopAudio()
            playSpeech(identity: identity, speed: speed)
        }
    }

    private func playSpeech(identity: SpeechIdentity, speed: Float) {
        activeSpeechIdentity = identity
        activeSpeechRate = speed

        if let data = try? store.audioData(for: identity.recordID ?? UUID(), kind: .source),
           SpeechAudioPolicy.isValid(data) {
            startPlayback(data, identity: identity, speed: speed)
            return
        }

        guard let translator else { return }
        let generation = speechState.beginLoading(identity)
        updateSpeakButtonUI()

        translator.speak(identity.text, model: identity.model, speed: 1.0) { [weak self] result in
            Task { @MainActor in
                guard let self, self.speechState.accepts(generation: generation, identity: identity) else { return }
                guard case let .success(data) = result, SpeechAudioPolicy.isValid(data) else {
                    _ = self.speechState.finishLoading(generation: generation, identity: identity)
                    self.updateSpeakButtonUI()
                    return
                }
                if let recordID = identity.recordID {
                    try? self.store.attachAudio(data, kind: .source, recordID: recordID)
                }
                self.startPlayback(data, identity: identity, speed: speed, loadingGeneration: generation)
            }
        }
    }

    private func startPlayback(_ data: Data, identity: SpeechIdentity, speed: Float, loadingGeneration: Int? = nil) {
        if let loadingGeneration {
            _ = speechState.finishLoading(generation: loadingGeneration, identity: identity)
        }
        audioPlayer?.stop()
        guard let player = try? AVAudioPlayer(data: data) else {
            stopAudio()
            return
        }
        player.delegate = self
        player.enableRate = true
        player.rate = speed
        audioPlayer = player
        activeSpeechIdentity = identity
        activeSpeechRate = speed

        guard player.play() else {
            stopAudio()
            return
        }
        speechState.beginPlaying(identity)
        updateSpeakButtonUI()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer else { return }
        stopAudio()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audioPlayer else { return }
        stopAudio()
    }

    @objc private func gradeClicked(_ sender: NSButton) {
        stopAudio()
        guard let grade = SRSGrade(rawValue: sender.tag), currentIndex < recordsToReview.count else { return }
        let record = recordsToReview[currentIndex]
        do {
            try store.updateSRS(recordID: record.id, grade: grade)
        } catch {
            NSLog("[NTranslate] Failed to update SRS: \(error.localizedDescription)")
        }

        currentIndex += 1
        loadCurrentCard()
    }

    private func playAudio(_ data: Data, speed: Float = 1.0) {
        guard let identity = currentSourceSpeechIdentity() else { return }
        startPlayback(data, identity: identity, speed: speed)
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
        activeSpeechIdentity = nil
        speechState.reset()
        updateSpeakButtonUI()
    }

    func windowWillClose(_ notification: Notification) {
        stopAudio()
    }
}
