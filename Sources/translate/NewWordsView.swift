// Browsing the shipped vocabulary pack one word at a time: read it, hear it, then decide whether
// it belongs in the deck. Nothing here touches the store; the controller does that.
import AppKit

@MainActor
protocol NewWordsViewDelegate: AnyObject {
    func newWordsView(_ view: NewWordsView, didDecide decision: NewWordsView.Decision)
    func newWordsView(_ view: NewWordsView, didRequestSpeechSlow slow: Bool)
    func newWordsView(_ view: NewWordsView, didSelect level: VocabDiscovery.Level?)
    func newWordsViewDidRequestHome(_ view: NewWordsView)
}

@MainActor
final class NewWordsView: NSView {
    enum Decision { case known, learn, skip }

    weak var delegate: NewWordsViewDelegate?

    let speakButton = NSButton()
    let speakSlowButton = NSButton()

    private let levelPopup = NSPopUpButton()
    private let progressLabel = NSTextField(labelWithString: "")
    private let wordLabel = NSTextField(labelWithString: "")
    private let detailView = NSTextView()
    private let detailScroll = NSScrollView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let knownButton = NSButton()
    private let learnButton = NSButton()
    private let skipButton = NSButton()
    private let actionRow = NSStackView()
    private let bodyStack = NSStackView()

    /// Popup order, so a selection maps back to a level. `nil` is the "Tất cả" row.
    private var levelOrder: [VocabDiscovery.Level?] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Data

    func setLevels(_ counts: [VocabDiscovery.Level: Int], selected: VocabDiscovery.Level?) {
        levelPopup.removeAllItems()
        levelOrder = [nil] + VocabDiscovery.Level.allCases.filter { (counts[$0] ?? 0) > 0 }
        let total = counts.values.reduce(0, +)
        for level in levelOrder {
            guard let level else {
                levelPopup.addItem(withTitle: "Tất cả (\(total))")
                continue
            }
            levelPopup.addItem(withTitle: "\(level.label) (\(counts[level] ?? 0))")
        }
        if let index = levelOrder.firstIndex(where: { $0 == selected }) {
            levelPopup.selectItem(at: index)
        }
    }

    func show(word: String, detail: String, remaining: Int, learned: Int, known: Int, skipped: Int) {
        bodyStack.isHidden = false
        actionRow.isHidden = false
        emptyLabel.isHidden = true
        wordLabel.stringValue = word
        detailView.string = detail
        detailView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        progressLabel.stringValue = "\(learned) đã học · \(known) đã biết · \(skipped) bỏ qua · còn \(remaining) từ"
    }

    func showEmpty(message: String) {
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
        levelPopup.toolTip = "Chọn cấp độ từ vựng muốn duyệt"

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

        ReviewControls.iconButton(speakButton, symbol: "speaker.wave.2", label: "Đọc từ (4)", target: self, action: #selector(tapSpeak))
        ReviewControls.iconButton(speakSlowButton, symbol: "tortoise", label: "Đọc chậm (5)", target: self, action: #selector(tapSpeakSlow))

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
        bodyStack.addArrangedSubview(wordRow)
        bodyStack.addArrangedSubview(detailScroll)

        ReviewControls.actionButton(knownButton, title: "Đã biết (1)", symbol: "checkmark.circle", target: self, action: #selector(tapKnown))
        ReviewControls.actionButton(learnButton, title: "Học (2)", symbol: "plus.circle.fill", target: self, action: #selector(tapLearn))
        ReviewControls.actionButton(skipButton, title: "Bỏ qua (3)", symbol: "arrow.uturn.forward", target: self, action: #selector(tapSkip))
        knownButton.toolTip = "Bỏ hẳn từ này khỏi danh sách gợi ý"
        learnButton.toolTip = "Thêm vào deck và ôn ngay hôm nay"
        skipButton.toolTip = "Để lại cuối hàng, ưu tiên từ chưa gặp trước"

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
            actionRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            knownButton.heightAnchor.constraint(equalToConstant: 38)
        ])
    }

    @objc private func tapKnown() { delegate?.newWordsView(self, didDecide: .known) }
    @objc private func tapLearn() { delegate?.newWordsView(self, didDecide: .learn) }
    @objc private func tapSkip() { delegate?.newWordsView(self, didDecide: .skip) }
    @objc private func tapSpeak() { delegate?.newWordsView(self, didRequestSpeechSlow: false) }
    @objc private func tapSpeakSlow() { delegate?.newWordsView(self, didRequestSpeechSlow: true) }
    @objc private func tapHome() { delegate?.newWordsViewDidRequestHome(self) }

    @objc private func levelChanged() {
        let index = levelPopup.indexOfSelectedItem
        guard index >= 0, index < levelOrder.count else { return }
        delegate?.newWordsView(self, didSelect: levelOrder[index])
    }
}
