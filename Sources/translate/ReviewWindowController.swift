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
    private enum Screen { case home, session, summary, newWords, passages }

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
    /// Called with a reading line to explain in the translate panel's Learn mode.
    var onLearnSentence: ((String) -> Void)?
    /// Called with a reading line or selection to translate in the popover's translate mode.
    var onTranslateSentence: ((String) -> Void)?

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
    /// Scenario behind the open passage, so Regenerate asks for the same setting again.
    private var currentScenario: String?
    /// Which language the reading passage opens in. Picked while the model is still writing it,
    /// and nil until the learner picks: a passage that arrives first waits in `pendingReading`.
    private var preferredReadingMode: ReadingChatView.Mode?
    private var isAwaitingWeave = false
    private var pendingReading: (text: String, words: [String], entry: (key: String, passage: WeavePassage)?)?
    /// The passage on the reading screen, with the key it is filed under, so a regenerated title
    /// can be written back to the same file.
    private var currentPassage: (key: String, passage: WeavePassage)?
    private var titleRequest: RequestHandle?
    private var readingReturnScreen: Screen = .home
    private let passagesView = PassagesView()

    // New words
    private var newWordsQueue: [VocabPackEntry] = []
    private var newWordsIndex = 0
    private var newWordsFilter: VocabDiscovery.Filter = .all
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
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 620, height: 640)
        window.isReleasedWhenClosed = false
        window.title = "Study"
        window.setFrameAutosaveName("ReviewSRSWindowTall2")

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
        newWordsFilter = learning.newWordsLevel.flatMap(VocabDiscovery.Filter.init(rawValue:)) ?? .all
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
        passagesView.delegate = self
        sessionView.readingChatView.onSpeak = { [weak self] line, isSlow in self?.speakReadingLine(line, slow: isSlow) }
        sessionView.readingChatView.onWord = { [weak self] word in self?.openTranslateForWord(word) }
        sessionView.readingChatView.onLearn = { [weak self] line in
            guard let self else { return }
            self.stopAudio()
            self.onLearnSentence?(line)
        }
        sessionView.readingChatView.onTranslate = { [weak self] line in
            guard let self else { return }
            self.stopAudio()
            self.onTranslateSentence?(line)
        }
        // Selecting the text hands it to the field editor, which drops every attribute unless the
        // field says attributes are its own. Without this the reading underlines vanish on click.
        sessionView.resultLabel.allowsEditingTextAttributes = true

        for screen in [homeView, sessionView, summaryView, newWordsView, passagesView] as [NSView] {
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

        // Every screen lives inside a scroll view, so the content's fitting size is almost zero and
        // AppKit's constraint-based layout happily shrinks the window to the titlebar. `minSize`
        // only guards a user drag, not that path, so the floor has to be a constraint too, and it
        // is set to the window's designed size: the mode grid alone needs about 590 points.
        NSLayoutConstraint.activate([
            cardView.widthAnchor.constraint(greaterThanOrEqualToConstant: 588),
            cardView.heightAnchor.constraint(greaterThanOrEqualToConstant: 608),
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
        passagesView.isHidden = screen != .passages
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

    private func showPassages() {
        isReadingMode = false
        stopAudio()
        passagesView.reload(entries: WeaveCache.entries())
        show(.passages)
    }

    func showReview() {
        installKeyEventMonitorIfNeeded()
        // Accessory app: without this the window opens behind an inactive app, so the first click
        // on any control only activates and never reaches the button.
        NSApp.activate(ignoringOtherApps: true)
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
        if ReviewPlanner.writesSchedule(isPractice: isPracticeMode) {
            do {
                try store.updateSRS(recordID: record.id, grade: grade)
            } catch {
                NSLog("[NTranslate] Failed to update SRS: \(error.localizedDescription)")
            }
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
        if ReviewPlanner.writesSchedule(isPractice: isPracticeMode) {
            do {
                try store.restoreSRS(from: snapshot.record)
            } catch {
                NSLog("[NTranslate] Failed to undo grade: \(error.localizedDescription)")
                return
            }
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
        let alert = NSAlert()
        alert.messageText = "Remove this card from the deck?"
        alert.informativeText = "The translation stays in History. You can add it back with the star button there."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if let window = window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.commitHideCard(record)
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            commitHideCard(record)
        }
    }

    private func commitHideCard(_ record: TranslationRecord) {
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

        let encounter = LearnCard.Encounter.split(record.sourceText)
        sessionView.termLabel.stringValue = encounter.term
        currentContext = encounter.context
        isContextExpanded = false
        updateContextDisplay()

        sessionView.sourceContainer.isHidden = false
        // The reading screen can leave the term hidden; a card always shows its question.
        sessionView.termLabel.isHidden = false
        setSourceGiveaways(hidden: false)
        sessionView.titleRefreshButton.isHidden = true
        sessionView.resultLabel.stringValue = sessionView.learnBadgeView.apply(to: record.resultText, live: true)
        sessionView.resultLabel.isHidden = true
        hideReadingChat()
        sessionView.revealButton.isHidden = false
        sessionView.backButton.isHidden = true
        sessionView.markDoneButton.isHidden = true
        sessionView.regenerateButton.isHidden = true
        sessionView.gradeStack.isHidden = true
        sessionView.autoGradeStack.isHidden = true
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
    /// read as a bug. A real Start Review grade still schedules with `ReviewPlanner.randomFuzz()`.
    /// Practice captions stay empty so the buttons do not promise a due date.
    private func gradePreview(_ grade: SRSGrade, for record: TranslationRecord) -> String {
        let next = ReviewPlanner.nextSchedule(
            grade: grade,
            interval: record.interval,
            ease: record.ease,
            fuzz: 1.0
        )
        return ReviewPlanner.gradeIntervalCaption(
            isPractice: isPracticeMode,
            scheduled: Self.intervalText(next.interval)
        )
    }

    private func updateGradeIntervals(for record: TranslationRecord) {
        sessionView.setGradeIntervals(
            again: gradePreview(.again, for: record),
            hard: gradePreview(.hard, for: record),
            easy: gradePreview(.easy, for: record)
        )
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
        let encounter = LearnCard.Encounter.split(record.sourceText).context
        if card.preferredCloze(encounterSentence: encounter) != nil { kinds.insert(.cloze) }
        if card.collocationQuiz != nil { kinds.insert(.collocation) }
        if card.familyQuiz != nil { kinds.insert(.family) }
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
        let encounter = LearnCard.Encounter.split(record.sourceText).context
        switch resolved.kind {
        case .flip:
            return (.none, .flip, resolved.note)
        case .cloze:
            guard let cloze = card.preferredCloze(encounterSentence: encounter) else { return (.none, .flip, resolved.note) }
            return (.typed(cloze, kind: .cloze), .cloze, resolved.note)
        case .collocation:
            guard let quiz = card.collocationQuiz else { return (.none, .flip, resolved.note) }
            return (.typed(quiz, kind: .collocation), .collocation, resolved.note)
        case .family:
            guard let quiz = card.familyQuiz else { return (.none, .flip, resolved.note) }
            return (.typed(quiz, kind: .family), .family, resolved.note)
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
            sessionView.termLabel.stringValue = question.hintedPrompt
            sessionView.termLabel.font = .systemFont(ofSize: 17, weight: .regular)
            sessionView.answerField.isHidden = false
            sessionView.answerField.placeholderString = {
                switch kind {
                case .cloze: return "Type the missing word, then press Return"
                case .collocation: return "Type the phrase, then press Return"
                case .family: return "Type the related form, then press Return"
                default: return "Type the word, then press Return"
                }
            }()
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
        // A self-graded card already picked; `showAutoGrade` put the Continue button up instead.
        sessionView.gradeStack.isHidden = pendingAutoGrade != nil
        adjustWindowHeightForContentIfNeeded()
    }

    /// The stored source text can carry an appended context sentence; only the term is the answer.
    private func displayTerm(of record: TranslationRecord) -> String {
        return LearnCard.Encounter.split(record.sourceText).term
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
        let interval = currentIndex < recordsToReview.count
            ? gradePreview(grade, for: recordsToReview[currentIndex])
            : ""
        sessionView.showAutoGrade(grade, name: name, interval: interval)
    }

    private func submitTypedAnswer() {
        guard case let .typed(question, kind) = activeQuestion, !isAnswerRevealed else { return }
        let typed = sessionView.answerField.stringValue
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let correct = question.matches(typed)
        let nearMiss = !correct && ReviewPlanner.isNearMiss(typed: typed, answer: question.answer)
        // Seeing the wrong attempt next to the answer is where the mistake is actually learnt.
        let typedBack = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let note: String
        if nearMiss {
            note = "Just a typo: \(question.answer) (you typed \"\(typedBack)\")"
        } else if correct {
            note = "Answer: \(question.answer)"
        } else {
            note = "You typed \"\(typedBack)\". Answer: \(question.answer)"
        }
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

    private func updateNewWordsLevels() {
        let progress = VocabProgressStore.shared.progress
        let entries = VocabPack.shared.allEntries()
        let inStore = Set(store.records.filter { $0.isSaved }.map { VocabPack.normalize(displayTerm(of: $0)) })
        newWordsView.setLevels(
            VocabDiscovery.remainingByLevel(entries: entries, progress: progress, inStore: inStore),
            knownCount: progress.known.count,
            selected: newWordsFilter
        )
    }

    private func rebuildNewWordsQueue() {
        VocabProgressStore.shared.load()
        let progress = VocabProgressStore.shared.progress
        let entries = VocabPack.shared.allEntries()
        let inStore = Set(store.records.filter { $0.isSaved }.map { VocabPack.normalize(displayTerm(of: $0)) })
        newWordsView.setLevels(
            VocabDiscovery.remainingByLevel(entries: entries, progress: progress, inStore: inStore),
            knownCount: progress.known.count,
            selected: newWordsFilter
        )
        if newWordsFilter == .known {
            newWordsQueue = VocabDiscovery.knownQueue(entries: entries, progress: progress)
        } else {
            let level: VocabDiscovery.Level?
            switch newWordsFilter {
            case .level(let lvl): level = lvl
            case .all, .known: level = nil
            }
            newWordsQueue = VocabDiscovery.queue(
                entries: entries,
                level: level,
                progress: progress,
                inStore: inStore
            )
        }
        newWordsIndex = 0
        showCurrentNewWord()
    }

    private func showCurrentNewWord() {
        guard newWordsIndex < newWordsQueue.count else {
            let emptyMessage: String
            if VocabPack.shared.isEmpty {
                emptyMessage = "Không tìm thấy kho từ vựng. Kiểm tra tệp vocab-en-vi.json trong Application Support."
            } else if newWordsFilter == .known {
                emptyMessage = "Chưa có từ nào trong danh sách Đã biết."
            } else {
                emptyMessage = "Hết từ ở mức này. Chọn cấp độ khác ở góc trên bên trái."
            }
            newWordsView.showEmpty(message: emptyMessage)
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
            newWordsIndex += 1
        case .unmarkKnown:
            VocabProgressStore.shared.unmarkKnown(word: entry.w)
            newWordsQueue.remove(at: newWordsIndex)
            updateNewWordsLevels()
            showCurrentNewWord()
            return
        case .skip:
            VocabProgressStore.shared.record(.skipped, word: entry.w)
            // A skipped word belongs at the back of the queue, not gone: move it there now so the
            // rest of this sitting keeps offering words never seen before.
            newWordsQueue.append(newWordsQueue.remove(at: newWordsIndex))
            updateNewWordsLevels()
            showCurrentNewWord()
            return
        case .next:
            newWordsIndex += 1
        case .learn:
            addNewWordToDeck(entry)
            if newWordsFilter == .known {
                VocabProgressStore.shared.unmarkKnown(word: entry.w)
                newWordsQueue.remove(at: newWordsIndex)
                updateNewWordsLevels()
                showCurrentNewWord()
                return
            }
            newWordsIndex += 1
        }
        updateNewWordsLevels()
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
            VocabProgressStore.shared.unmarkKnown(word: entry.w)
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
        if let delta = TextZoom.delta(for: event) {
            if TextZoom.nudge(delta) { sessionView.applyTextZoom() }
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
        case .summary, .passages:
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
            // Space on an empty field still means "show answer": a typed answer never starts with
            // a space, so the key is free until the user has typed something.
            if chars == " ", editor.string.isEmpty {
                handleSpaceKey()
                return nil
            }
            return event
        }
        if isReadingMode {
            if isAwaitingWeave, let index = ["1", "2"].firstIndex(of: chars) {
                sessionView(sessionView, didChooseAt: index)
                return nil
            }
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

    /// A fresh random handful drawn from every saved word, not just the ones due in this session.
    private func randomStudyWords() -> [String] {
        let saved = store.records.filter { $0.isSaved && $0.mode == .learn }
        return Translator.weaveWords(saved.map { displayTerm(of: $0) }.shuffled())
    }

    private func showReadingPassage() {
        readingReturnScreen = .home
        currentScenario = nil
        didRetryWeave = false
        isAwaitingWeave = false
        preferredReadingMode = nil
        pendingReading = nil
        requestReadingPassage()
    }

    private func requestReadingPassage(
        words explicitWords: [String]? = nil,
        force: Bool = false,
        scenario: String? = nil
    ) {
        let words = explicitWords ?? readingWords()
        guard !words.isEmpty || !(scenario ?? "").isEmpty else { return }
        // The prompt actually in use decides the passage, so it decides the cache key too, and the
        // scenario is part of the prompt the model really sees.
        let key = WeaveCache.cacheKey(
            words: words,
            promptVersion: AppConfig.weavePromptVersion,
            prompt: (config ?? AppConfig.load()).weavePrompt + (scenario.map { "\n" + $0 } ?? "")
        )
        if !force, let cached = WeaveCache.load(key: key) {
            presentReading(cached.text, words: words, entry: (key, cached))
            return
        }
        guard let translator else {
            presentReading("No translator is configured, so the passage cannot be generated.", words: words)
            return
        }
        isAwaitingWeave = true
        let progress = words.isEmpty
            ? "Generating a dialogue for your scenario…"
            : "Generating a passage from \(words.count) words…"
        presentReading(progress, words: words)
        // The words come from these records, so their own language pair is the right one to ask
        // for. `config.sourceLang` is often "Auto detect", which means nothing to the model here.
        let first = readingPool().first
        let sourceLang = first?.sourceLanguage ?? "English"
        let targetLang = first?.targetLanguage ?? config?.targetLang ?? "Vietnamese"
        weaveRequest?.cancel()
        weaveRequest = translator.weave(
            words,
            sourceLang: sourceLang,
            targetLang: targetLang,
            scenario: scenario
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isReadingMode else { return }
                switch result {
                case let .success(text):
                    // A model that quietly drops a word leaves the learner short of practice, so
                    // one missed word buys one more attempt before the passage is kept.
                    let missing = Self.wordsMissing(from: text, words: words)
                    if !missing.isEmpty, !self.didRetryWeave {
                        self.didRetryWeave = true
                        self.requestReadingPassage(words: explicitWords, force: force, scenario: scenario)
                        return
                    }
                    let passage = WeavePassage(
                        words: words,
                        text: text,
                        promptVersion: AppConfig.weavePromptVersion,
                        generatedAt: Date(),
                        scenario: scenario?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? scenario : nil
                    )
                    WeaveCache.store(passage, key: key)
                    self.deliverReading(text, words: words, entry: (key, passage))
                case let .failure(error):
                    self.deliverReading("Could not generate the passage: \(error.localizedDescription)", words: words)
                }
            }
        }
    }

    /// A finished passage still waits for the language choice, so the screen never jumps ahead of
    /// the learner just because the model was quick.
    private func deliverReading(
        _ text: String,
        words: [String],
        entry: (key: String, passage: WeavePassage)? = nil
    ) {
        guard preferredReadingMode != nil else {
            pendingReading = (text, words, entry)
            sessionView.hintLabel.stringValue = "Passage is ready. Pick a language to open it."
            return
        }
        isAwaitingWeave = false
        pendingReading = nil
        presentReading(text, words: words, entry: entry)
    }

    private func presentReading(
        _ text: String,
        words: [String],
        entry: (key: String, passage: WeavePassage)? = nil,
        returnScreen: Screen? = nil
    ) {
        if let returnScreen { readingReturnScreen = returnScreen }
        isReadingMode = true
        currentPassage = entry
        titleRequest?.cancel()
        titleRequest = nil
        stopAudio()
        show(.session)
        if let stored = entry?.passage.scenario { currentScenario = stored }
        sessionView.setReadingPills(count: words.count, words: words, scenario: currentScenario)
        sessionView.updateProgress(correct: 0, wrong: 0, remaining: 0, elapsed: 0, practice: false)
        applyReadingTitle()
        sessionView.sourceContainer.isHidden = false
        setSourceGiveaways(hidden: true)
        sessionView.answerField.isHidden = true
        sessionView.choiceStack.isHidden = true
        sessionView.feedbackLabel.isHidden = true
        if let dialogue = ReadingDialogue.parse(text) {
            sessionView.readingChatView.show(dialogue, words: words)
            sessionView.readingChatView.setGlobalMode(preferredReadingMode ?? .both)
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
        sessionView.autoGradeStack.isHidden = true
        sessionView.hintLabel.isHidden = true
        sessionView.undoButton.isEnabled = false
        sessionView.hideButton.isEnabled = false
        sessionView.backButton.isHidden = false
        sessionView.markDoneButton.isHidden = entry == nil
        sessionView.regenerateButton.isHidden = entry == nil
        sessionView.regenerateButton.isEnabled = !isAwaitingWeave
        sessionView.setPassageDone(entry?.passage.isDone == true)
        // The wait is dead time otherwise, so it buys the one setting the passage needs. The
        // passage has no title yet, so the header would only say "Untitled" over the question.
        if isAwaitingWeave, preferredReadingMode == nil {
            sessionView.termLabel.isHidden = true
            sessionView.titleRefreshButton.isHidden = true
            sessionView.firstChoiceButton.title = "  English first (EN to VI)"
            sessionView.secondChoiceButton.title = "  Vietnamese first (VI to EN)"
            sessionView.choiceStack.isHidden = false
            sessionView.hintLabel.stringValue = readingModeHint()
            sessionView.hintLabel.isHidden = false
        }
        adjustWindowHeightForContentIfNeeded()
    }

    /// Names the passage on the reading screen. Without a title the header says so and offers the
    /// button that asks the model for one.
    private func applyReadingTitle() {
        sessionView.termLabel.isHidden = false
        sessionView.termLabel.font = .systemFont(ofSize: 20, weight: .bold)
        let headline = currentPassage.map { Self.passageHeadline($0.passage) } ?? ""
        sessionView.termLabel.stringValue = headline.isEmpty ? "Untitled passage" : headline
        // Only a passage that is actually on disk can keep the title it gets back.
        sessionView.titleRefreshButton.isHidden = currentPassage == nil
        sessionView.titleRefreshButton.isEnabled = true
        sessionView.titleRefreshButton.toolTip = headline.isEmpty
            ? "Ask the model for a title"
            : "Generate a new title"
    }

    /// Throws the open passage away and asks for a new one from the same words. The cache key is
    /// built from the words and the prompt, so the only way to get different text is to skip the
    /// cache on the way in and overwrite the file on the way out.
    private func regeneratePassage() {
        guard translator != nil, !isAwaitingWeave else { return }
        didRetryWeave = false
        sessionView.regenerateButton.isEnabled = false
        let words = currentPassage?.passage.words ?? readingWords()
        requestReadingPassage(words: words, force: true, scenario: currentScenario)
    }

    /// Asks the model for a short title and files it with the passage, so the list and this header
    /// both stop saying "Untitled".
    private func regeneratePassageTitle() {
        guard let entry = currentPassage, let translator else { return }
        sessionView.titleRefreshButton.isEnabled = false
        sessionView.termLabel.stringValue = "Naming the passage…"
        let language = readingPool().first?.targetLanguage ?? config?.targetLang ?? "Vietnamese"
        titleRequest?.cancel()
        titleRequest = translator.ask(
            "Give this conversation a title in \(language). Hard limit: 8 words or fewer, ideally 4 to 6. Reply with the title only, no quotes and no punctuation at the end.",
            sourceText: entry.passage.text,
            translatedText: "",
            sourceLang: readingPool().first?.sourceLanguage ?? "English",
            targetLang: language
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.isReadingMode, self.currentPassage?.key == entry.key else { return }
                switch result {
                case let .success(text):
                    let title = Self.cleanTitle(text)
                    guard !title.isEmpty else { self.applyReadingTitle(); return }
                    var passage = entry.passage
                    passage.title = title
                    WeaveCache.store(passage, key: entry.key)
                    self.currentPassage = (entry.key, passage)
                case .failure:
                    break
                }
                self.applyReadingTitle()
            }
        }
    }

    /// Models like to answer with quotes, a trailing period, or a "Title:" prefix.
    static func cleanTitle(_ raw: String) -> String {
        var title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        title = title.components(separatedBy: "\n").first ?? title
        if title.lowercased().hasPrefix("title:") {
            title = String(title.dropFirst("title:".count))
        }
        title = title.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'“”‘’.,;:"))
        // The prompt asks for at most 8 words; a model that ignores it gets trimmed here.
        let words = title.split(separator: " ")
        if words.count > 8 { title = words.prefix(8).joined(separator: " ") }
        if title.count > 80 { title = String(title.prefix(79)) + "…" }
        return title
    }

    /// Which of the requested words never made it into the passage.
    static func wordsMissing(from text: String, words: [String]) -> [String] {
        words.filter { ReadingHighlight.ranges(in: text, words: [$0]).isEmpty }
    }

    /// Flips the Done flag on the open passage and writes it back to its cache file.
    private func togglePassageDone() {
        guard let entry = currentPassage else { return }
        var passage = entry.passage
        let newStatus = !(passage.isDone ?? false)
        passage.isDone = newStatus
        WeaveCache.store(passage, key: entry.key)
        currentPassage = (entry.key, passage)
        sessionView.setPassageDone(newStatus)
        if newStatus {
            showPassages()
        }
    }

    private func hideReadingChat() {
        sessionView.readingChatView.isHidden = true
        sessionView.readingModeControl.isHidden = true
    }

    private func readingModeHint() -> String {
        switch preferredReadingMode {
        case .source: return "Passage will open in English. Press 1 or 2 to change."
        case .translation: return "Passage will open in Vietnamese. Press 1 or 2 to change."
        default: return "Pick how the passage should open while it is being written."
        }
    }

    private func readingModeChanged(_ segment: Int) {
        guard let mode = ReadingChatView.Mode(rawValue: segment) else { return }
        preferredReadingMode = mode
        sessionView.readingChatView.setGlobalMode(mode)
    }

    /// One line of the conversation, spoken in the language it is written in. These lines are not
    /// cards, so their audio is cached by text under the history folder instead of on a record.
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
        showPassages()
    }

    /// The passage's own title: the one generated for it, else the topic line the model wrote.
    /// Empty when the passage predates both, which is what puts the regenerate button on screen.
    static func passageHeadline(_ passage: WeavePassage) -> String {
        if let title = passage.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let topic = ReadingDialogue.parse(passage.text)?.topic ?? ""
        return topic.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One row in the saved list: headline plus how many words and when it was made.
    static func passageTitle(_ passage: WeavePassage) -> String {
        var title = passageHeadline(passage)
        if title.isEmpty { title = passage.words.joined(separator: ", ") }
        if title.count > 60 { title = String(title.prefix(59)) + "…" }
        let date = DateFormatter.localizedString(from: passage.generatedAt, dateStyle: .short, timeStyle: .none)
        return "\(title)  ·  \(passage.words.count) words  ·  \(date)"
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
        if readingReturnScreen == .passages {
            showPassages()
        } else {
            goHome()
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
        if identity.recordID == nil,
           let data = WeaveAudioCache.load(text: identity.text, model: identity.model),
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
                } else {
                    WeaveAudioCache.store(data, text: identity.text, model: identity.model)
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
        let volume = config?.speechVolume ?? AppConfig.default.speechVolume
        guard let player = try? AVAudioPlayer(data: SpeechGain.boosted(data, volume: volume)) else {
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
        learning.newWordsLevel = newWordsFilter.rawValue
        config?.learning = learning
        onLearningSettingsChanged?(learning)
    }
}

extension ReviewWindowController: ReviewSessionViewDelegate {
    func sessionViewDidTapHome(_ view: ReviewSessionView) { goHome() }
    func sessionViewDidTapUndo(_ view: ReviewSessionView) { undoLastGrade() }
    func sessionViewDidTapHide(_ view: ReviewSessionView) { hideCurrentCard() }
    func sessionViewDidTapReveal(_ view: ReviewSessionView) { revealAnswer() }
    func sessionViewDidRequestPassageTitle(_ view: ReviewSessionView) { regeneratePassageTitle() }
    func sessionViewDidRequestPassageRegenerate(_ view: ReviewSessionView) { regeneratePassage() }

    func sessionViewDidTapBack(_ view: ReviewSessionView) { leaveReading() }
    func sessionViewDidTogglePassageDone(_ view: ReviewSessionView) { togglePassageDone() }
    func sessionView(_ view: ReviewSessionView, didGrade grade: SRSGrade) { applyGrade(grade) }
    func sessionView(_ view: ReviewSessionView, didChooseAt index: Int) {
        // While the passage is being written the same two buttons pick the language it opens in.
        guard !isAwaitingWeave else {
            preferredReadingMode = index == 0 ? .source : .translation
            if let pending = pendingReading {
                deliverReading(pending.text, words: pending.words, entry: pending.entry)
            } else {
                sessionView.hintLabel.stringValue = readingModeHint()
            }
            return
        }
        chooseContrast(index: index)
    }
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

    func newWordsView(_ view: NewWordsView, didSelect filter: VocabDiscovery.Filter) {
        newWordsFilter = filter
        persistOptions()
        rebuildNewWordsQueue()
    }

    func newWordsViewDidRequestHome(_ view: NewWordsView) { goHome() }
}

extension ReviewWindowController: PassagesViewDelegate {
    func passagesViewDidTapBack(_ view: PassagesView) {
        goHome()
    }

    func passagesView(_ view: PassagesView, didSelectPassage passage: WeavePassage, key: String) {
        stopAudio()
        presentReading(passage.text, words: passage.words, entry: (key, passage), returnScreen: .passages)
    }

    func passagesView(_ view: PassagesView, didToggleDone key: String) {
        guard var passage = WeaveCache.load(key: key) else { return }
        passage.isDone = !(passage.isDone ?? false)
        WeaveCache.store(passage, key: key)
        passagesView.reload(entries: WeaveCache.entries())
    }

    func passagesView(_ view: PassagesView, didDeletePassage key: String) {
        WeaveCache.delete(key: key)
        passagesView.reload(entries: WeaveCache.entries())
    }

    func passagesViewDidRequestCreate(_ view: PassagesView) {
        guard let window else { return }
        CustomDialogueDialog.present(
            over: window,
            randomWords: { [weak self] in self?.randomStudyWords() ?? [] }
        ) { [weak self] words, scenario in
            guard let self, !words.isEmpty || scenario != nil else { return }
            self.readingReturnScreen = .passages
            self.didRetryWeave = false
            self.isAwaitingWeave = false
            self.preferredReadingMode = nil
            self.pendingReading = nil
            self.currentScenario = scenario
            self.requestReadingPassage(words: words, force: false, scenario: scenario)
        }
    }
}
