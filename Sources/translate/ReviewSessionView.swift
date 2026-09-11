// The card itself: progress chrome at the top, the question in the middle, grading at the bottom.
// The reading passage borrows the same body, so this view covers every screen that is not home,
// summary or new-word discovery.
import AppKit

@MainActor
protocol ReviewSessionViewDelegate: AnyObject {
    func sessionViewDidTapHome(_ view: ReviewSessionView)
    func sessionViewDidTapUndo(_ view: ReviewSessionView)
    func sessionViewDidTapHide(_ view: ReviewSessionView)
    func sessionViewDidTapReveal(_ view: ReviewSessionView)
    func sessionViewDidTapBack(_ view: ReviewSessionView)
    func sessionViewDidTogglePassageDone(_ view: ReviewSessionView)
    func sessionViewDidRequestPassageTitle(_ view: ReviewSessionView)
    func sessionViewDidRequestPassageRegenerate(_ view: ReviewSessionView)
    func sessionView(_ view: ReviewSessionView, didGrade grade: SRSGrade)
    func sessionView(_ view: ReviewSessionView, didChooseAt index: Int)
    func sessionViewDidSubmitAnswer(_ view: ReviewSessionView)
    func sessionViewDidToggleContext(_ view: ReviewSessionView)
    func sessionView(_ view: ReviewSessionView, didRequestSpeechSlow slow: Bool)
    func sessionViewDidRequestTranslate(_ view: ReviewSessionView)
    func sessionView(_ view: ReviewSessionView, didChangeReadingMode mode: Int)
}

@MainActor
final class ReviewSessionView: NSView {
    weak var delegate: ReviewSessionViewDelegate?

    // Top bar
    let homeButton = NSButton()
    let undoButton = NSButton()
    let hideButton = NSButton()
    private let progressBar = SessionProgressBar()
    private let countsLabel = NSTextField(labelWithString: "")
    let pillRow = NSStackView()
    private let wordsDetailLabel = NSTextField(labelWithString: "")
    private let pillContainer = NSStackView()
    /// CEFR / frequency / register pulled out of the card's "Mức dùng:" line.
    let learnBadgeView = LearnBadgeView()

    // Card body
    /// Unscaled sizes of the raw / translated text, so Cmd+Plus zoom stays absolute.
    static let termBaseSize: CGFloat = 24
    static let contextBaseSize: CGFloat = 13
    static let resultBaseSize: CGFloat = 14

    let termLabel = NSTextField(wrappingLabelWithString: "")
    /// Only visible on the reading screen: asks the model to name the passage.
    let titleRefreshButton = NSButton()
    let contextLabel = NSTextField(wrappingLabelWithString: "")
    let readMoreButton = NSButton()
    let speakSourceButton = NSButton()
    let speakSlowSourceButton = NSButton()
    let openTranslateButton = NSButton()
    let speakShortcutLabel = NSTextField(labelWithString: "(4)")
    let speakSlowShortcutLabel = NSTextField(labelWithString: "(5)")
    let openTranslateShortcutLabel = NSTextField(labelWithString: "(6)")
    let answerField = NSTextField()
    let feedbackLabel = NSTextField(labelWithString: "")
    let hintLabel = NSTextField(wrappingLabelWithString: "")
    let resultLabel = NSTextField(wrappingLabelWithString: "")
    let readingChatView = ReadingChatView()
    let readingModeControl = NSSegmentedControl()
    let choiceStack = NSStackView()
    let firstChoiceButton = NSButton()
    let secondChoiceButton = NSButton()
    let sourceContainer = NSStackView()
    let scrollView = NSScrollView()
    let documentView = ReviewFlippedView()

    // Actions
    let revealButton = NSButton()
    let backButton = NSButton()
    let markDoneButton = NSButton()
    let regenerateButton = NSButton()
    private let againButton = NSButton()
    private let hardButton = NSButton()
    private let easyButton = NSButton()
    let gradeStack = NSStackView()
    /// Shown instead of `gradeStack` when the question graded itself: one wide "next" button plus
    /// a quiet override row.
    let autoGradeStack = NSStackView()
    private let continueButton = NSButton()
    private let overrideAgain = NSButton()
    private let overrideHard = NSButton()
    private let overrideEasy = NSButton()
    private let actionStack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Chrome updates

    /// The counters above the card. `elapsed` is the whole session, not this card.
    func updateProgress(correct: Int, wrong: Int, remaining: Int, elapsed: TimeInterval, practice: Bool) {
        let total = max(1, correct + wrong + remaining)
        progressBar.correctFraction = Double(correct) / Double(total)
        progressBar.wrongFraction = Double(wrong) / Double(total)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        let clock = String(format: "%d:%02d", minutes, seconds)
        let prefix = practice ? "Practice  ·  " : ""
        countsLabel.stringValue = "\(prefix)✓ \(correct)   ✗ \(wrong)   \(remaining) left   \(clock)"
    }

    func setPills(_ pills: [String]) {
        wordsDetailLabel.stringValue = ""
        wordsDetailLabel.isHidden = true
        pillRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for text in pills where !text.isEmpty {
            pillRow.addArrangedSubview(Self.makePill(text))
        }
        pillRow.isHidden = pills.isEmpty
        pillContainer.isHidden = pills.isEmpty
    }

    func setReadingPills(count: Int, words: [String], scenario: String? = nil) {
        learnBadgeView.clear()
        let scene = scenario?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Words and the scene are the two things that made this passage, so the pill reveals both.
        var lines: [String] = []
        if !words.isEmpty { lines.append(words.joined(separator: ", ")) }
        if !scene.isEmpty { lines.append("Scenario: " + scene) }
        wordsDetailLabel.stringValue = lines.joined(separator: "\n")
        wordsDetailLabel.isHidden = true
        pillRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        pillRow.addArrangedSubview(Self.makePill("Reading"))
        let countPill = Self.makeClickablePill("\(count) words") { [weak self] in
            guard let self else { return }
            self.wordsDetailLabel.isHidden.toggle()
        }
        pillRow.addArrangedSubview(countPill)
        pillRow.isHidden = false
        pillContainer.isHidden = false
    }

    /// Grade buttons carry the interval they would schedule, so the choice is never blind.
    func setGradeIntervals(again: String, hard: String, easy: String) {
        styleGrade(againButton, title: "Again (1)", detail: again, color: .systemRed)
        styleGrade(hardButton, title: "Hard (2)", detail: hard, color: .systemOrange)
        styleGrade(easyButton, title: "Easy (3)", detail: easy, color: .systemGreen)
    }

    /// The card already knows the grade, so the only real action is moving on. The three grades
    /// stay reachable underneath in case the learner disagrees.
    func showAutoGrade(_ grade: SRSGrade, name: String, interval: String) {
        let color = Self.gradeColor(grade)
        continueButton.tag = grade.rawValue
        continueButton.bezelColor = color
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let suffix = interval.isEmpty ? "" : "  ·  \(interval)"
        continueButton.attributedTitle = NSAttributedString(
            string: "Continue  ·  \(name)\(suffix)  (Space)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]
        )
        for button in [overrideAgain, overrideHard, overrideEasy] {
            let isPicked = button.tag == grade.rawValue
            styleOverride(button, dimmed: isPicked)
        }
        gradeStack.isHidden = true
        autoGradeStack.isHidden = false
    }

    private static func gradeColor(_ grade: SRSGrade) -> NSColor {
        switch grade {
        case .again: return .systemRed
        case .hard: return .systemOrange
        case .easy: return .systemGreen
        }
    }

    /// The grade the model already picked is spelled out on the big button, so its override reads
    /// as redundant and steps back.
    private func styleOverride(_ button: NSButton, dimmed: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let grade = SRSGrade(rawValue: button.tag) ?? .hard
        let color = dimmed ? NSColor.tertiaryLabelColor : Self.gradeColor(grade)
        button.attributedTitle = NSAttributedString(
            string: button.identifier?.rawValue ?? "",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    // MARK: - Build

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        ReviewControls.iconButton(homeButton, symbol: "house", label: "Back to home (Esc)", target: self, action: #selector(tapHome))
        ReviewControls.iconButton(undoButton, symbol: "arrow.uturn.backward.circle", label: "Undo last grade (Cmd+Z)", target: self, action: #selector(tapUndo))
        ReviewControls.iconButton(hideButton, symbol: "eye.slash", label: "Remove this card from the deck", target: self, action: #selector(tapHide))

        countsLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        countsLabel.textColor = .secondaryLabelColor
        countsLabel.alignment = .right
        countsLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let topBar = NSStackView(views: [homeButton, undoButton, hideButton, progressBar, countsLabel])
        topBar.orientation = .horizontal
        topBar.spacing = 8
        topBar.alignment = .centerY
        topBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.heightAnchor.constraint(equalToConstant: 6).isActive = true

        pillRow.orientation = .horizontal
        pillRow.spacing = 6
        pillRow.alignment = .centerY
        pillRow.translatesAutoresizingMaskIntoConstraints = false

        wordsDetailLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        wordsDetailLabel.textColor = .secondaryLabelColor
        wordsDetailLabel.alignment = .center
        wordsDetailLabel.lineBreakMode = .byWordWrapping
        wordsDetailLabel.maximumNumberOfLines = 0
        wordsDetailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        wordsDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        wordsDetailLabel.isHidden = true

        pillContainer.orientation = .vertical
        pillContainer.spacing = 6
        pillContainer.alignment = .centerX
        pillContainer.translatesAutoresizingMaskIntoConstraints = false
        learnBadgeView.translatesAutoresizingMaskIntoConstraints = false
        learnBadgeView.isHidden = true
        pillContainer.addArrangedSubview(pillRow)
        pillContainer.addArrangedSubview(learnBadgeView)
        pillContainer.addArrangedSubview(wordsDetailLabel)

        termLabel.font = .systemFont(ofSize: TextZoom.size(Self.termBaseSize), weight: .bold)
        termLabel.alignment = .center
        termLabel.lineBreakMode = .byWordWrapping
        termLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        termLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        contextLabel.font = .systemFont(ofSize: TextZoom.size(Self.contextBaseSize))
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.alignment = .center
        contextLabel.lineBreakMode = .byWordWrapping

        readMoreButton.title = "Read more"
        readMoreButton.isBordered = false
        readMoreButton.font = .systemFont(ofSize: 12, weight: .medium)
        readMoreButton.contentTintColor = .systemBlue
        readMoreButton.target = self
        readMoreButton.action = #selector(tapReadMore)
        readMoreButton.isHidden = true

        ReviewControls.iconButton(speakSourceButton, symbol: "speaker.wave.2", label: "Speak source (4 / 1.0x)", target: self, action: #selector(tapSpeak))
        ReviewControls.iconButton(speakSlowSourceButton, symbol: "tortoise", label: "Speak source slowly (5)", target: self, action: #selector(tapSpeakSlow))
        ReviewControls.iconButton(openTranslateButton, symbol: "character.bubble", label: "Open this card in Translate (6)", target: self, action: #selector(tapTranslate))

        for label in [speakShortcutLabel, speakSlowShortcutLabel, openTranslateShortcutLabel] {
            label.font = .systemFont(ofSize: 10, weight: .bold)
            label.textColor = .tertiaryLabelColor
            label.alignment = .center
        }

        let audioStack = NSStackView(views: [
            Self.pair(speakSourceButton, speakShortcutLabel),
            Self.pair(speakSlowSourceButton, speakSlowShortcutLabel),
            Self.pair(openTranslateButton, openTranslateShortcutLabel)
        ])
        audioStack.orientation = .horizontal
        audioStack.spacing = 6
        audioStack.alignment = .centerY

        // The buttons sit to the right of the term, so a spacer of the same width on the left
        // keeps the term itself optically centred, and collapses when the buttons hide.
        ReviewControls.iconButton(
            titleRefreshButton,
            symbol: "arrow.clockwise",
            label: "Generate a title for this passage",
            target: self,
            action: #selector(tapTitleRefresh)
        )
        titleRefreshButton.isHidden = true

        let leadingSpacer = NSView()
        leadingSpacer.translatesAutoresizingMaskIntoConstraints = false
        let termStack = NSStackView(views: [leadingSpacer, termLabel, titleRefreshButton, audioStack])
        termStack.orientation = .horizontal
        termStack.spacing = 8
        termStack.alignment = .centerY
        leadingSpacer.widthAnchor.constraint(equalTo: audioStack.widthAnchor).isActive = true

        answerField.placeholderString = "Type the missing word, then press Return"
        answerField.font = .systemFont(ofSize: 15)
        answerField.alignment = .center
        answerField.target = self
        answerField.action = #selector(submitAnswer)
        answerField.isHidden = true
        answerField.translatesAutoresizingMaskIntoConstraints = false
        answerField.widthAnchor.constraint(equalToConstant: 300).isActive = true

        feedbackLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        feedbackLabel.alignment = .center
        feedbackLabel.isHidden = true

        ReviewControls.actionButton(firstChoiceButton, title: "", symbol: "1.circle", target: self, action: #selector(chooseFirst))
        ReviewControls.actionButton(secondChoiceButton, title: "", symbol: "2.circle", target: self, action: #selector(chooseSecond))
        choiceStack.orientation = .horizontal
        choiceStack.spacing = 12
        choiceStack.distribution = .fillEqually
        choiceStack.addArrangedSubview(firstChoiceButton)
        choiceStack.addArrangedSubview(secondChoiceButton)
        choiceStack.isHidden = true
        choiceStack.translatesAutoresizingMaskIntoConstraints = false
        choiceStack.widthAnchor.constraint(equalToConstant: 380).isActive = true

        sourceContainer.orientation = .vertical
        sourceContainer.spacing = 6
        sourceContainer.alignment = .centerX
        sourceContainer.addArrangedSubview(termStack)
        sourceContainer.addArrangedSubview(contextLabel)
        sourceContainer.addArrangedSubview(readMoreButton)
        sourceContainer.addArrangedSubview(answerField)
        sourceContainer.addArrangedSubview(choiceStack)
        sourceContainer.addArrangedSubview(feedbackLabel)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.alignment = .center
        hintLabel.isHidden = true

        resultLabel.font = .systemFont(ofSize: TextZoom.size(Self.resultBaseSize))
        resultLabel.alignment = .left
        resultLabel.lineBreakMode = .byWordWrapping
        // Selecting hands the text to the field editor, which drops attributes unless the field
        // owns them. Without this the reading underlines vanish on click.
        resultLabel.allowsEditingTextAttributes = true

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

        let innerStack = NSStackView(views: [sourceContainer, hintLabel, readingModeControl, readingChatView, resultLabel])
        innerStack.orientation = .vertical
        innerStack.spacing = 16
        innerStack.alignment = .centerX
        innerStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        documentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = documentView
        documentView.addSubview(innerStack)

        ReviewControls.actionButton(revealButton, title: "Show Answer (Space)", symbol: "eye", target: self, action: #selector(tapReveal))
        ReviewControls.actionButton(backButton, title: "Back", symbol: "chevron.backward", target: self, action: #selector(tapBack))
        backButton.isHidden = true
        ReviewControls.actionButton(markDoneButton, title: "Mark Done", symbol: "checkmark.circle", target: self, action: #selector(tapMarkDone))
        markDoneButton.isHidden = true
        ReviewControls.actionButton(regenerateButton, title: "Regenerate", symbol: "arrow.clockwise", target: self, action: #selector(tapRegenerate))
        regenerateButton.isHidden = true
        regenerateButton.toolTip = "Ask the model for a new conversation from the same words"

        for button in [againButton, hardButton, easyButton] {
            button.bezelStyle = .flexiblePush
            button.target = self
            button.action = #selector(gradeClicked(_:))
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 46).isActive = true
        }
        againButton.tag = SRSGrade.again.rawValue
        hardButton.tag = SRSGrade.hard.rawValue
        easyButton.tag = SRSGrade.easy.rawValue
        setGradeIntervals(again: "", hard: "", easy: "")

        gradeStack.orientation = .horizontal
        gradeStack.spacing = 10
        gradeStack.distribution = .fillEqually
        gradeStack.addArrangedSubview(againButton)
        gradeStack.addArrangedSubview(hardButton)
        gradeStack.addArrangedSubview(easyButton)
        gradeStack.isHidden = true
        gradeStack.translatesAutoresizingMaskIntoConstraints = false

        continueButton.bezelStyle = .flexiblePush
        continueButton.controlSize = .regular
        continueButton.target = self
        continueButton.action = #selector(gradeClicked(_:))
        continueButton.translatesAutoresizingMaskIntoConstraints = false
        continueButton.heightAnchor.constraint(equalToConstant: 34).isActive = true

        let overrideLabel = NSTextField(labelWithString: "Override:")
        overrideLabel.font = .systemFont(ofSize: 11)
        overrideLabel.textColor = .tertiaryLabelColor
        for (button, tag, title) in [
            (overrideAgain, SRSGrade.again.rawValue, "Again (1)"),
            (overrideHard, SRSGrade.hard.rawValue, "Hard (2)"),
            (overrideEasy, SRSGrade.easy.rawValue, "Easy (3)")
        ] {
            button.bezelStyle = .inline
            button.isBordered = false
            button.tag = tag
            button.identifier = NSUserInterfaceItemIdentifier(title)
            button.target = self
            button.action = #selector(gradeClicked(_:))
            styleOverride(button, dimmed: false)
        }
        let overrideRow = NSStackView(views: [overrideLabel, overrideAgain, overrideHard, overrideEasy])
        overrideRow.orientation = .horizontal
        overrideRow.spacing = 10
        overrideRow.alignment = .centerY

        autoGradeStack.orientation = .vertical
        autoGradeStack.spacing = 8
        autoGradeStack.alignment = .centerX
        autoGradeStack.addArrangedSubview(continueButton)
        autoGradeStack.addArrangedSubview(overrideRow)
        autoGradeStack.isHidden = true
        autoGradeStack.translatesAutoresizingMaskIntoConstraints = false

        actionStack.orientation = .vertical
        actionStack.spacing = 10
        actionStack.alignment = .centerX
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.addArrangedSubview(revealButton)
        actionStack.addArrangedSubview(gradeStack)
        actionStack.addArrangedSubview(autoGradeStack)
        // Back and Done sit side by side under the passage; Done is the green half.
        let readingRow = NSStackView(views: [backButton, regenerateButton, markDoneButton])
        readingRow.orientation = .horizontal
        readingRow.spacing = 10
        readingRow.distribution = .fillEqually
        readingRow.translatesAutoresizingMaskIntoConstraints = false
        actionStack.addArrangedSubview(readingRow)
        readingRow.widthAnchor.constraint(equalTo: actionStack.widthAnchor).isActive = true

        addSubview(topBar)
        addSubview(pillContainer)
        addSubview(scrollView)
        addSubview(actionStack)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            pillContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            pillContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 10),
            pillContainer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            pillContainer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: pillContainer.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: actionStack.topAnchor, constant: -14),

            documentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            documentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            documentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            documentView.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.heightAnchor),

            readingChatView.widthAnchor.constraint(equalTo: innerStack.widthAnchor),
            innerStack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: 24),
            innerStack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -24),
            innerStack.centerYAnchor.constraint(equalTo: documentView.centerYAnchor),
            innerStack.topAnchor.constraint(greaterThanOrEqualTo: documentView.topAnchor, constant: 20),
            innerStack.bottomAnchor.constraint(lessThanOrEqualTo: documentView.bottomAnchor, constant: -20),

            actionStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            actionStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            actionStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

            gradeStack.widthAnchor.constraint(equalTo: actionStack.widthAnchor),
            autoGradeStack.widthAnchor.constraint(equalTo: actionStack.widthAnchor),
            continueButton.widthAnchor.constraint(lessThanOrEqualTo: autoGradeStack.widthAnchor),
            continueButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 340),
            revealButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            revealButton.heightAnchor.constraint(equalToConstant: 38),
            backButton.heightAnchor.constraint(equalToConstant: 38),
            markDoneButton.heightAnchor.constraint(equalToConstant: 38),
            regenerateButton.heightAnchor.constraint(equalToConstant: 38),
            firstChoiceButton.heightAnchor.constraint(equalToConstant: 34),
            secondChoiceButton.heightAnchor.constraint(equalToConstant: 34)
        ])
    }

    private func styleGrade(_ button: NSButton, title: String, detail: String, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 1
        let text = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ])
        if !detail.isEmpty {
            text.append(NSAttributedString(string: "\n" + detail, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor,
                .paragraphStyle: paragraph
            ]))
        }
        button.attributedTitle = text
    }

    private static func pair(_ button: NSButton, _ label: NSTextField) -> NSStackView {
        let stack = NSStackView(views: [button, label])
        stack.orientation = .horizontal
        stack.spacing = 1
        stack.alignment = .centerY
        return stack
    }

    private final class ClickablePill: NSView {
        var onClick: (() -> Void)?

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if bounds.contains(point) {
                onClick?()
            }
        }
    }

    static func makePill(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 9
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -3)
        ])
        return box
    }

    private static func makeClickablePill(_ text: String, onClick: @escaping () -> Void) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        let box = ClickablePill()
        box.onClick = onClick
        box.wantsLayer = true
        box.layer?.cornerRadius = 9
        box.layer?.borderWidth = 1
        box.layer?.borderColor = NSColor.separatorColor.cgColor
        box.toolTip = "Click to toggle word list"
        box.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -3)
        ])
        return box
    }

    // MARK: - Actions

    @objc private func tapHome() { delegate?.sessionViewDidTapHome(self) }
    @objc private func tapUndo() { delegate?.sessionViewDidTapUndo(self) }
    @objc private func tapHide() { delegate?.sessionViewDidTapHide(self) }
    @objc private func tapReveal() { delegate?.sessionViewDidTapReveal(self) }
    @objc private func tapBack() { delegate?.sessionViewDidTapBack(self) }
    @objc private func tapMarkDone() { delegate?.sessionViewDidTogglePassageDone(self) }
    @objc private func tapRegenerate() { delegate?.sessionViewDidRequestPassageRegenerate(self) }

    /// Shows whether the open passage is already done, and which way the button will flip it.
    func setPassageDone(_ isDone: Bool) {
        markDoneButton.title = isDone ? "  Done" : "  Mark Done"
        markDoneButton.image = NSImage(
            systemSymbolName: isDone ? "checkmark.circle.fill" : "checkmark.circle",
            accessibilityDescription: markDoneButton.title
        )
        markDoneButton.contentTintColor = isDone ? .systemGreen : .systemTeal
    }
    @objc private func tapTitleRefresh() { delegate?.sessionViewDidRequestPassageTitle(self) }

    @objc private func tapReadMore() { delegate?.sessionViewDidToggleContext(self) }
    @objc private func tapSpeak() { delegate?.sessionView(self, didRequestSpeechSlow: false) }
    @objc private func tapSpeakSlow() { delegate?.sessionView(self, didRequestSpeechSlow: true) }
    @objc private func tapTranslate() { delegate?.sessionViewDidRequestTranslate(self) }
    @objc private func submitAnswer() { delegate?.sessionViewDidSubmitAnswer(self) }
    @objc private func chooseFirst() { delegate?.sessionView(self, didChooseAt: 0) }
    @objc private func chooseSecond() { delegate?.sessionView(self, didChooseAt: 1) }
    @objc private func readingModeChanged() {
        delegate?.sessionView(self, didChangeReadingMode: readingModeControl.selectedSegment)
    }

    @objc private func gradeClicked(_ sender: NSButton) {
        guard let grade = SRSGrade(rawValue: sender.tag) else { return }
        delegate?.sessionView(self, didGrade: grade)
    }
}

/// Two stacked fills: how much of the session was answered right, and how much was missed.
@MainActor
final class SessionProgressBar: NSView {
    var correctFraction: Double = 0 { didSet { needsDisplay = true } }
    var wrongFraction: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        NSColor.separatorColor.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()

        let correctWidth = bounds.width * CGFloat(min(1, max(0, correctFraction)))
        let wrongWidth = bounds.width * CGFloat(min(1, max(0, wrongFraction)))
        guard correctWidth + wrongWidth > 0 else { return }

        let clip = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        clip.addClip()
        NSColor.systemGreen.setFill()
        bounds.divided(atDistance: correctWidth, from: .minXEdge).slice.fill()
        NSColor.systemRed.setFill()
        NSRect(x: correctWidth, y: 0, width: wrongWidth, height: bounds.height).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// AppKit lays out scroll documents from the bottom unless the view says otherwise.
@MainActor
final class ReviewFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Button styling shared by every review screen, so one change of look lands everywhere.
@MainActor
enum ReviewControls {
    static let iconSize: CGFloat = 20

    static func iconButton(_ button: NSButton, symbol: String, label: String, target: AnyObject, action: Selector) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(configuration)
        button.isBordered = false
        button.target = target
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.imageScaling = .scaleProportionallyUpOrDown
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
    }

    static func actionButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        target: AnyObject,
        action: Selector,
        key: String? = nil
    ) {
        button.title = "  " + title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.target = target
        button.action = action
        if let key { button.keyEquivalent = key }
    }
}

extension ReviewSessionView {
    /// Cmd+Plus / Cmd+Minus. Only the prompt, context and answer text moves; chrome stays put.
    func applyTextZoom() {
        TextZoom.apply(to: termLabel, base: Self.termBaseSize, weight: .bold)
        TextZoom.apply(to: contextLabel, base: Self.contextBaseSize)
        TextZoom.apply(to: resultLabel, base: Self.resultBaseSize)
    }
}
