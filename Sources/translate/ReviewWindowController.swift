// The Study window. It owns the session state, the SRS grading, speech playback and the reading
// passage, and swaps one screen view at a time into the card: home, session, summary, new words.
import AppKit
import AVFoundation

private enum ReviewLayout {
    static let contextTruncateLimit = 100
    static let compactHeight: CGFloat = 520
    static let expandedHeight: CGFloat = 720
}

@MainActor
final class ReviewWindowController: NSWindowController, NSWindowDelegate, @preconcurrency AVAudioPlayerDelegate {
    private enum Screen { case home, session, summary, newWords }

    private enum ActiveQuestion {
        /// Cloze, Recall and Listen all ask for one typed word; only the prompt differs.
        case typed(LearnCard.ClozeQuestion, kind: ReviewPlanner.QuestionKind)
        case contrast(ConfusableDrillItem, choices: [String])
        case none
    }

    private var store: TranslationHistoryStore
    var translator: Translator?
    var config: AppConfig?

    /// Called when the learning options on the home screen change, so they survive a relaunch.
    var onLearningSettingsChanged: ((AppConfig.LearningSettings) -> Void)?
    var onReviewsCompleted: (() -> Void)?
    /// Lets the app drop back to a menu-bar utility once this window is gone.
    var onWindowClosed: (() -> Void)?
    var onOpenTranslate: ((TranslationRecord) -> Void)?

    private var recordsToReview: [TranslationRecord] = []
    private var currentIndex = 0
    private var isAnswerRevealed = false
    private var audioPlayer: AVAudioPlayer?
    private var isPracticeMode = false
    private var screen: Screen = .home
    private var isReadingMode = false

    /// nil means Auto: the card picks its own question from how well it is known.
    private var requestedKind: ReviewPlanner.QuestionKind?
    private var sessionLimit: Int?
    private var selectedBucket: DeckStats.Bucket?
    private var activeQuestion: ActiveQuestion = .none

    // Session bookkeeping: everything below resets when a session starts.
    private var questionShownAt: Date?
    private var sessionStartedAt: Date?
    private var answeredCount = 0
    private var correctCount = 0
    private var missedTerms: [String] = []
    private var missedLapses: [String: Int] = [:]
    private var relearnCounts: [UUID: Int] = [:]
    private var pendingAutoGrade: SRSGrade?
    private var undoSnapshot: (record: TranslationRecord, index: Int)?

    private var currentContext: String?
    private var isContextExpanded = false
    private var speechState = SpeechPlaybackState()
    private var activeSpeechIdentity: SpeechIdentity?
    private var activeSpeechRate: Float = 1.0
    private var pendingNewWordSpeech: SpeechIdentity?

    // Reading passage
    private var weaveRequest: RequestHandle?
    private var didRetryWeave = false
    private var savedPassages: [WeavePassage] = []

    // New words
    private var newWordsQueue: [VocabPackEntry] = []
    private var newWordsIndex = 0
    private var newWordsLevel: VocabDiscovery.Level?
    private var newWordsLearned = 0

    private let cardView = NSVisualEffectView()
    private var homeView: ReviewHomeView!
    private let sessionView = ReviewSessionView()
    private let summaryView = ReviewSummaryView()
    private let newWordsView = NewWordsView()
    private var keyEventMonitor: Any?
    private var sessionTimer: Timer?
    private var didShowReview = false

    /// True while the card is asking something instead of just showing its term.
    private var hasActiveQuestion: Bool {
        if case .none = activeQuestion { return false }
        return true
    }

    init(store: TranslationHistoryStore, translator: Translator? = nil, config: AppConfig? = nil) {
        self.store = store
        self.translator = translator
        self.config = config
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 560, height: 460)
        window.isReleasedWhenClosed = false
        window.title = "Study"
        window.setFrameAutosaveName("ReviewSRSWindow")

        super.init(window: window)
        window.delegate = self
        applyStoredOptions()
        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func updateDependencies(store: TranslationHistoryStore, translator: Translator?, config: AppConfig) {
        self.store = store
        self.translator = translator
        self.config = config
    }

    private func applyStoredOptions() {
        let learning = (config ?? AppConfig.load()).learning
        sessionLimit = learning.reviewSessionLimit
        requestedKind = learning.reviewQuestionKind.flatMap { label in
            ReviewPlanner.QuestionKind.allCases.first { $0.label == label }
        }
        selectedBucket = learning.reviewFilter.flatMap(DeckStats.Bucket.init(rawValue:))
        newWordsLevel = learning.newWordsLevel.flatMap(VocabDiscovery.Level.init(rawValue:))
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
        content.addSubview(cardView)

        homeView = ReviewHomeView(limit: sessionLimit, kind: requestedKind, bucket: selectedBucket)
        homeView.delegate = self
        sessionView.delegate = self
        summaryView.delegate = self
        newWordsView.delegate = self
        sessionView.readingChatView.onSpeak = { [weak self] line, isSlow in self?.speakReadingLine(line, slow: isSlow) }
        sessionView.readingChatView.onWord = { [weak self] word in self?.openTranslateForWord(word) }
        // Selecting the text hands it to the field editor, which drops every attribute unless the
        // field says attributes are its own. Without this the reading underlines vanish on click.
        sessionView.resultLabel.allowsEditingTextAttributes = true

        for screen in [homeView, sessionView, summaryView, newWordsView] as [NSView] {
            screen.translatesAutoresizingMaskIntoConstraints = false
            screen.isHidden = true
            cardView.addSubview(screen)
            NSLayoutConstraint.activate([
                screen.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                screen.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                screen.topAnchor.constraint(equalTo: cardView.topAnchor),
                screen.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            cardView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            cardView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            cardView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
    }

    private func show(_ screen: Screen) {
        self.screen = screen
        homeView.isHidden = screen != .home
        sessionView.isHidden = screen != .session
        summaryView.isHidden = screen != .summary
        newWordsView.isHidden = screen != .newWords
        sessionTimer?.invalidate()
        sessionTimer = nil
        if screen == .session, !isReadingMode {
            // One tick a second is enough to keep the session clock honest.
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshSessionChrome() }
            }
            RunLoop.main.add(timer, forMode: .common)
            sessionTimer = timer
        }
    }

    func showReview() {
        installKeyEventMonitorIfNeeded()
        showWindow(nil)
        if !didShowReview {
            didShowReview = true
            // Autosave restores a saved frame before first show; only centre the constructed default.
            if let window, window.frame.origin == .zero { window.center() }
        }
        window?.makeKeyAndOrderFront(nil)
        showHome()
    }

    // MARK: - Home

    private func showHome() {
        isReadingMode = false
        clearActiveQuestion()
        stopAudio()
        show(.home)
        refreshHome()
    }

    private func refreshHome() {
        let stats = DeckStats.compute(records: store.records)
        homeView.update(
            stats: stats,
            readingEnabled: !readingWords().isEmpty,
            missedCount: missedTerms.count,
            hasSavedCards: stats.totalSaved > 0
        )
    }

    /// The cards a Start would queue: the chosen bucket, or everything due, capped by the limit.
    private func plannedRecords() -> [TranslationRecord] {
        let saved = store.records.filter { $0.isSaved }
        let pool: [TranslationRecord]
        if let selectedBucket {
            pool = saved.filter { DeckStats.bucket(for: $0) == selectedBucket }
        } else {
            pool = store.dueReviews()
        }
        let limit = sessionLimit ?? max(1, pool.count)
        return Self.sessionRecords(due: pool, dailyReviewLimit: limit)
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

    // MARK: - Session lifecycle

    private func startSession() {
        isPracticeMode = false
        recordsToReview = plannedRecords()
        // "Review Anyway" on a day with nothing due still deserves cards to look at.
        if recordsToReview.isEmpty {
            startPracticeReview(shuffled: false)
            return
        }
        beginSession()
    }

    private func startPracticeReview(shuffled: Bool, records: [TranslationRecord]? = nil) {
        var pool = records ?? store.records.filter { $0.isSaved }
        guard !pool.isEmpty else { return }
        if shuffled { pool.shuffle() }
        isPracticeMode = true
        recordsToReview = ReviewPlanner.interleave(pool) { $0.sourceText }
        beginSession()
    }

    private func beginSession() {
        currentIndex = 0
        isAnswerRevealed = false
        isReadingMode = false
        sessionStartedAt = Date()
        answeredCount = 0
        correctCount = 0
        missedTerms.removeAll()
        missedLapses.removeAll()
        relearnCounts.removeAll()
        undoSnapshot = nil
        show(.session)
        loadCurrentCard()
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
        let term = displayTerm(of: record)
        missedLapses[term, default: 0] += 1
        if !missedTerms.contains(term) { missedTerms.append(term) }
        let seen = relearnCounts[record.id] ?? 0
        guard seen < ReviewPlanner.maxRelearnPerCard else { return }
        relearnCounts[record.id] = seen + 1
        let target = ReviewPlanner.requeueIndex(currentIndex: currentIndex, count: recordsToReview.count)
        recordsToReview.insert(record, at: target)
    }

    private func undoLastGrade() {
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
        isReadingMode = false
        show(.session)
        loadCurrentCard()
    }

    /// Leeches and cards the learner no longer wants leave the deck the same way they entered it.
    private func hideCurrentCard() {
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

    private func goHome() {
        stopAudio()
        weaveRequest?.cancel()
        weaveRequest = nil
        isReadingMode = false
        showHome()
    }

    // MARK: - Card rendering

    private func loadCurrentCard() {
        if recordsToReview.isEmpty || currentIndex >= recordsToReview.count {
            showSummary()
            return
        }
        show(.session)
        let record = recordsToReview[currentIndex]
        sessionView.undoButton.isEnabled = undoSnapshot != nil
        sessionView.hideButton.isEnabled = !isPracticeMode

        let sourceText = record.sourceText
        if let range = sourceText.range(of: " (context: ") {
            var context = String(sourceText[range.upperBound...])
            if context.hasSuffix(")") { context = String(context.dropLast()) }
            sessionView.termLabel.stringValue = String(sourceText[..<range.lowerBound])
            currentContext = context
        } else {
            sessionView.termLabel.stringValue = sourceText
            currentContext = nil
        }
        isContextExpanded = false
        updateContextDisplay()

        sessionView.sourceContainer.isHidden = false
        setSourceGiveaways(hidden: false)
        sessionView.resultLabel.stringValue = record.resultText
        sessionView.resultLabel.isHidden = true
        hideReadingChat()
        sessionView.revealButton.isHidden = false
        sessionView.backButton.isHidden = true
        sessionView.gradeStack.isHidden = true
        isAnswerRevealed = false
        stopAudio()
        updateSpeakButtonUI()

        pendingAutoGrade = nil
        let asked = question(for: record)
        activeQuestion = asked.0
        applyQuestionLayer(kind: asked.kind)
        setPills(for: record, kind: asked.kind)
        updateGradeIntervals(for: record)
        refreshSessionChrome()
        showHint(asked.note ?? leechNote(for: record))

        // Auto play source speech ONLY if cached locally. In a question mode the source word is
        // the answer, so speaking it would hand it over before the learner tries.
        if !hasActiveQuestion,
           let data = try? store.audioData(for: record.id, kind: .source),
           SpeechAudioPolicy.isValid(data) {
            playAudio(data, speed: 1.0)
        }
    }

    private func refreshSessionChrome() {
        guard screen == .session else { return }
        let remaining = max(0, recordsToReview.count - currentIndex)
        sessionView.updateProgress(
            correct: correctCount,
            wrong: max(0, answeredCount - correctCount),
            remaining: remaining,
            elapsed: Date().timeIntervalSince(sessionStartedAt ?? Date()),
            practice: isPracticeMode
        )
    }

    private func setPills(for record: TranslationRecord, kind: ReviewPlanner.QuestionKind) {
        var pills = [kind.label, DeckStats.bucket(for: record).label]
        pills.append("lần \(record.repetitions + 1)")
        if let last = record.lastReviewedAt {
            let days = Calendar.current.dateComponents(
                [.day],
                from: Calendar.current.startOfDay(for: last),
                to: Calendar.current.startOfDay(for: Date())
            ).day ?? 0
            pills.append(days <= 0 ? "ôn hôm nay" : "ôn \(days) ngày trước")
        }
        if (relearnCounts[record.id] ?? 0) > 0 { pills.append("relearning") }
        pills.append("\(record.sourceLanguage) → \(record.targetLanguage)")
        sessionView.setPills(pills)
    }

    /// Fuzz is pinned to 1.0 here: this is a preview, and a preview that moves every render would
    /// read as a bug. The real grade still schedules with `ReviewPlanner.randomFuzz()`.
    private func updateGradeIntervals(for record: TranslationRecord) {
        func preview(_ grade: SRSGrade) -> String {
            let next = ReviewPlanner.nextSchedule(
                grade: grade,
                interval: record.interval,
                ease: record.ease,
                fuzz: 1.0
            )
            return Self.intervalText(next.interval)
        }
        sessionView.setGradeIntervals(again: preview(.again), hard: preview(.hard), easy: preview(.easy))
    }

    static func intervalText(_ days: Int) -> String {
        switch days {
        case ..<1: return "hôm nay"
        case 1: return "1 ngày"
        case 2..<30: return "\(days) ngày"
        case 30..<365: return "\(days / 30) tháng"
        default: return "\(max(1, days / 365)) năm"
        }
    }

    private func updateContextDisplay() {
        guard let context = currentContext, !context.isEmpty else {
            sessionView.contextLabel.stringValue = ""
            sessionView.contextLabel.isHidden = true
            sessionView.readMoreButton.isHidden = true
            return
        }
        sessionView.contextLabel.isHidden = false
        if context.count > ReviewLayout.contextTruncateLimit {
            sessionView.readMoreButton.isHidden = false
            if isContextExpanded {
                sessionView.contextLabel.stringValue = "Context: \(context)"
                sessionView.readMoreButton.title = "Show less"
            } else {
                sessionView.contextLabel.stringValue = "Context: \(context.prefix(ReviewLayout.contextTruncateLimit))..."
                sessionView.readMoreButton.title = "Read more"
            }
        } else {
            sessionView.contextLabel.stringValue = "Context: \(context)"
            sessionView.readMoreButton.isHidden = true
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

    private func applyQuestionLayer(kind: ReviewPlanner.QuestionKind) {
        sessionView.answerField.stringValue = ""
        sessionView.feedbackLabel.isHidden = true
        questionShownAt = Date()
        switch activeQuestion {
        case .none:
            sessionView.answerField.isHidden = true
            sessionView.choiceStack.isHidden = true
            sessionView.termLabel.font = .systemFont(ofSize: 24, weight: .bold)
        case let .typed(question, kind):
            sessionView.termLabel.stringValue = question.prompt
            sessionView.termLabel.font = .systemFont(ofSize: 17, weight: .regular)
            sessionView.answerField.isHidden = false
            sessionView.answerField.placeholderString = kind == .cloze
                ? "Type the missing word, then press Return"
                : "Type the word, then press Return"
            sessionView.choiceStack.isHidden = true
            setSourceGiveaways(hidden: true)
            if kind == .listen {
                // The whole question is the sound, so the speak buttons stay and play at once.
                sessionView.speakSourceButton.isHidden = false
                sessionView.speakSlowSourceButton.isHidden = false
                sessionView.speakShortcutLabel.isHidden = false
                sessionView.speakSlowShortcutLabel.isHidden = false
                speakCurrentSource()
            }
            window?.makeFirstResponder(sessionView.answerField)
        case let .contrast(drill, choices):
            sessionView.termLabel.stringValue = drill.sentence
            sessionView.termLabel.font = .systemFont(ofSize: 17, weight: .regular)
            sessionView.answerField.isHidden = true
            sessionView.choiceStack.isHidden = false
            sessionView.firstChoiceButton.title = "  " + (choices.first ?? "")
            sessionView.secondChoiceButton.title = "  " + (choices.last ?? "")
            setSourceGiveaways(hidden: true)
        }
    }

    /// The term, its audio, and the Translate shortcut all reveal the answer, so they wait until
    /// the card is flipped.
    private func setSourceGiveaways(hidden: Bool) {
        sessionView.speakSourceButton.isHidden = hidden
        sessionView.speakSlowSourceButton.isHidden = hidden
        sessionView.speakShortcutLabel.isHidden = hidden
        sessionView.speakSlowShortcutLabel.isHidden = hidden
        sessionView.openTranslateButton.isHidden = hidden
        sessionView.openTranslateShortcutLabel.isHidden = hidden
        if hidden {
            sessionView.contextLabel.isHidden = true
            sessionView.readMoreButton.isHidden = true
        }
    }

    private func revealAnswer() {
        guard screen == .session, !isReadingMode else { return }
        guard !recordsToReview.isEmpty, currentIndex < recordsToReview.count else { return }
        isAnswerRevealed = true
        let record = recordsToReview[currentIndex]
        // Whatever the question was, the flipped card shows the term itself again.
        if hasActiveQuestion {
            sessionView.termLabel.stringValue = displayTerm(of: record)
            sessionView.termLabel.font = .systemFont(ofSize: 24, weight: .bold)
            sessionView.answerField.isHidden = true
            sessionView.choiceStack.isHidden = true
            updateContextDisplay()
            setSourceGiveaways(hidden: false)
        }
        sessionView.resultLabel.isHidden = false
        sessionView.revealButton.isHidden = true
        sessionView.gradeStack.isHidden = false
        adjustWindowHeightForContentIfNeeded()
    }

    /// The stored source text can carry an appended context sentence; only the term is the answer.
    private func displayTerm(of record: TranslationRecord) -> String {
        guard let range = record.sourceText.range(of: " (context: ") else { return record.sourceText }
        return String(record.sourceText[..<range.lowerBound])
    }

    private func showAnswerFeedback(correct: Bool, note: String) {
        sessionView.feedbackLabel.stringValue = correct ? "Correct. \(note)" : "Not quite. \(note)"
        sessionView.feedbackLabel.textColor = correct ? .systemGreen : .systemRed
        sessionView.feedbackLabel.isHidden = false
    }

    private func showHint(_ text: String?) {
        sessionView.hintLabel.stringValue = text ?? ""
        sessionView.hintLabel.isHidden = (text ?? "").isEmpty
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

    private func submitTypedAnswer() {
        guard case let .typed(question, kind) = activeQuestion, !isAnswerRevealed else { return }
        let typed = sessionView.answerField.stringValue
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let correct = question.matches(typed)
        let nearMiss = !correct && ReviewPlanner.isNearMiss(typed: typed, answer: question.answer)
        let note = nearMiss ? "Just a typo: \(question.answer)" : "Answer: \(question.answer)"
        showAnswerFeedback(correct: correct || nearMiss, note: note)
        autoGrade(correct: correct || nearMiss, nearMiss: nearMiss)
        if kind == .listen { stopAudio() }
        revealAnswer()
    }

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

    /// Leaving the card behind has to take its question with it, or a later keystroke would
    /// answer or grade a card that is no longer on screen.
    private func clearActiveQuestion() {
        activeQuestion = .none
        isAnswerRevealed = false
        pendingAutoGrade = nil
        questionShownAt = nil
    }

    // MARK: - Summary

    private func showSummary() {
        clearActiveQuestion()
        stopAudio()
        show(.summary)
        let stats = DeckStats.compute(records: store.records)
        let remaining = isPracticeMode ? 0 : max(0, stats.dueToday)
        var result = ReviewSummaryView.Result()
        result.answered = answeredCount
        result.correct = correctCount
        result.elapsed = Date().timeIntervalSince(sessionStartedAt ?? Date())
        result.remainingToday = remaining
        result.dueTomorrow = stats.dueTomorrow
        result.isPractice = isPracticeMode
        result.missed = missedTerms.map { term in
            let record = store.records.first { displayTerm(of: $0) == term }
            return ReviewSummaryView.Missed(
                term: term,
                meaning: record.map { LearnCard.parse($0.resultText).meanings.first ?? "" } ?? "",
                lapses: record?.lapses ?? missedLapses[term] ?? 1,
                isLeech: ReviewPlanner.isLeech(lapses: record?.lapses ?? 0)
            )
        }
        summaryView.update(result, readingEnabled: !readingWords().isEmpty)
        if !isPracticeMode { onReviewsCompleted?() }
    }

    private func redrillMissed() {
        let records = store.records.filter { $0.isSaved && missedTerms.contains(displayTerm(of: $0)) }
        guard !records.isEmpty else { return }
        startPracticeReview(shuffled: false, records: records)
    }

    // MARK: - New words

    private func showNewWords() {
        stopAudio()
        clearActiveQuestion()
        isReadingMode = false
        show(.newWords)
        newWordsLearned = 0
        rebuildNewWordsQueue()
    }

    private func rebuildNewWordsQueue() {
        VocabProgressStore.shared.load()
        let progress = VocabProgressStore.shared.progress
        let entries = VocabPack.shared.allEntries()
        let inStore = Set(store.records.filter { $0.isSaved }.map { VocabPack.normalize(displayTerm(of: $0)) })
        newWordsView.setLevels(
            VocabDiscovery.remainingByLevel(entries: entries, progress: progress, inStore: inStore),
            selected: newWordsLevel
        )
        newWordsQueue = VocabDiscovery.queue(
            entries: entries,
            level: newWordsLevel,
            progress: progress,
            inStore: inStore
        )
        newWordsIndex = 0
        showCurrentNewWord()
    }

    private func showCurrentNewWord() {
        guard newWordsIndex < newWordsQueue.count else {
            newWordsView.showEmpty(
                message: VocabPack.shared.isEmpty
                    ? "Không tìm thấy kho từ vựng. Kiểm tra tệp vocab-en-vi.json trong Application Support."
                    : "Hết từ ở mức này. Chọn cấp độ khác ở góc trên bên trái."
            )
            stopAudio()
            return
        }
        let entry = newWordsQueue[newWordsIndex]
        let progress = VocabProgressStore.shared.progress
        newWordsView.show(
            word: entry.w,
            detail: entry.r,
            remaining: newWordsQueue.count - newWordsIndex,
            learned: newWordsLearned,
            known: progress.known.count,
            skipped: progress.skipped.count
        )
        stopAudio()
        pendingNewWordSpeech = newWordSpeechIdentity(for: entry.w)
        updateSpeakButtonUI()
    }

    private func decideNewWord(_ decision: NewWordsView.Decision) {
        guard newWordsIndex < newWordsQueue.count else { return }
        let entry = newWordsQueue[newWordsIndex]
        switch decision {
        case .known:
            VocabProgressStore.shared.record(.known, word: entry.w)
        case .skip:
            VocabProgressStore.shared.record(.skipped, word: entry.w)
            // A skipped word belongs at the back of the queue, not gone: move it there now so the
            // rest of this sitting keeps offering words never seen before.
            newWordsQueue.append(newWordsQueue.remove(at: newWordsIndex))
            showCurrentNewWord()
            return
        case .learn:
            addNewWordToDeck(entry)
        }
        newWordsIndex += 1
        showCurrentNewWord()
    }

    /// Materialize the pack entry into history the same way a pack hit from the popup does, then
    /// save it so it enters the deck due today.
    private func addNewWordToDeck(_ entry: VocabPackEntry) {
        let pair = (config ?? AppConfig.load())
        let record = TranslationRecord(
            id: UUID(),
            timestamp: Date(),
            mode: .learn,
            sourceText: entry.w,
            resultText: entry.r,
            sourceLanguage: VocabPack.shared.packSourceLanguage.isEmpty ? "English" : VocabPack.shared.packSourceLanguage,
            targetLanguage: pair.targetLang,
            isSaved: false
        )
        do {
            let stored = try store.appendIfAbsent(record)
            try store.setSaved(true, recordID: stored.id)
            VocabProgressStore.shared.clearSkip(word: entry.w)
            newWordsLearned += 1
        } catch {
            NSLog("[NTranslate] Failed to add new word: \(error.localizedDescription)")
        }
    }

    private func newWordSpeechIdentity(for word: String) -> SpeechIdentity {
        let speechCfg = config ?? AppConfig.load()
        let language = VocabPack.shared.packSourceLanguage.isEmpty ? "English" : VocabPack.shared.packSourceLanguage
        return SpeechIdentity(
            kind: .source,
            text: word,
            model: SpeechModelResolver.model(for: language, config: speechCfg)
        )
    }

    // MARK: - Keyboard

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
            // Escape steps back out of a screen first, and only closes from home.
            if screen != .home {
                goHome()
                return nil
            }
            stopAudio()
            window?.performClose(nil)
            return nil
        }
        if event.modifierFlags.contains(.command) {
            if chars.lowercased() == "z" {
                undoLastGrade()
                return nil
            }
            return event
        }
        switch screen {
        case .home:
            if chars == "\r" || chars == " " { startSession() }
            return chars == " " ? nil : event
        case .newWords:
            switch chars {
            case "1": decideNewWord(.known); return nil
            case "2": decideNewWord(.learn); return nil
            case "3": decideNewWord(.skip); return nil
            case "4": speakNewWord(slow: false); return nil
            case "5": speakNewWord(slow: true); return nil
            default: return event
            }
        case .summary:
            return event
        case .session:
            return handleSessionKey(event, chars: chars)
        }
    }

    private func handleSessionKey(_ event: NSEvent, chars: String) -> NSEvent? {
        // While the answer field has focus every key belongs to it, not to the shortcuts. Once the
        // field is hidden its editor can still hold first responder, and a hidden field has no
        // claim on the keyboard.
        if !sessionView.answerField.isHidden,
           let editor = window?.firstResponder as? NSText,
           editor.delegate === sessionView.answerField {
            return event
        }
        if isReadingMode {
            if !sessionView.readingModeControl.isHidden, let index = ["1", "2", "3"].firstIndex(of: chars) {
                sessionView.readingModeControl.selectedSegment = index
                readingModeChanged(index)
                return nil
            }
            return event
        }
        if !isAnswerRevealed, case .contrast = activeQuestion {
            if chars == "1" { chooseContrast(index: 0); return nil }
            if chars == "2" { chooseContrast(index: 1); return nil }
        }
        if chars == " " {
            handleSpaceKey()
            return nil
        }
        if isAnswerRevealed {
            if chars == "1" { applyGrade(.again); return nil }
            if chars == "2" { applyGrade(.hard); return nil }
            if chars == "3" { applyGrade(.easy); return nil }
        }
        if chars == "4" { speakCurrentSource(); return nil }
        if chars == "5" { speakCurrentSourceSlow(); return nil }
        if chars == "6" { openTranslatePopup(); return nil }
        return event
    }

    private func handleSpaceKey() {
        if !isAnswerRevealed {
            revealAnswer()
            return
        }
        // A question that graded itself only needs "next"; Space is that key.
        if let auto = pendingAutoGrade {
            applyGrade(auto)
            return
        }
        let clipView = sessionView.scrollView.contentView
        let visibleRect = clipView.documentVisibleRect
        let docHeight = sessionView.documentView.bounds.height
        if visibleRect.maxY < docHeight - 5 {
            let newY = min(docHeight - visibleRect.height, visibleRect.origin.y + clipView.bounds.height * 0.75)
            clipView.scroll(to: NSPoint(x: 0, y: max(0, newY)))
        } else {
            clipView.scroll(to: NSPoint(x: 0, y: 0))
        }
        sessionView.scrollView.reflectScrolledClipView(clipView)
    }

    // MARK: - Menu commands

    /// The Study menu drives the same paths as the buttons, and asks here whether an item applies.
    func canRunStudyCommand(_ command: StudyCommand) -> Bool {
        switch command {
        case .start: return screen == .home
        case .newWords: return screen != .newWords
        case .showAnswer: return screen == .session && !isReadingMode && !isAnswerRevealed
        case .grade: return screen == .session && !isReadingMode && isAnswerRevealed
        case .undo: return undoSnapshot != nil
        case .skip: return screen == .session && !isReadingMode && !isPracticeMode
        case .reading: return !readingWords().isEmpty
        case .passages: return true
        case .home: return screen != .home
        }
    }

    enum StudyCommand { case start, newWords, showAnswer, grade, undo, skip, reading, passages, home }

    func runStudyCommand(_ command: StudyCommand, grade: SRSGrade? = nil) {
        switch command {
        case .start: startSession()
        case .newWords: showNewWords()
        case .showAnswer: revealAnswer()
        case .grade: if let grade { applyGrade(grade) }
        case .undo: undoLastGrade()
        case .skip: hideCurrentCard()
        case .reading: showReadingPassage()
        case .passages: presentPassageMenu(from: nil)
        case .home: goHome()
        }
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

    private func showReadingPassage() {
        didRetryWeave = false
        requestReadingPassage()
    }

    private func requestReadingPassage() {
        let words = readingWords()
        guard !words.isEmpty else { return }
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
        stopAudio()
        show(.session)
        sessionView.setPills(["Reading", "\(words.count) từ"])
        sessionView.updateProgress(correct: 0, wrong: 0, remaining: 0, elapsed: 0, practice: false)
        sessionView.termLabel.stringValue = "Reading"
        sessionView.termLabel.font = .systemFont(ofSize: 22, weight: .bold)
        sessionView.sourceContainer.isHidden = false
        setSourceGiveaways(hidden: true)
        sessionView.answerField.isHidden = true
        sessionView.choiceStack.isHidden = true
        sessionView.feedbackLabel.isHidden = true
        if let dialogue = ReadingDialogue.parse(text) {
            sessionView.readingChatView.show(dialogue, words: words)
            sessionView.readingChatView.isHidden = false
            sessionView.readingModeControl.isHidden = false
            sessionView.readingModeControl.selectedSegment = sessionView.readingChatView.currentMode.rawValue
            sessionView.resultLabel.isHidden = true
        } else {
            hideReadingChat()
            sessionView.resultLabel.attributedStringValue = Self.readingDisplay(text, words: words)
            sessionView.resultLabel.isHidden = false
        }
        sessionView.revealButton.isHidden = true
        sessionView.gradeStack.isHidden = true
        sessionView.hintLabel.isHidden = true
        sessionView.undoButton.isEnabled = false
        sessionView.hideButton.isEnabled = false
        sessionView.backButton.isHidden = false
        adjustWindowHeightForContentIfNeeded()
    }

    /// Which of the requested words never made it into the passage.
    static func wordsMissing(from text: String, words: [String]) -> [String] {
        words.filter { ReadingHighlight.ranges(in: text, words: [$0]).isEmpty }
    }

    private func hideReadingChat() {
        sessionView.readingChatView.isHidden = true
        sessionView.readingModeControl.isHidden = true
    }

    private func readingModeChanged(_ segment: Int) {
        guard let mode = ReadingChatView.Mode(rawValue: segment) else { return }
        sessionView.readingChatView.setGlobalMode(mode)
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

    private func presentPassageMenu(from sender: NSButton?) {
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
        if let sender {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
        } else if let contentView = window?.contentView {
            menu.popUp(positioning: nil, at: NSPoint(x: 20, y: contentView.bounds.height - 20), in: contentView)
        }
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

    private func leaveReading() {
        weaveRequest?.cancel()
        weaveRequest = nil
        isReadingMode = false
        if recordsToReview.isEmpty || currentIndex >= recordsToReview.count {
            showHome()
        } else {
            show(.session)
            loadCurrentCard()
        }
    }

    private func adjustWindowHeightForContentIfNeeded() {
        guard let window else { return }
        let resultText = sessionView.resultLabel.stringValue
        guard !resultText.isEmpty else { return }
        // Expand height when the answer is long enough to need the room.
        let targetHeight: CGFloat = (resultText.count > 150 || resultText.contains("\n\n"))
            ? ReviewLayout.expandedHeight
            : ReviewLayout.compactHeight
        let currentFrame = window.frame
        guard currentFrame.height < targetHeight else { return }
        let heightDiff = targetHeight - currentFrame.height
        window.setFrame(
            NSRect(
                x: currentFrame.origin.x,
                y: max(0, currentFrame.origin.y - heightDiff),
                width: currentFrame.width,
                height: targetHeight
            ),
            display: true,
            animate: true
        )
    }

    // MARK: - Speech

    private func currentSourceSpeechIdentity() -> SpeechIdentity? {
        if screen == .newWords { return pendingNewWordSpeech }
        guard !recordsToReview.isEmpty, currentIndex < recordsToReview.count else { return nil }
        let record = recordsToReview[currentIndex]
        let speechCfg = config ?? AppConfig.load()
        return SpeechIdentity(
            kind: .source,
            text: displayTerm(of: record),
            model: SpeechModelResolver.model(for: record.sourceLanguage, config: speechCfg),
            recordID: record.id
        )
    }

    private func makeSymbolImage(name: String, description: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
    }

    private func updateSpeakButtonUI() {
        if isReadingMode {
            updateReadingSpeechUI()
            return
        }
        let normalButton = screen == .newWords ? newWordsView.speakButton : sessionView.speakSourceButton
        let slowButton = screen == .newWords ? newWordsView.speakSlowButton : sessionView.speakSlowSourceButton
        guard let identity = currentSourceSpeechIdentity() else {
            normalButton.isEnabled = false
            slowButton.isEnabled = false
            return
        }
        let action = speechState.action(for: identity)
        let isNormalPlaying = activeSpeechIdentity == identity && activeSpeechRate == 1.0
        let isSlowPlaying = activeSpeechIdentity == identity && activeSpeechRate < 1.0

        normalButton.image = isNormalPlaying
            ? makeSymbolImage(name: Self.symbol(for: action, playing: "speaker.wave.2"), description: "Speak source")
            : makeSymbolImage(name: "speaker.wave.2", description: "Speak source (4 / 1.0x)")
        slowButton.image = isSlowPlaying
            ? makeSymbolImage(name: Self.symbol(for: action, playing: "tortoise"), description: "Speak source slowly")
            : makeSymbolImage(name: "tortoise", description: "Speak source slowly (5)")
        normalButton.isEnabled = true
        slowButton.isEnabled = true
    }

    private static func symbol(for action: SpeechButtonAction, playing idle: String) -> String {
        switch action {
        case .pause: return "pause.fill"
        case .resume: return "play.fill"
        case .loading: return "hourglass"
        case .play: return idle
        }
    }

    /// In reading mode the speak buttons live in the bubbles, so the same state drives them.
    private func updateReadingSpeechUI() {
        let slowRate = config?.speechSlowRate ?? AppConfig.default.speechSlowRate
        let isSlow = abs(activeSpeechRate - slowRate) < 0.01
        let action = activeSpeechIdentity.map { speechState.action(for: $0) } ?? .play
        sessionView.readingChatView.updateSpeech(line: activeSpeechIdentity?.text, isSlow: isSlow, action: action)
    }

    private func speakCurrentSource() { handleSpeechPlay(speed: 1.0) }

    private func speakCurrentSourceSlow() {
        handleSpeechPlay(speed: config?.speechSlowRate ?? 0.4)
    }

    private func speakNewWord(slow: Bool) {
        guard let identity = pendingNewWordSpeech else { return }
        handleSpeechPlay(speed: slow ? (config?.speechSlowRate ?? 0.4) : 1.0, identity: identity)
    }

    /// Opens the current card in the translate panel without closing this review window.
    private func openTranslatePopup() {
        stopAudio()
        guard currentIndex < recordsToReview.count else { return }
        onOpenTranslate?(recordsToReview[currentIndex])
    }

    private func handleSpeechPlay(speed: Float, identity providedIdentity: SpeechIdentity? = nil) {
        guard let identity = providedIdentity ?? currentSourceSpeechIdentity() else { return }
        // Clicking the same speed while active follows the pause/resume/play cycle.
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
            stopAudio()
            playSpeech(identity: identity, speed: speed)
        }
    }

    private func playSpeech(identity: SpeechIdentity, speed: Float) {
        activeSpeechIdentity = identity
        activeSpeechRate = speed

        if let recordID = identity.recordID,
           let data = try? store.audioData(for: recordID, kind: .source),
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

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer else { return }
        stopAudio()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audioPlayer else { return }
        stopAudio()
    }

    func windowWillClose(_ notification: Notification) {
        stopAudio()
        removeKeyEventMonitor()
        sessionTimer?.invalidate()
        sessionTimer = nil
        onWindowClosed?()
    }
}

// MARK: - Screen delegates

extension ReviewWindowController: ReviewHomeViewDelegate {
    func homeViewDidStart(_ view: ReviewHomeView) { startSession() }
    func homeViewDidRequestNewWords(_ view: ReviewHomeView) { showNewWords() }
    func homeViewDidRequestReading(_ view: ReviewHomeView) { showReadingPassage() }

    func homeView(_ view: ReviewHomeView, didRequestPassagesFrom sender: NSButton) {
        presentPassageMenu(from: sender)
    }

    func homeViewDidRequestPracticeAll(_ view: ReviewHomeView, shuffled: Bool) {
        startPracticeReview(shuffled: shuffled)
    }

    func homeViewDidChangeOptions(_ view: ReviewHomeView) {
        sessionLimit = view.sessionLimit
        requestedKind = view.requestedKind
        selectedBucket = view.selectedBucket
        persistOptions()
    }

    private func persistOptions() {
        var learning = (config ?? AppConfig.load()).learning
        learning.reviewSessionLimit = sessionLimit
        learning.reviewQuestionKind = requestedKind?.label
        learning.reviewFilter = selectedBucket?.rawValue
        learning.newWordsLevel = newWordsLevel?.rawValue
        config?.learning = learning
        onLearningSettingsChanged?(learning)
    }
}

extension ReviewWindowController: ReviewSessionViewDelegate {
    func sessionViewDidTapHome(_ view: ReviewSessionView) { goHome() }
    func sessionViewDidTapUndo(_ view: ReviewSessionView) { undoLastGrade() }
    func sessionViewDidTapHide(_ view: ReviewSessionView) { hideCurrentCard() }
    func sessionViewDidTapReveal(_ view: ReviewSessionView) { revealAnswer() }
    func sessionViewDidTapBack(_ view: ReviewSessionView) { leaveReading() }
    func sessionView(_ view: ReviewSessionView, didGrade grade: SRSGrade) { applyGrade(grade) }
    func sessionView(_ view: ReviewSessionView, didChooseAt index: Int) { chooseContrast(index: index) }
    func sessionViewDidSubmitAnswer(_ view: ReviewSessionView) { submitTypedAnswer() }

    func sessionViewDidToggleContext(_ view: ReviewSessionView) {
        isContextExpanded.toggle()
        updateContextDisplay()
    }

    func sessionView(_ view: ReviewSessionView, didRequestSpeechSlow slow: Bool) {
        slow ? speakCurrentSourceSlow() : speakCurrentSource()
    }

    func sessionViewDidRequestTranslate(_ view: ReviewSessionView) { openTranslatePopup() }

    func sessionView(_ view: ReviewSessionView, didChangeReadingMode mode: Int) {
        readingModeChanged(mode)
    }
}

extension ReviewWindowController: ReviewSummaryViewDelegate {
    func summaryViewDidRequestRedrill(_ view: ReviewSummaryView) { redrillMissed() }
    func summaryViewDidRequestContinue(_ view: ReviewSummaryView) { startSession() }
    func summaryViewDidRequestReading(_ view: ReviewSummaryView) { showReadingPassage() }
    func summaryViewDidRequestHome(_ view: ReviewSummaryView) { goHome() }
}

extension ReviewWindowController: NewWordsViewDelegate {
    func newWordsView(_ view: NewWordsView, didDecide decision: NewWordsView.Decision) {
        decideNewWord(decision)
    }

    func newWordsView(_ view: NewWordsView, didRequestSpeechSlow slow: Bool) {
        speakNewWord(slow: slow)
    }

    func newWordsView(_ view: NewWordsView, didSelect level: VocabDiscovery.Level?) {
        newWordsLevel = level
        persistOptions()
        rebuildNewWordsQueue()
    }

    func newWordsViewDidRequestHome(_ view: NewWordsView) { goHome() }
}
