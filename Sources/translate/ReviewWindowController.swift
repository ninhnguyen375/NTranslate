import AppKit
import AVFoundation

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

private enum ReviewLayout {
    static let iconSize: CGFloat = 20
    static let contextTruncateLimit = 100
    static let compactHeight: CGFloat = 480
    static let expandedHeight: CGFloat = 700
}

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate, @preconcurrency AVAudioPlayerDelegate {
    private var store: TranslationHistoryStore
    var translator: Translator?
    var config: AppConfig?
    private var recordsToReview: [TranslationRecord] = []
    private var currentIndex: Int = 0
    private var isAnswerRevealed: Bool = false
    private var audioPlayer: AVAudioPlayer?
    private var isPracticeMode: Bool = false

    private enum ActiveQuestion {
        /// Cloze, Recall and Listen all ask for one typed word; only the prompt differs.
        case typed(LearnCard.ClozeQuestion, kind: ReviewPlanner.QuestionKind)
        case contrast(ConfusableDrillItem, choices: [String])
        case none
    }

    /// nil means Auto: the card picks its own question from how well it is known.
    private var requestedKind: ReviewPlanner.QuestionKind?
    private var activeQuestion: ActiveQuestion = .none
    private var activeKind: ReviewPlanner.QuestionKind = .flip

    // Session bookkeeping: everything below resets when a session starts.
    private var questionShownAt: Date?
    private var sessionStartedAt: Date?
    private var answeredCount = 0
    private var correctCount = 0
    private var missedTerms: [String] = []
    private var relearnCounts: [UUID: Int] = [:]
    private var pendingAutoGrade: SRSGrade?
    private var undoSnapshot: (record: TranslationRecord, index: Int)?

    /// True while the card is asking something instead of just showing its term.
    private var hasActiveQuestion: Bool {
        if case .none = activeQuestion { return false }
        return true
    }
    private var isReadingMode = false
    private var isHomeScreen = true
    private var weaveRequest: RequestHandle?

    private let progressLabel = NSTextField(labelWithString: "")
    private let completedImageView = NSImageView()
    private let sourceContainer = NSStackView()
    private let termLabel = NSTextField(wrappingLabelWithString: "")
    private let contextLabel = NSTextField(wrappingLabelWithString: "")
    private let readMoreButton = NSButton()
    private let speakSourceButton = NSButton()
    private let speakSlowSourceButton = NSButton()
    private let openTranslateButton = NSButton()
    private let speakShortcutLabel = NSTextField(labelWithString: "(4)")
    private let speakSlowShortcutLabel = NSTextField(labelWithString: "(5)")
    private let openTranslateShortcutLabel = NSTextField(labelWithString: "(6)")
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private let readingChatView = ReadingChatView()
    private let readingModeControl = NSSegmentedControl()
    private var readingWordsInPlay: [String] = []
    private var didRetryWeave = false
    private let answerField = NSTextField()
    private let feedbackLabel = NSTextField(labelWithString: "")
    private let choiceStack = NSStackView()
    private let firstChoiceButton = NSButton()
    private let secondChoiceButton = NSButton()
    private let revealButton = NSButton()
    private let backButton = NSButton()
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
    private let startButton = NSButton()
    private let statsLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(wrappingLabelWithString: "")
    private let modePopup = NSPopUpButton()
    private let homeButton = NSButton()
    private let undoButton = NSButton()
    private let hideButton = NSButton()
    private let topBarStack = NSStackView()
    private let readingButton = NSButton()
    private let passagesButton = NSButton()
    /// Backs the saved-passages menu: the item's tag is an index into this list.
    private var savedPassages: [WeavePassage] = []
    private let startOptionsStack = NSStackView()
    private let cardScrollView = NSScrollView()
    private let cardDocumentView = FlippedDocumentView()
    private var keyEventMonitor: Any?
    private var didShowReview = false

    var onReviewsCompleted: (() -> Void)?
    var onOpenTranslate: ((TranslationRecord) -> Void)?

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
        window.title = "Spaced Repetition"
        window.setFrameAutosaveName("ReviewSRSWindow")

        super.init(window: window)
        window.delegate = self
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func updateDependencies(store: TranslationHistoryStore, translator: Translator?, config: AppConfig) {
        self.store = store
        self.translator = translator
        self.config = config
    }

    func showReview() {
        installKeyEventMonitorIfNeeded()
        showWindow(nil)
        if !didShowReview {
            didShowReview = true
            // Autosave restores a saved frame before first show; only center the constructed default.
            if let window, window.frame.origin == .zero {
                window.center()
            }
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        showHome()
    }

    /// Starts today's session: SM-2 order, capped by the daily limit, with same-family cards
    /// pulled apart so one does not prime the next.
    private func startSession() {
        isPracticeMode = false
        recordsToReview = Self.sessionRecords(
            due: store.dueReviews(),
            dailyReviewLimit: config?.learning.dailyReviewLimit ?? 12
        )
        beginSession()
    }

    private func beginSession() {
        currentIndex = 0
        isAnswerRevealed = false
        isHomeScreen = false
        isReadingMode = false
        sessionStartedAt = Date()
        answeredCount = 0
        correctCount = 0
        missedTerms.removeAll()
        relearnCounts.removeAll()
        undoSnapshot = nil
        loadCurrentCard()
    }

    /// Higher score = review sooner. Combines how overdue a card is (relative to its own
    /// interval, so long-interval cards are not unfairly favoured) with how fragile the
    /// memory looks: low ease, many lapses, few successful repetitions.
    static func reviewPriorityScore(
        _ record: TranslationRecord,
        currentDate: Date,
        calendar: Calendar
    ) -> Double {
        var daysOverdue = 0
        if let due = record.dueDate {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: due),
                to: calendar.startOfDay(for: currentDate)
            ).day ?? 0
            daysOverdue = max(0, days)
        }
        let overdueRatio = Double(daysOverdue) / Double(max(1, record.interval))
        let easePenalty = max(0, 2.5 - record.ease)
        let lapsePenalty = Double(record.lapses) * 0.3
        let fragility = 1.0 / Double(max(1, record.repetitions + 1))
        return overdueRatio * 2.0 + easePenalty + lapsePenalty + fragility
    }

    /// Reviews take SM-2 priority up to `dailyReviewLimit`; remaining slots are filled
    /// with new cards so the session never exceeds `limit`.
    static func sessionRecords(
        due: [TranslationRecord],
        dailyReviewLimit: Int,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [TranslationRecord] {
        let limit = max(1, dailyReviewLimit)
        func isNew(_ record: TranslationRecord) -> Bool {
            record.dueDate == nil || record.interval == 0
        }
        let news = due.filter(isNew)
        // Score once per card: Calendar date math is costly, and a comparator would repeat it.
        let rankedReviews = due.filter { !isNew($0) }
            .map { (record: $0, score: reviewPriorityScore($0, currentDate: currentDate, calendar: calendar)) }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                let lhsDue = lhs.record.dueDate ?? .distantPast
                let rhsDue = rhs.record.dueDate ?? .distantPast
                if lhsDue != rhsDue { return lhsDue < rhsDue }
                return (lhs.record.lastReviewedAt ?? .distantPast) < (rhs.record.lastReviewedAt ?? .distantPast)
            }
            .map(\.record)
        let reviews = Array(rankedReviews.prefix(limit))
        let remaining = max(0, limit - reviews.count)
        let session = reviews + Array(news.prefix(remaining))
        return ReviewPlanner.interleave(session) { $0.sourceText }
    }

    private func installKeyEventMonitorIfNeeded() {
        guard keyEventMonitor == nil else { return }
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, window.isVisible, NSApp.keyWindow === window else {
                return event
            }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyEventMonitor() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        let chars = event.charactersIgnoringModifiers ?? ""
        if event.keyCode == 53 { // Escape
            if isReadingMode {
                leaveReading()
                return nil
            }
            // Escape steps back out of a session first, and only closes from the home screen.
            if !isHomeScreen {
                goHome()
                return nil
            }
            stopAudio()
            window?.performClose(nil)
            return nil
        }
        if event.modifierFlags.contains(.command), chars.lowercased() == "z" {
            undoLastGrade()
            return nil
        }
        // While the cloze field has focus every key belongs to it, not to the shortcuts. Once the
        // field is hidden its editor can still hold first responder, and a hidden field has no
        // claim on the keyboard.
        if !answerField.isHidden, let editor = window?.firstResponder as? NSText, editor.delegate === answerField {
            return event
        }
        if isReadingMode {
            if !readingModeControl.isHidden, let index = ["1", "2", "3"].firstIndex(of: chars) {
                readingModeControl.selectedSegment = index
                readingModeChanged()
                return nil
            }
            return event
        }
        // Home owns the keyboard while it is showing: no stale card may be answered or graded.
        if isHomeScreen {
            if chars == "\r" { startSession() }
            return event
        }
        if !isAnswerRevealed, case .contrast = activeQuestion {
            if chars == "1" {
                chooseContrast(index: 0)
                return nil
            }
            if chars == "2" {
                chooseContrast(index: 1)
                return nil
            }
        }
        if chars == " " {
            handleSpaceKey()
            return nil
        }
        if isAnswerRevealed {
            if chars == "1" {
                applyGrade(.again)
                return nil
            } else if chars == "2" {
                applyGrade(.hard)
                return nil
            } else if chars == "3" {
                applyGrade(.easy)
                return nil
            }
        }
        if chars == "4" {
            speakCurrentSource()
            return nil
        } else if chars == "5" {
            speakCurrentSourceSlow()
            return nil
        } else if chars == "6" {
            openTranslatePopup()
            return nil
        }
        return event
    }

    private func handleSpaceKey() {
        if isHomeScreen {
            startSession()
            return
        }
        if !isAnswerRevealed {
            revealAnswer()
            return
        }
        // A question that graded itself only needs "next"; Space is that key.
        if let auto = pendingAutoGrade {
            applyGrade(auto)
            return
        }
        let clipView = cardScrollView.contentView
        let visibleRect = clipView.documentVisibleRect
        let docHeight = cardDocumentView.bounds.height
        if visibleRect.maxY < docHeight - 5 {
            let scrollDistance = clipView.bounds.height * 0.75
            let newY = min(docHeight - visibleRect.height, visibleRect.origin.y + scrollDistance)
            clipView.scroll(to: NSPoint(x: 0, y: max(0, newY)))
            cardScrollView.reflectScrolledClipView(clipView)
        } else {
            clipView.scroll(to: NSPoint(x: 0, y: 0))
            cardScrollView.reflectScrolledClipView(clipView)
        }
    }

    private func applyGrade(_ grade: SRSGrade) {
        stopAudio()
        guard currentIndex < recordsToReview.count else { return }
        let record = recordsToReview[currentIndex]
        undoSnapshot = (store.records.first(where: { $0.id == record.id }) ?? record, currentIndex)
        do {
            try store.updateSRS(recordID: record.id, grade: grade)
        } catch {
            NSLog("[NTranslate] Failed to update SRS: \(error.localizedDescription)")
        }

        answeredCount += 1
        if grade != .again { correctCount += 1 }
        if grade == .again { requeueForRelearning(record) }

        pendingAutoGrade = nil
        currentIndex += 1
        loadCurrentCard()
    }

    /// A missed card comes back later in the same session. Twice at most: a third pass in one
    /// sitting is drilling, not learning, and it crowds out the rest of the queue.
    private func requeueForRelearning(_ record: TranslationRecord) {
        let seen = relearnCounts[record.id] ?? 0
        guard seen < ReviewPlanner.maxRelearnPerCard else { return }
        relearnCounts[record.id] = seen + 1
        let target = ReviewPlanner.requeueIndex(currentIndex: currentIndex, count: recordsToReview.count)
        recordsToReview.insert(record, at: target)
        let term = displayTerm(of: record)
        if !missedTerms.contains(term) { missedTerms.append(term) }
    }

    @objc private func undoLastGrade() {
        guard let snapshot = undoSnapshot else { return }
        do {
            try store.restoreSRS(from: snapshot.record)
        } catch {
            NSLog("[NTranslate] Failed to undo grade: \(error.localizedDescription)")
            return
        }
        // The relearning copy that grade may have queued is no longer wanted.
        if let queued = recordsToReview.dropFirst(snapshot.index + 1).firstIndex(where: { $0.id == snapshot.record.id }) {
            recordsToReview.remove(at: queued)
            relearnCounts[snapshot.record.id] = max(0, (relearnCounts[snapshot.record.id] ?? 1) - 1)
        }
        answeredCount = max(0, answeredCount - 1)
        undoSnapshot = nil
        currentIndex = snapshot.index
        isHomeScreen = false
        isReadingMode = false
        loadCurrentCard()
    }

    /// Leeches and cards the learner no longer wants leave the deck the same way they entered it.
    @objc private func hideCurrentCard() {
        guard currentIndex < recordsToReview.count else { return }
        let record = recordsToReview[currentIndex]
        do {
            try store.setSaved(false, recordID: record.id)
        } catch {
            NSLog("[NTranslate] Failed to hide card: \(error.localizedDescription)")
            return
        }
        recordsToReview.removeAll { $0.id == record.id }
        undoSnapshot = nil
        loadCurrentCard()
    }

    @objc private func goHome() {
        stopAudio()
        weaveRequest?.cancel()
        weaveRequest = nil
        isReadingMode = false
        showHome()
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
        termLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        termLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

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

        makeIconButton(
            speakSourceButton,
            symbol: "speaker.wave.2",
            label: "Speak source (4 / 1.0x)",
            action: #selector(speakCurrentSource)
        )
        makeIconButton(
            speakSlowSourceButton,
            symbol: "tortoise",
            label: "Speak source slowly (5)",
            action: #selector(speakCurrentSourceSlow)
        )
        makeIconButton(
            openTranslateButton,
            symbol: "character.bubble",
            label: "Open this card in Translate (6)",
            action: #selector(openTranslatePopup)
        )

        speakShortcutLabel.font = .systemFont(ofSize: 10, weight: .bold)
        speakShortcutLabel.textColor = .tertiaryLabelColor
        speakShortcutLabel.alignment = .center

        speakSlowShortcutLabel.font = .systemFont(ofSize: 10, weight: .bold)
        speakSlowShortcutLabel.textColor = .tertiaryLabelColor
        speakSlowShortcutLabel.alignment = .center

        openTranslateShortcutLabel.font = .systemFont(ofSize: 10, weight: .bold)
        openTranslateShortcutLabel.textColor = .tertiaryLabelColor
        openTranslateShortcutLabel.alignment = .center

        let speakGroup = NSStackView(views: [speakSourceButton, speakShortcutLabel])
        speakGroup.orientation = .horizontal
        speakGroup.spacing = 1
        speakGroup.alignment = .centerY

        let speakSlowGroup = NSStackView(views: [speakSlowSourceButton, speakSlowShortcutLabel])
        speakSlowGroup.orientation = .horizontal
        speakSlowGroup.spacing = 1
        speakSlowGroup.alignment = .centerY

        let openTranslateGroup = NSStackView(views: [openTranslateButton, openTranslateShortcutLabel])
        openTranslateGroup.orientation = .horizontal
        openTranslateGroup.spacing = 1
        openTranslateGroup.alignment = .centerY

        let audioButtonsStack = NSStackView(views: [speakGroup, speakSlowGroup, openTranslateGroup])
        audioButtonsStack.orientation = .horizontal
        audioButtonsStack.spacing = 6
        audioButtonsStack.alignment = .centerY

        // The buttons sit to the right of the term, so without a matching gap on the left the
        // whole group centres and the term itself reads as left-aligned. The spacer tracks the
        // button stack's width, including when the buttons hide and it collapses to zero.
        let termLeadingSpacer = NSView()
        termLeadingSpacer.translatesAutoresizingMaskIntoConstraints = false

        let termStack = NSStackView(views: [termLeadingSpacer, termLabel, audioButtonsStack])
        termStack.orientation = .horizontal
        termStack.spacing = 8
        termStack.alignment = .centerY
        // Both views share termStack now, so the constraint has an ancestor to live on.
        termLeadingSpacer.widthAnchor.constraint(equalTo: audioButtonsStack.widthAnchor).isActive = true

        sourceContainer.orientation = .vertical
        sourceContainer.spacing = 6
        sourceContainer.alignment = .centerX
        sourceContainer.addArrangedSubview(termStack)
        sourceContainer.addArrangedSubview(contextLabel)
        sourceContainer.addArrangedSubview(readMoreButton)
        sourceContainer.addArrangedSubview(answerField)
        sourceContainer.addArrangedSubview(choiceStack)
        sourceContainer.addArrangedSubview(feedbackLabel)

        resultLabel.font = .systemFont(ofSize: 14, weight: .regular)
        resultLabel.textColor = .labelColor
        resultLabel.alignment = .left
        resultLabel.lineBreakMode = .byWordWrapping
        // Selecting the text hands it to the field editor, which drops every attribute unless the
        // field says attributes are its own. Without this the reading underlines vanish on click.
        resultLabel.allowsEditingTextAttributes = true

        answerField.placeholderString = "Type the missing word, then press Return"
        answerField.font = .systemFont(ofSize: 15, weight: .regular)
        answerField.alignment = .center
        answerField.target = self
        answerField.action = #selector(submitClozeAnswer)
        answerField.isHidden = true
        answerField.translatesAutoresizingMaskIntoConstraints = false
        answerField.widthAnchor.constraint(equalToConstant: 280).isActive = true

        feedbackLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        feedbackLabel.alignment = .center
        feedbackLabel.isHidden = true

        styleActionButton(firstChoiceButton, title: "", symbol: "1.circle", action: #selector(chooseFirst), key: "")
        styleActionButton(secondChoiceButton, title: "", symbol: "2.circle", action: #selector(chooseSecond), key: "")
        choiceStack.orientation = .horizontal
        choiceStack.spacing = 12
        choiceStack.distribution = .fillEqually
        choiceStack.addArrangedSubview(firstChoiceButton)
        choiceStack.addArrangedSubview(secondChoiceButton)
        choiceStack.isHidden = true
        choiceStack.translatesAutoresizingMaskIntoConstraints = false
        choiceStack.widthAnchor.constraint(equalToConstant: 380).isActive = true

        styleActionButton(revealButton, title: "Show Answer (Space)", symbol: "eye", action: #selector(revealAnswer), key: " ")
        styleActionButton(backButton, title: "Back", symbol: "chevron.backward", action: #selector(leaveReading))
        backButton.isHidden = true

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

        modePopup.addItem(withTitle: "Auto")
        for kind in ReviewPlanner.QuestionKind.allCases {
            modePopup.addItem(withTitle: kind.label)
        }
        modePopup.selectItem(at: 0)
        modePopup.target = self
        modePopup.action = #selector(modeChanged)
        modePopup.toolTip = "How each card asks its question. Auto follows how well you know the card."

        styleActionButton(readingButton, title: "Reading Passage", symbol: "text.book.closed", action: #selector(showReadingPassage))
        styleActionButton(passagesButton, title: "Saved Passages", symbol: "list.bullet.rectangle", action: #selector(showPassageList(_:)))

        startOptionsStack.orientation = .horizontal
        startOptionsStack.spacing = 12
        startOptionsStack.alignment = .centerY
        startOptionsStack.addArrangedSubview(modePopup)
        startOptionsStack.addArrangedSubview(readingButton)
        startOptionsStack.addArrangedSubview(passagesButton)
        startOptionsStack.translatesAutoresizingMaskIntoConstraints = false

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

        makeIconButton(homeButton, symbol: "house", label: "Back to home (Esc)", action: #selector(goHome))
        makeIconButton(undoButton, symbol: "arrow.uturn.backward.circle", label: "Undo last grade (Cmd+Z)", action: #selector(undoLastGrade))
        makeIconButton(hideButton, symbol: "eye.slash", label: "Remove this card from the deck", action: #selector(hideCurrentCard))

        topBarStack.orientation = .horizontal
        topBarStack.spacing = 10
        topBarStack.alignment = .centerY
        topBarStack.addArrangedSubview(homeButton)
        topBarStack.addArrangedSubview(undoButton)
        topBarStack.addArrangedSubview(hideButton)
        topBarStack.translatesAutoresizingMaskIntoConstraints = false
        topBarStack.isHidden = true

        statsLabel.font = .systemFont(ofSize: 12, weight: .regular)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.alignment = .center
        statsLabel.isHidden = true

        hintLabel.font = .systemFont(ofSize: 11, weight: .regular)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.isHidden = true

        styleActionButton(startButton, title: "Start Review", symbol: "play.fill", action: #selector(startReviewSession))

        readingModeControl.segmentStyle = .rounded
        readingModeControl.segmentCount = 3
        readingModeControl.setLabel("English (1)", forSegment: 0)
        readingModeControl.setLabel("Vietnamese (2)", forSegment: 1)
        readingModeControl.setLabel("Both (3)", forSegment: 2)
        readingModeControl.selectedSegment = ReadingChatView.Mode.both.rawValue
        readingModeControl.target = self
        readingModeControl.action = #selector(readingModeChanged)
        readingModeControl.isHidden = true
        readingChatView.isHidden = true
        readingChatView.onSpeak = { [weak self] line, isSlow in self?.speakReadingLine(line, slow: isSlow) }
        readingChatView.onWord = { [weak self] word in self?.openTranslateForWord(word) }

        let innerStack = NSStackView(views: [completedImageView, progressLabel, statsLabel, sourceContainer, hintLabel, readingModeControl, readingChatView, resultLabel])
        innerStack.orientation = .vertical
        innerStack.spacing = 18
        innerStack.alignment = .centerX
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        let actionAreaStack = NSStackView(views: [revealButton, buttonStack, backButton, startButton, startOptionsStack, completedStack])
        actionAreaStack.orientation = .vertical
        actionAreaStack.spacing = 10
        actionAreaStack.alignment = .centerX
        actionAreaStack.translatesAutoresizingMaskIntoConstraints = false

        revealButton.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        completedStack.translatesAutoresizingMaskIntoConstraints = false

        cardDocumentView.addSubview(innerStack)
        cardView.addSubview(topBarStack)
        cardView.addSubview(cardScrollView)
        cardView.addSubview(actionAreaStack)
        content.addSubview(cardView)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            cardView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            cardView.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            cardView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),

            topBarStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 16),
            topBarStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 12),

            cardScrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            cardScrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            cardScrollView.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 36),
            cardScrollView.bottomAnchor.constraint(equalTo: actionAreaStack.topAnchor, constant: -16),

            cardDocumentView.leadingAnchor.constraint(equalTo: cardScrollView.leadingAnchor),
            cardDocumentView.trailingAnchor.constraint(equalTo: cardScrollView.trailingAnchor),
            cardDocumentView.topAnchor.constraint(equalTo: cardScrollView.topAnchor),
            cardDocumentView.widthAnchor.constraint(equalTo: cardScrollView.widthAnchor),
            cardDocumentView.heightAnchor.constraint(greaterThanOrEqualTo: cardScrollView.heightAnchor),

            readingChatView.widthAnchor.constraint(equalTo: innerStack.widthAnchor),

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
            readingButton.heightAnchor.constraint(equalToConstant: 30),
            backButton.heightAnchor.constraint(equalToConstant: 38),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            startButton.heightAnchor.constraint(equalToConstant: 38),
            startButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            firstChoiceButton.heightAnchor.constraint(equalToConstant: 34),
            secondChoiceButton.heightAnchor.constraint(equalToConstant: 34),
            buttonStack.widthAnchor.constraint(equalTo: actionAreaStack.widthAnchor, multiplier: 0.85),
            completedStack.widthAnchor.constraint(equalTo: actionAreaStack.widthAnchor, multiplier: 0.85)
        ])
    }

    private func makeIconButton(_ button: NSButton, symbol: String, label: String, action: Selector) {
        button.image = makeSymbolImage(name: symbol, description: label)
        button.isBordered = false
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.imageScaling = .scaleProportionallyUpOrDown
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: ReviewLayout.iconSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: ReviewLayout.iconSize).isActive = true
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
        if context.count > ReviewLayout.contextTruncateLimit {
            readMoreButton.isHidden = false
            if isContextExpanded {
                contextLabel.stringValue = "Context: \(context)"
                readMoreButton.title = "Show less"
            } else {
                let truncated = String(context.prefix(ReviewLayout.contextTruncateLimit)) + "..."
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
            showSummary()
            return
        }

        isHomeScreen = false
        completedImageView.isHidden = true
        statsLabel.isHidden = true
        topBarStack.isHidden = false
        undoButton.isEnabled = undoSnapshot != nil
        let record = recordsToReview[currentIndex]
        let modePrefix = isPracticeMode ? "Practice" : "Card"
        let relearning = (relearnCounts[record.id] ?? 0) > 0 ? "  ·  relearning" : ""
        progressLabel.stringValue = "\(modePrefix) \(currentIndex + 1) of \(recordsToReview.count)\(relearning)  ·  \(record.sourceLanguage) → \(record.targetLanguage)"

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
        speakShortcutLabel.isHidden = false
        speakSlowShortcutLabel.isHidden = false
        openTranslateButton.isHidden = false
        openTranslateShortcutLabel.isHidden = false
        resultLabel.stringValue = record.resultText
        resultLabel.isHidden = true
        hideReadingChat()
        revealButton.isHidden = false
        backButton.isHidden = true
        buttonStack.isHidden = true
        completedStack.isHidden = true
        startOptionsStack.isHidden = true
        startButton.isHidden = true
        isAnswerRevealed = false
        stopAudio()
        updateSpeakButtonUI()

        pendingAutoGrade = nil
        let asked = question(for: record)
        activeQuestion = asked.0
        activeKind = asked.kind
        applyQuestionLayer()
        showHint(asked.note ?? leechNote(for: record))

        hideButton.isEnabled = !isPracticeMode

        // Auto play source speech ONLY if cached locally. In a question mode the source word is
        // the answer, so speaking it would hand it over before the learner tries.
        if !hasActiveQuestion,
           let data = try? store.audioData(for: record.id, kind: .source),
           SpeechAudioPolicy.isValid(data) {
            playAudio(data, speed: 1.0)
        }
    }

    /// What a given card is able to ask. A card only offers a question it has the text for, so the
    /// mode picker never promises something the card cannot deliver.
    private func availableKinds(for record: TranslationRecord, card: LearnCard) -> Set<ReviewPlanner.QuestionKind> {
        guard record.mode == .learn else { return [.flip] }
        var kinds: Set<ReviewPlanner.QuestionKind> = [.flip]
        if card.cloze != nil { kinds.insert(.cloze) }
        if ConfusableDrillItem.build(from: [card]).first != nil { kinds.insert(.contrast) }
        if card.recall != nil { kinds.insert(.recall) }
        // Listening needs a word to pronounce and a voice to pronounce it with.
        if !card.headword.isEmpty, translator != nil || (try? store.audioData(for: record.id, kind: .source)) != nil {
            kinds.insert(.listen)
        }
        return kinds
    }

    /// The question this card asks this time round, and the note explaining any downgrade.
    private func question(for record: TranslationRecord) -> (ActiveQuestion, kind: ReviewPlanner.QuestionKind, note: String?) {
        let card = LearnCard.parse(record.resultText)
        let resolved = ReviewPlanner.resolve(
            requested: requestedKind,
            interval: record.interval,
            repetitions: record.repetitions,
            available: availableKinds(for: record, card: card)
        )
        switch resolved.kind {
        case .flip:
            return (.none, .flip, resolved.note)
        case .cloze:
            guard let cloze = card.cloze else { return (.none, .flip, resolved.note) }
            return (.typed(cloze, kind: .cloze), .cloze, resolved.note)
        case .recall:
            guard let recall = card.recall else { return (.none, .flip, resolved.note) }
            return (.typed(recall, kind: .recall), .recall, resolved.note)
        case .listen:
            guard !card.headword.isEmpty else { return (.none, .flip, resolved.note) }
            let question = LearnCard.ClozeQuestion(prompt: "Listen, then type what you hear.", answer: card.headword)
            return (.typed(question, kind: .listen), .listen, resolved.note)
        case .contrast:
            guard let drill = ConfusableDrillItem.build(from: [card]).first else { return (.none, .flip, resolved.note) }
            return (.contrast(drill, choices: [drill.correct, drill.distractor].shuffled()), .contrast, resolved.note)
        }
    }

    private func applyQuestionLayer() {
        answerField.stringValue = ""
        feedbackLabel.isHidden = true
        questionShownAt = Date()
        switch activeQuestion {
        case .none:
            answerField.isHidden = true
            choiceStack.isHidden = true
            termLabel.font = .systemFont(ofSize: 22, weight: .bold)
        case let .typed(question, kind):
            termLabel.stringValue = question.prompt
            termLabel.font = .systemFont(ofSize: 17, weight: .regular)
            answerField.isHidden = false
            answerField.placeholderString = kind == .cloze
                ? "Type the missing word, then press Return"
                : "Type the word, then press Return"
            choiceStack.isHidden = true
            hideSourceGiveaways()
            if kind == .listen {
                // The whole question is the sound, so the speak buttons stay and play at once.
                speakSourceButton.isHidden = false
                speakSlowSourceButton.isHidden = false
                speakShortcutLabel.isHidden = false
                speakSlowShortcutLabel.isHidden = false
                speakCurrentSource()
            }
            window?.makeFirstResponder(answerField)
        case let .contrast(drill, choices):
            termLabel.stringValue = drill.sentence
            termLabel.font = .systemFont(ofSize: 17, weight: .regular)
            answerField.isHidden = true
            choiceStack.isHidden = false
            firstChoiceButton.title = "  " + (choices.first ?? "")
            secondChoiceButton.title = "  " + (choices.last ?? "")
            hideSourceGiveaways()
        }
    }

    /// The term, its audio, and the Translate shortcut all reveal the answer, so they wait until
    /// the card is flipped.
    private func hideSourceGiveaways() {
        speakSourceButton.isHidden = true
        speakSlowSourceButton.isHidden = true
        speakShortcutLabel.isHidden = true
        speakSlowShortcutLabel.isHidden = true
        openTranslateButton.isHidden = true
        openTranslateShortcutLabel.isHidden = true
        contextLabel.isHidden = true
        readMoreButton.isHidden = true
    }

    /// The home screen: what the deck looks like today and every way into it. Reachable at any
    /// time from the house button, so a session can be left without closing the window.
    private func showHome() {
        isHomeScreen = true
        isReadingMode = false
        clearActiveQuestion()
        let stats = store.computeStats()
        let due = stats.dueCount
        completedImageView.isHidden = true
        progressLabel.stringValue = "Spaced Repetition"
        termLabel.stringValue = stats.totalSaved == 0
            ? "No saved words found in bookmark."
            : (due > 0 ? "\(due) card\(due == 1 ? "" : "s") due today." : "Nothing due today.")
        statsLabel.stringValue = "\(stats.totalSaved) saved  ·  \(stats.totalMastered) mastered  ·  \(stats.dayStreak)-day streak"
        statsLabel.isHidden = stats.totalSaved == 0
        startButton.title = due > 0 ? "  Start Review (\(due))" : "  Review Anyway"
        startButton.isHidden = stats.totalSaved == 0
        presentNonCardChrome()
        completedStack.isHidden = stats.totalSaved == 0
        startOptionsStack.isHidden = false
        readingButton.isEnabled = !readingWords().isEmpty
        readingButton.title = missedTerms.isEmpty ? "  Reading Passage" : "  Reading Passage (\(missedTerms.count) missed)"
    }

    /// End of a session: how it went, and what tomorrow looks like.
    private func showSummary() {
        isHomeScreen = true
        clearActiveQuestion()
        completedImageView.isHidden = false
        progressLabel.stringValue = isPracticeMode ? "Practice Completed!" : "Completed!"
        termLabel.stringValue = isPracticeMode
            ? "You have finished reviewing all cards in practice mode."
            : "You have completed all review cards for today."
        statsLabel.stringValue = sessionSummaryLine()
        statsLabel.isHidden = false
        startButton.isHidden = true
        presentNonCardChrome()
        completedStack.isHidden = store.records.allSatisfy { !$0.isSaved }
        startOptionsStack.isHidden = false
        readingButton.isEnabled = !readingWords().isEmpty
        readingButton.title = missedTerms.isEmpty ? "  Reading Passage" : "  Review \(missedTerms.count) missed in a passage"
        if !isPracticeMode {
            onReviewsCompleted?()
        }
    }

    /// Leaving the card behind has to take its question with it, or a later keystroke would
    /// answer or grade a card that is no longer on screen.
    private func clearActiveQuestion() {
        activeQuestion = .none
        activeKind = .flip
        isAnswerRevealed = false
        pendingAutoGrade = nil
        questionShownAt = nil
    }

    private func sessionSummaryLine() -> String {
        guard answeredCount > 0 else { return "Nothing was reviewed in this session." }
        let accuracy = Int((Double(correctCount) / Double(answeredCount) * 100).rounded())
        let elapsed = Int(Date().timeIntervalSince(sessionStartedAt ?? Date()))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        let time = minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        let tomorrow = store.dueCount(onDayAfter: Date())
        return "\(answeredCount) answered  ·  \(accuracy)% correct  ·  \(time)  ·  \(tomorrow) due tomorrow"
    }

    /// Chrome shared by home, summary and the empty deck: no card, no grading, no top bar.
    private func presentNonCardChrome() {
        currentContext = nil
        isContextExpanded = false
        updateContextDisplay()
        sourceContainer.isHidden = false
        speakSourceButton.isHidden = true
        speakSlowSourceButton.isHidden = true
        speakShortcutLabel.isHidden = true
        speakSlowShortcutLabel.isHidden = true
        openTranslateButton.isHidden = true
        openTranslateShortcutLabel.isHidden = true
        resultLabel.stringValue = ""
        resultLabel.isHidden = true
        hideReadingChat()
        revealButton.isHidden = true
        buttonStack.isHidden = true
        answerField.isHidden = true
        choiceStack.isHidden = true
        feedbackLabel.isHidden = true
        hintLabel.isHidden = true
        topBarStack.isHidden = true
        termLabel.font = .systemFont(ofSize: 22, weight: .bold)
        backButton.isHidden = true
        stopAudio()
    }

    @objc private func startReviewSession() {
        startSession()
        // "Review Anyway" on a day with nothing due still deserves cards to look at.
        if recordsToReview.isEmpty {
            startPracticeReview(shuffled: false)
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
        recordsToReview = ReviewPlanner.interleave(saved) { $0.sourceText }
        beginSession()
    }

    @objc private func revealAnswer() {
        guard !isHomeScreen, !isReadingMode else { return }
        guard !recordsToReview.isEmpty, currentIndex < recordsToReview.count else { return }
        isAnswerRevealed = true
        // Whatever the question was, the flipped card shows the term itself again.
        let record = recordsToReview[currentIndex]
        if hasActiveQuestion {
            termLabel.stringValue = displayTerm(of: record)
            termLabel.font = .systemFont(ofSize: 22, weight: .bold)
            answerField.isHidden = true
            choiceStack.isHidden = true
            updateContextDisplay()
            openTranslateButton.isHidden = false
            openTranslateShortcutLabel.isHidden = false
            speakSlowSourceButton.isHidden = false
            speakSlowShortcutLabel.isHidden = false
            speakShortcutLabel.isHidden = false
        }
        resultLabel.isHidden = false
        revealButton.isHidden = true
        buttonStack.isHidden = false
        speakSourceButton.isHidden = false

        adjustWindowHeightForContentIfNeeded()
    }

    /// The stored source text can carry an appended context sentence; only the term is the answer.
    private func displayTerm(of record: TranslationRecord) -> String {
        guard let range = record.sourceText.range(of: " (context: ") else { return record.sourceText }
        return String(record.sourceText[..<range.lowerBound])
    }

    private func showAnswerFeedback(correct: Bool, note: String) {
        feedbackLabel.stringValue = correct ? "Correct. \(note)" : "Not quite. \(note)"
        feedbackLabel.textColor = correct ? .systemGreen : .systemRed
        feedbackLabel.isHidden = false
    }

    private func showHint(_ text: String?) {
        hintLabel.stringValue = text ?? ""
        hintLabel.isHidden = (text ?? "").isEmpty
    }

    /// A card missed this often is not being learnt, and saying so is more useful than showing it
    /// again tomorrow.
    private func leechNote(for record: TranslationRecord) -> String? {
        guard ReviewPlanner.isLeech(lapses: record.lapses) else { return nil }
        return "Missed \(record.lapses) times. Consider removing it and learning it from a fresh card."
    }

    /// The question knew whether the answer was right, so it grades itself instead of asking the
    /// learner to judge the same recall a second time. The three buttons stay live as an override.
    private func autoGrade(correct: Bool, nearMiss: Bool) {
        let elapsed = Date().timeIntervalSince(questionShownAt ?? Date())
        let grade = ReviewPlanner.autoGrade(correct: correct, nearMiss: nearMiss, elapsed: elapsed)
        pendingAutoGrade = grade
        let name = ["Again", "Hard", "Easy"][grade.rawValue]
        showHint("Graded \(name) automatically. Space to continue, or pick another grade.")
    }

    @objc private func submitClozeAnswer() {
        guard case let .typed(question, kind) = activeQuestion, !isAnswerRevealed else { return }
        let typed = answerField.stringValue
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let correct = question.matches(typed)
        let nearMiss = !correct && ReviewPlanner.isNearMiss(typed: typed, answer: question.answer)
        let note = nearMiss
            ? "Just a typo: \(question.answer)"
            : "Answer: \(question.answer)"
        showAnswerFeedback(correct: correct || nearMiss, note: note)
        autoGrade(correct: correct || nearMiss, nearMiss: nearMiss)
        if kind == .listen { stopAudio() }
        revealAnswer()
    }

    @objc private func chooseFirst() { chooseContrast(index: 0) }
    @objc private func chooseSecond() { chooseContrast(index: 1) }

    private func chooseContrast(index: Int) {
        guard case let .contrast(drill, choices) = activeQuestion, !isAnswerRevealed else { return }
        guard index < choices.count else { return }
        let correct = choices[index].caseInsensitiveCompare(drill.correct) == .orderedSame
        let note = drill.explanation.isEmpty
            ? "Answer: \(drill.correct)"
            : "\(drill.correct): \(drill.explanation)"
        showAnswerFeedback(correct: correct, note: note)
        autoGrade(correct: correct, nearMiss: false)
        revealAnswer()
    }

    @objc private func modeChanged() {
        // Item 0 is Auto; the rest follow QuestionKind order.
        requestedKind = ReviewPlanner.QuestionKind(rawValue: modePopup.indexOfSelectedItem - 1)
    }

    // MARK: - Reading passage

    /// Terms the passage should weave together: this session's cards when there is a session,
    /// otherwise what is due, otherwise the saved deck.
    private func readingPool() -> [TranslationRecord] {
        // Words missed in this session are the ones worth seeing again in context.
        let missed = recordsToReview.filter { missedTerms.contains(displayTerm(of: $0)) }
        if !missed.isEmpty { return missed.filter { $0.mode == .learn } }
        var pool = recordsToReview
        if pool.isEmpty { pool = store.dueReviews() }
        if pool.isEmpty { pool = store.records.filter { $0.isSaved } }
        return pool.filter { $0.mode == .learn }
    }

    private func readingWords() -> [String] {
        Translator.weaveWords(readingPool().map { displayTerm(of: $0) })
    }

    @objc private func showReadingPassage() {
        didRetryWeave = false
        requestReadingPassage()
    }

    private func requestReadingPassage() {
        let words = readingWords()
        guard !words.isEmpty else { return }
        readingWordsInPlay = words
        // The prompt actually in use decides the passage, so it decides the cache key too.
        let key = WeaveCache.cacheKey(
            words: words,
            promptVersion: AppConfig.weavePromptVersion,
            prompt: (config ?? AppConfig.load()).weavePrompt
        )
        if let cached = WeaveCache.load(key: key) {
            presentReading(cached.text, words: words)
            return
        }
        guard let translator else {
            presentReading("No translator is configured, so the passage cannot be generated.", words: words)
            return
        }
        presentReading("Generating a passage from \(words.count) words…", words: words)
        // The words come from these records, so their own language pair is the right one to ask
        // for. `config.sourceLang` is often "Auto detect", which means nothing to the model here.
        let first = readingPool().first
        let sourceLang = first?.sourceLanguage ?? "English"
        let targetLang = first?.targetLanguage ?? config?.targetLang ?? "Vietnamese"
        weaveRequest?.cancel()
        weaveRequest = translator.weave(words, sourceLang: sourceLang, targetLang: targetLang) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isReadingMode else { return }
                switch result {
                case let .success(text):
                    // A model that quietly drops a word leaves the learner short of practice, so
                    // one missed word buys one more attempt before the passage is kept.
                    let missing = Self.wordsMissing(from: text, words: words)
                    if !missing.isEmpty, !self.didRetryWeave {
                        self.didRetryWeave = true
                        self.requestReadingPassage()
                        return
                    }
                    WeaveCache.store(
                        WeavePassage(words: words, text: text, promptVersion: AppConfig.weavePromptVersion, generatedAt: Date()),
                        key: key
                    )
                    self.presentReading(text, words: words)
                case let .failure(error):
                    self.presentReading("Could not generate the passage: \(error.localizedDescription)", words: words)
                }
            }
        }
    }

    private func presentReading(_ text: String, words: [String]) {
        isReadingMode = true
        readingWordsInPlay = words
        stopAudio()
        completedImageView.isHidden = true
        progressLabel.stringValue = "Reading passage  ·  \(words.count) words"
        termLabel.stringValue = "Reading"
        termLabel.font = .systemFont(ofSize: 22, weight: .bold)
        sourceContainer.isHidden = false
        hideSourceGiveaways()
        answerField.isHidden = true
        choiceStack.isHidden = true
        feedbackLabel.isHidden = true
        if let dialogue = ReadingDialogue.parse(text) {
            readingChatView.show(dialogue, words: words)
            readingChatView.isHidden = false
            readingModeControl.isHidden = false
            readingModeControl.selectedSegment = readingChatView.currentMode.rawValue
            resultLabel.isHidden = true
        } else {
            hideReadingChat()
            resultLabel.attributedStringValue = Self.readingDisplay(text, words: words)
            resultLabel.isHidden = false
        }
        revealButton.isHidden = true
        buttonStack.isHidden = true
        completedStack.isHidden = true
        startOptionsStack.isHidden = true
        startButton.isHidden = true
        statsLabel.isHidden = true
        hintLabel.isHidden = true
        topBarStack.isHidden = false
        undoButton.isEnabled = false
        hideButton.isEnabled = false
        backButton.isHidden = false
        adjustWindowHeightForContentIfNeeded()
    }

    /// Which of the requested words never made it into the passage.
    static func wordsMissing(from text: String, words: [String]) -> [String] {
        words.filter { ReadingHighlight.ranges(in: text, words: [$0]).isEmpty }
    }

    private func hideReadingChat() {
        readingChatView.isHidden = true
        readingModeControl.isHidden = true
    }

    @objc private func readingModeChanged() {
        guard let mode = ReadingChatView.Mode(rawValue: readingModeControl.selectedSegment) else { return }
        readingChatView.setGlobalMode(mode)
    }

    /// One line of the conversation, spoken in the language it is written in. These lines are not
    /// cards, so nothing is cached: each click is its own request.
    private func speakReadingLine(_ line: String, slow: Bool) {
        let speechCfg = config ?? AppConfig.load()
        let language = readingPool().first?.sourceLanguage ?? "English"
        let identity = SpeechIdentity(
            kind: .source,
            text: line,
            model: SpeechModelResolver.model(for: language, config: speechCfg)
        )
        handleSpeechPlay(speed: slow ? speechCfg.speechSlowRate : 1.0, identity: identity)
    }

    /// An underlined word came from one of the cards in play, so clicking it can open that card in
    /// the translate panel with its history already there.
    private func openTranslateForWord(_ word: String) {
        guard let record = readingPool().first(where: {
            displayTerm(of: $0).caseInsensitiveCompare(word) == .orderedSame
        }) else { return }
        stopAudio()
        onOpenTranslate?(record)
    }

    @objc private func showPassageList(_ sender: NSButton) {
        savedPassages = WeaveCache.all()
        let menu = NSMenu()
        if savedPassages.isEmpty {
            let empty = NSMenuItem(title: "No saved passages yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for (index, passage) in savedPassages.enumerated() {
            let item = NSMenuItem(title: Self.passageTitle(passage), action: #selector(openSavedPassage(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// The topic line the passage was generated with. Passages made before the prompt asked for one
    /// fall back to their first spoken line, so every row still says something.
    static func passageTitle(_ passage: WeavePassage) -> String {
        let dialogue = ReadingDialogue.parse(passage.text)
        let topic = dialogue?.topic ?? ""
        let fallback = dialogue?.turns.first?.source ?? passage.words.joined(separator: ", ")
        var title = topic.isEmpty ? fallback : topic
        if title.count > 60 { title = String(title.prefix(59)) + "…" }
        let date = DateFormatter.localizedString(from: passage.generatedAt, dateStyle: .short, timeStyle: .none)
        return "\(title)  ·  \(passage.words.count) words  ·  \(date)"
    }

    @objc private func openSavedPassage(_ sender: NSMenuItem) {
        guard sender.tag < savedPassages.count else { return }
        let passage = savedPassages[sender.tag]
        stopAudio()
        presentReading(passage.text, words: passage.words)
    }

    private static func readingDisplay(_ text: String, words: [String]) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ])
        for range in ReadingHighlight.ranges(in: text, words: words) {
            attributed.addAttributes([
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .foregroundColor: NSColor.labelColor
            ], range: range)
        }
        return attributed
    }

    @objc private func leaveReading() {
        weaveRequest?.cancel()
        weaveRequest = nil
        isReadingMode = false
        if isHomeScreen || recordsToReview.isEmpty || currentIndex >= recordsToReview.count {
            showHome()
        } else {
            loadCurrentCard()
        }
    }

    private func adjustWindowHeightForContentIfNeeded() {
        guard let window else { return }
        let resultText = resultLabel.stringValue
        guard !resultText.isEmpty else { return }

        // Expand height ~1.7x when translation result is long
        let targetHeight: CGFloat = (resultText.count > 150 || resultText.contains("\n\n"))
            ? ReviewLayout.expandedHeight
            : ReviewLayout.compactHeight
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
        if isReadingMode {
            updateReadingSpeechUI()
            return
        }
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
                speakSourceButton.image = makeSymbolImage(name: "speaker.wave.2", description: "Speak source (4 / 1.0x)")
                speakSourceButton.toolTip = "Speak source (4 / 1.0x)"
            }
        } else {
            speakSourceButton.image = makeSymbolImage(name: "speaker.wave.2", description: "Speak source (4 / 1.0x)")
            speakSourceButton.toolTip = "Speak source (4 / 1.0x)"
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
                speakSlowSourceButton.image = makeSymbolImage(name: "tortoise", description: "Speak source slowly (5)")
                speakSlowSourceButton.toolTip = "Speak source slowly (5)"
            }
        } else {
            speakSlowSourceButton.image = makeSymbolImage(name: "tortoise", description: "Speak source slowly (5)")
            speakSlowSourceButton.toolTip = "Speak source slowly (5)"
        }

        speakSourceButton.isEnabled = true
        speakSlowSourceButton.isEnabled = true
    }

    /// In reading mode the speak buttons live in the bubbles, so the same state drives them.
    private func updateReadingSpeechUI() {
        let slowRate = config?.speechSlowRate ?? AppConfig.default.speechSlowRate
        let isSlow = abs(activeSpeechRate - slowRate) < 0.01
        let action = activeSpeechIdentity.map { speechState.action(for: $0) } ?? .play
        readingChatView.updateSpeech(line: activeSpeechIdentity?.text, isSlow: isSlow, action: action)
    }

    @objc private func speakCurrentSource() {
        handleSpeechPlay(speed: 1.0)
    }

    /// Opens the current card in the translate panel without closing this review window.
    @objc private func openTranslatePopup() {
        stopAudio()
        guard currentIndex < recordsToReview.count else { return }
        onOpenTranslate?(recordsToReview[currentIndex])
    }

    @objc private func speakCurrentSourceSlow() {
        handleSpeechPlay(speed: config?.speechSlowRate ?? 0.4)
    }

    private func handleSpeechPlay(speed: Float, identity providedIdentity: SpeechIdentity? = nil) {
        guard let identity = providedIdentity ?? currentSourceSpeechIdentity() else { return }

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
        SpeechTrim.seekPastLeadingSilence(player, data: data)

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
        guard let grade = SRSGrade(rawValue: sender.tag) else { return }
        applyGrade(grade)
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
        removeKeyEventMonitor()
    }
}
