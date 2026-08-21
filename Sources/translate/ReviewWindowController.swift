import AppKit
import AVFoundation

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate, AVAudioPlayerDelegate {
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
    private let sourceLabel = NSTextField(wrappingLabelWithString: "")
    private let speakSourceButton = NSButton()
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let revealButton = NSButton()
    private let againButton = NSButton()
    private let hardButton = NSButton()
    private let easyButton = NSButton()
    private let buttonStack = NSStackView()
    private let cardView = NSVisualEffectView()

    // Completed state view & buttons
    private let completedStack = NSStackView()
    private let reviewAllButton = NSButton()
    private let reviewAllShuffledButton = NSButton()

    var onReviewsCompleted: (() -> Void)?

    init(store: TranslationHistoryStore, translator: Translator? = nil, config: AppConfig? = nil) {
        self.store = store
        self.translator = translator
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
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

        progressLabel.font = .systemFont(ofSize: 12, weight: .medium)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.alignment = .center

        sourceLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        sourceLabel.alignment = .center
        sourceLabel.maximumNumberOfLines = 6
        sourceLabel.lineBreakMode = .byWordWrapping

        speakSourceButton.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Speak source")
        speakSourceButton.isBordered = false
        speakSourceButton.target = self
        speakSourceButton.action = #selector(speakCurrentSource)
        speakSourceButton.toolTip = "Speak source"
        speakSourceButton.setAccessibilityLabel("Speak source")
        speakSourceButton.imageScaling = .scaleProportionallyUpOrDown
        speakSourceButton.contentTintColor = .secondaryLabelColor
        speakSourceButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        speakSourceButton.heightAnchor.constraint(equalToConstant: 24).isActive = true

        sourceContainer.orientation = .horizontal
        sourceContainer.spacing = 8
        sourceContainer.alignment = .centerY
        sourceContainer.addArrangedSubview(sourceLabel)
        sourceContainer.addArrangedSubview(speakSourceButton)

        resultLabel.font = .systemFont(ofSize: 16, weight: .regular)
        resultLabel.textColor = .labelColor
        resultLabel.alignment = .center
        resultLabel.maximumNumberOfLines = 8
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

        let innerStack = NSStackView(views: [completedImageView, progressLabel, sourceContainer, resultLabel, revealButton, buttonStack, completedStack])
        innerStack.orientation = .vertical
        innerStack.spacing = 18
        innerStack.alignment = .centerX
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        cardView.addSubview(innerStack)
        content.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cardView.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            cardView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),

            innerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            innerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            innerStack.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),

            revealButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            revealButton.heightAnchor.constraint(equalToConstant: 38),
            againButton.heightAnchor.constraint(equalToConstant: 38),
            hardButton.heightAnchor.constraint(equalToConstant: 38),
            easyButton.heightAnchor.constraint(equalToConstant: 38),
            reviewAllButton.heightAnchor.constraint(equalToConstant: 38),
            reviewAllShuffledButton.heightAnchor.constraint(equalToConstant: 38),
            buttonStack.widthAnchor.constraint(equalTo: innerStack.widthAnchor, multiplier: 0.85),
            completedStack.widthAnchor.constraint(equalTo: innerStack.widthAnchor, multiplier: 0.85)
        ])
    }

    private func styleActionButton(_ button: NSButton, title: String, symbol: String, action: Selector, key: String? = nil) {
        button.title = title
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
        button.title = title
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

    private func loadCurrentCard() {
        if recordsToReview.isEmpty || currentIndex >= recordsToReview.count {
            showCompletedState()
            return
        }

        completedImageView.isHidden = true
        let record = recordsToReview[currentIndex]
        let modePrefix = isPracticeMode ? "Practice" : "Card"
        progressLabel.stringValue = "\(modePrefix) \(currentIndex + 1) of \(recordsToReview.count)  ·  \(record.sourceLanguage) → \(record.targetLanguage)"
        sourceLabel.stringValue = record.sourceText
        sourceContainer.isHidden = false
        speakSourceButton.isHidden = false
        resultLabel.stringValue = record.resultText
        resultLabel.isHidden = true
        revealButton.isHidden = false
        buttonStack.isHidden = true
        completedStack.isHidden = true
        isAnswerRevealed = false

        // Auto play source speech ONLY if cached locally
        if let data = try? store.audioData(for: record.id, kind: .source), SpeechAudioPolicy.isValid(data) {
            playAudio(data)
        }
    }

    private func showCompletedState() {
        let savedCount = store.records.filter { $0.isSaved }.count
        completedImageView.isHidden = false
        progressLabel.stringValue = isPracticeMode ? "Practice Completed!" : "Completed!"
        sourceLabel.stringValue = isPracticeMode
            ? "You have finished reviewing all cards in practice mode."
            : (savedCount > 0
                ? "You have completed all review cards for today."
                : "No saved words found in bookmark.")
        sourceContainer.isHidden = false
        speakSourceButton.isHidden = true
        resultLabel.stringValue = ""
        resultLabel.isHidden = true
        revealButton.isHidden = true
        buttonStack.isHidden = true
        completedStack.isHidden = savedCount == 0
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
    }

    @objc private func speakCurrentSource() {
        guard !recordsToReview.isEmpty, currentIndex < recordsToReview.count else { return }
        let record = recordsToReview[currentIndex]
        playSpeech(for: record, kind: .source)
    }

    private func speakCurrentResult() {
        guard !recordsToReview.isEmpty, currentIndex < recordsToReview.count else { return }
        let record = recordsToReview[currentIndex]
        playSpeech(for: record, kind: .result)
    }

    private func playSpeech(for record: TranslationRecord, kind: TranslationAudioKind) {
        if let data = try? store.audioData(for: record.id, kind: kind), SpeechAudioPolicy.isValid(data) {
            playAudio(data)
            return
        }

        // Fetch via Translator if missing
        guard let translator else { return }
        let textToSpeak = kind == .source ? record.sourceText : record.resultText
        let lang = kind == .source ? record.sourceLanguage : record.targetLanguage
        let speechCfg = config ?? AppConfig.load()
        let model = SpeechModelResolver.model(for: lang, config: speechCfg)
        let recordID = record.id

        speakSourceButton.isEnabled = false
        translator.speak(textToSpeak, model: model, speed: 1.0) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.speakSourceButton.isEnabled = true
                guard case let .success(data) = result, SpeechAudioPolicy.isValid(data) else { return }
                try? self.store.attachAudio(data, kind: kind, recordID: recordID)
                if self.currentIndex < self.recordsToReview.count, self.recordsToReview[self.currentIndex].id == recordID {
                    self.playAudio(data)
                }
            }
        }
    }

    @objc private func gradeClicked(_ sender: NSButton) {
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

    private func playAudio(_ data: Data) {
        audioPlayer?.stop()
        audioPlayer = try? AVAudioPlayer(data: data)
        audioPlayer?.delegate = self
        audioPlayer?.play()
    }

    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopAudio()
    }
}
