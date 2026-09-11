// Browsing the shipped vocabulary pack one word at a time: read it, hear it, then decide whether
// it belongs in the deck. Nothing here touches the store; the controller does that.
import AppKit

@MainActor
protocol NewWordsViewDelegate: AnyObject {
    func newWordsView(_ view: NewWordsView, didDecide decision: NewWordsView.Decision)
    func newWordsView(_ view: NewWordsView, didRequestSpeechSlow slow: Bool)
    func newWordsView(_ view: NewWordsView, didSelect filter: VocabDiscovery.Filter)
    func newWordsViewDidRequestHome(_ view: NewWordsView)
}

@MainActor
final class NewWordsView: NSView {
    enum Decision { case known, learn, skip, unmarkKnown, next }

    weak var delegate: NewWordsViewDelegate?

    let speakButton = NSButton()
    let speakSlowButton = NSButton()

    private let levelPopup = NSPopUpButton()
    private let progressLabel = NSTextField(labelWithString: "")
    private let wordLabel = NSTextField(labelWithString: "")
    /// CEFR / frequency / register pulled out of the entry's "Mức dùng:" line.
    private let learnBadgeView = LearnBadgeView()
    private let detailView = NSTextView()
    private let detailScroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let knownButton = NSButton()
    private let learnButton = NSButton()
    private let skipButton = NSButton()
    private let actionRow = NSStackView()
    private let bodyStack = NSStackView()

    /// Popup order, so a selection maps back to a filter.
    private var filterOrder: [VocabDiscovery.Filter] = []
    private var isKnownMode = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Data

    func setLevels(_ counts: [VocabDiscovery.Level: Int], knownCount: Int, selected: VocabDiscovery.Filter) {
        levelPopup.removeAllItems()
        filterOrder = [.all] + VocabDiscovery.Level.allCases.filter { (counts[$0] ?? 0) > 0 }.map { .level($0) }
        filterOrder.append(.known)
        let total = counts.values.reduce(0, +)
        for filter in filterOrder {
            switch filter {
            case .all:
                levelPopup.addItem(withTitle: "All (\(total))")
            case .level(let level):
                levelPopup.addItem(withTitle: "\(level.label) (\(counts[level] ?? 0))")
            case .known:
                levelPopup.addItem(withTitle: "Known (\(knownCount))")
            }
        }
        if let index = filterOrder.firstIndex(of: selected) {
            levelPopup.selectItem(at: index)
        }
        updateActionButtons(isKnown: selected == .known)
    }

    func show(word: String, detail: String, remaining: Int, learned: Int, known: Int, skipped: Int) {
        bodyStack.isHidden = false
        actionRow.isHidden = false
        emptyLabel.isHidden = true
        wordLabel.stringValue = word
        detailView.string = learnBadgeView.apply(to: detail, live: true)
        detailView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        if isKnownMode {
            progressLabel.stringValue = "Browsing known words · \(remaining) left"
        } else {
            progressLabel.stringValue = "\(learned) learned · \(known) known · \(skipped) skipped · \(remaining) left"
        }
    }

    func showEmpty(message: String) {
        learnBadgeView.clear()
        bodyStack.isHidden = true
        actionRow.isHidden = true
        emptyLabel.isHidden = false
        emptyLabel.stringValue = message
        progressLabel.stringValue = ""
    }

    // MARK: - Build

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        let homeButton = NSButton()
        ReviewControls.iconButton(homeButton, symbol: "house", label: "Back to home (Esc)", target: self, action: #selector(tapHome))

        levelPopup.target = self
        levelPopup.action = #selector(levelChanged)
        levelPopup.toolTip = "Choose a vocabulary level to browse"

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .tertiaryLabelColor
        progressLabel.alignment = .right

        let topBar = NSStackView(views: [homeButton, levelPopup, NSView(), progressLabel])
        topBar.orientation = .horizontal
        topBar.spacing = 10
        topBar.alignment = .centerY
        topBar.translatesAutoresizingMaskIntoConstraints = false

        wordLabel.font = .systemFont(ofSize: 30, weight: .bold)
        wordLabel.alignment = .center

        ReviewControls.iconButton(speakButton, symbol: "speaker.wave.2", label: "Speak word (4)", target: self, action: #selector(tapSpeak))
        ReviewControls.iconButton(speakSlowButton, symbol: "tortoise", label: "Speak slowly (5)", target: self, action: #selector(tapSpeakSlow))

        let wordRow = NSStackView(views: [wordLabel, speakButton, speakSlowButton])
        wordRow.orientation = .horizontal
        wordRow.spacing = 8
        wordRow.alignment = .centerY

        detailView.isEditable = false
        detailView.isSelectable = true
        detailView.drawsBackground = false
        detailView.font = .systemFont(ofSize: 13)
        detailView.textContainerInset = NSSize(width: 12, height: 10)
        detailScroll.documentView = detailView
        detailScroll.borderType = .noBorder
        detailScroll.drawsBackground = true
        detailScroll.backgroundColor = .textBackgroundColor
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.scrollerStyle = .overlay
        detailScroll.wantsLayer = true
        detailScroll.layer?.cornerRadius = 10
        detailScroll.translatesAutoresizingMaskIntoConstraints = false

        // Added straight to the view rather than to a stack, so it has to opt into Auto Layout
        // itself; without this its constraints break and it lands in the bottom-left corner.
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        bodyStack.orientation = .vertical
        bodyStack.spacing = 12
        bodyStack.alignment = .centerX
        bodyStack.translatesAutoresizingMaskIntoConstraints = false
        learnBadgeView.translatesAutoresizingMaskIntoConstraints = false
        learnBadgeView.isHidden = true
        bodyStack.addArrangedSubview(wordRow)
        bodyStack.addArrangedSubview(learnBadgeView)
        bodyStack.addArrangedSubview(detailScroll)

        ReviewControls.actionButton(knownButton, title: "Known (1)", symbol: "checkmark.circle", target: self, action: #selector(tapKnown))
        ReviewControls.actionButton(learnButton, title: "Learn (2)", symbol: "plus.circle.fill", target: self, action: #selector(tapLearn))
        ReviewControls.actionButton(skipButton, title: "Skip (3)", symbol: "arrow.uturn.forward", target: self, action: #selector(tapSkip))
        // Only the first button used to carry a height, which left the row visibly uneven.
        for button in [knownButton, learnButton, skipButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 38).isActive = true
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        knownButton.toolTip = "Remove this word from suggestions"
        learnButton.toolTip = "Add to the deck and review today"
        skipButton.toolTip = "Move to the end of the queue, unseen words first"

        actionRow.orientation = .horizontal
        actionRow.spacing = 10
        actionRow.distribution = .fillEqually
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        actionRow.addArrangedSubview(knownButton)
        actionRow.addArrangedSubview(learnButton)
        actionRow.addArrangedSubview(skipButton)

        addSubview(topBar)
        addSubview(bodyStack)
        addSubview(emptyLabel)
        addSubview(actionRow)

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            topBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            topBar.topAnchor.constraint(equalTo: topAnchor, constant: 12),

            bodyStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            bodyStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            bodyStack.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 14),
            bodyStack.bottomAnchor.constraint(equalTo: actionRow.topAnchor, constant: -14),
            detailScroll.widthAnchor.constraint(equalTo: bodyStack.widthAnchor),

            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),

            actionRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            actionRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            actionRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])
    }

    @objc private func tapKnown() {
        delegate?.newWordsView(self, didDecide: isKnownMode ? .unmarkKnown : .known)
    }

    @objc private func tapLearn() {
        delegate?.newWordsView(self, didDecide: .learn)
    }

    @objc private func tapSkip() {
        delegate?.newWordsView(self, didDecide: isKnownMode ? .next : .skip)
    }

    @objc private func tapSpeak() { delegate?.newWordsView(self, didRequestSpeechSlow: false) }
    @objc private func tapSpeakSlow() { delegate?.newWordsView(self, didRequestSpeechSlow: true) }
    @objc private func tapHome() { delegate?.newWordsViewDidRequestHome(self) }

    @objc private func levelChanged() {
        let index = levelPopup.indexOfSelectedItem
        guard index >= 0, index < filterOrder.count else { return }
        let selected = filterOrder[index]
        updateActionButtons(isKnown: selected == .known)
        delegate?.newWordsView(self, didSelect: selected)
    }

    private func updateActionButtons(isKnown: Bool) {
        isKnownMode = isKnown
        if isKnown {
            setButton(knownButton, title: "Unmark known (1)", symbol: "arrow.uturn.backward", toolTip: "Remove from known so it can appear in new-word suggestions again")
            setButton(learnButton, title: "Learn (2)", symbol: "plus.circle.fill", toolTip: "Add to the deck and review today")
            setButton(skipButton, title: "Next (3)", symbol: "arrow.forward", toolTip: "Show the next known word")
        } else {
            setButton(knownButton, title: "Known (1)", symbol: "checkmark.circle", toolTip: "Remove this word from suggestions")
            setButton(learnButton, title: "Learn (2)", symbol: "plus.circle.fill", toolTip: "Add to the deck and review today")
            setButton(skipButton, title: "Skip (3)", symbol: "arrow.uturn.forward", toolTip: "Move to the end of the queue, unseen words first")
        }
    }

    private func setButton(_ button: NSButton, title: String, symbol: String, toolTip: String) {
        button.title = "  " + title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.toolTip = toolTip
    }
}
