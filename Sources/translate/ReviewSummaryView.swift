// End of a session: how it went, and the two things worth doing next.
import AppKit

@MainActor
protocol ReviewSummaryViewDelegate: AnyObject {
    func summaryViewDidRequestRedrill(_ view: ReviewSummaryView)
    func summaryViewDidRequestContinue(_ view: ReviewSummaryView)
    func summaryViewDidRequestReading(_ view: ReviewSummaryView)
    func summaryViewDidRequestHome(_ view: ReviewSummaryView)
}

@MainActor
final class ReviewSummaryView: NSView {
    struct Missed {
        let term: String
        let meaning: String
        let lapses: Int
        let isLeech: Bool
    }

    struct Result {
        var answered = 0
        var correct = 0
        var elapsed: TimeInterval = 0
        var remainingToday = 0
        var dueTomorrow = 0
        var missed: [Missed] = []
        var isPractice = false
    }

    weak var delegate: ReviewSummaryViewDelegate?

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let tileRow = NSStackView()
    private let missedHeader = NSTextField(labelWithString: "CARDS TO WATCH")
    private let missedStack = NSStackView()
    private let leechNote = NSTextField(wrappingLabelWithString: "")
    private let redrillButton = NSButton()
    private let continueButton = NSButton()
    private let readingButton = NSButton()
    private let homeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(_ result: Result, readingEnabled: Bool) {
        titleLabel.stringValue = result.isPractice ? "Practice round done" : "Today's session done"
        let accuracy = result.answered > 0
            ? Int((Double(result.correct) / Double(result.answered) * 100).rounded())
            : 0
        let perCard = result.answered > 0 ? Int(result.elapsed) / result.answered : 0
        subtitleLabel.stringValue = result.answered == 0
            ? "No cards were graded in this session."
            : "\(Plural.count(result.answered, "card")) graded"

        setTiles([
            ("\(accuracy)%", "Accuracy", accuracy >= 80 ? NSColor.systemGreen : NSColor.labelColor),
            (Self.clock(result.elapsed), "Time", .labelColor),
            ("\(perCard)s", "Average/card", .labelColor),
            ("\(result.remainingToday)", "Left today", .labelColor)
        ])

        missedStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for missed in result.missed {
            missedStack.addArrangedSubview(makeMissedRow(missed))
        }
        let hasMissed = !result.missed.isEmpty
        missedHeader.isHidden = !hasMissed
        missedStack.isHidden = !hasMissed
        redrillButton.isHidden = !hasMissed
        redrillButton.title = "  Redrill \(Plural.count(result.missed.count, "missed card"))  "

        let leeches = result.missed.filter(\.isLeech).map(\.term)
        leechNote.isHidden = leeches.isEmpty
        leechNote.stringValue = leeches.isEmpty
            ? ""
            : "\(leeches.joined(separator: ", ")) missed \(ReviewPlanner.leechLapses) or more times. Consider removing the card from the deck and learning it again from a new card."

        continueButton.isHidden = result.remainingToday == 0
        continueButton.title = "  Continue \(Plural.count(result.remainingToday, "remaining card"))  "
        readingButton.isEnabled = readingEnabled
    }

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        let seal = NSImageView()
        seal.image = NSImage(systemSymbolName: "checkmark.seal.fill", accessibilityDescription: "Review completed")
        seal.contentTintColor = .systemGreen
        seal.imageScaling = .scaleProportionallyUpOrDown
        seal.translatesAutoresizingMaskIntoConstraints = false
        seal.widthAnchor.constraint(equalToConstant: 44).isActive = true
        seal.heightAnchor.constraint(equalToConstant: 44).isActive = true

        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.alignment = .center
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center

        tileRow.orientation = .horizontal
        tileRow.spacing = 8
        tileRow.distribution = .fillEqually

        missedHeader.font = .systemFont(ofSize: 10, weight: .semibold)
        missedHeader.textColor = .tertiaryLabelColor

        missedStack.orientation = .vertical
        missedStack.spacing = 1
        missedStack.alignment = .leading

        leechNote.font = .systemFont(ofSize: 11)
        leechNote.textColor = .systemOrange
        leechNote.isHidden = true

        ReviewControls.actionButton(redrillButton, title: "Redrill missed cards", symbol: "arrow.clockwise", target: self, action: #selector(tapRedrill))
        ReviewControls.actionButton(continueButton, title: "Continue", symbol: "forward.fill", target: self, action: #selector(tapContinue))
        ReviewControls.actionButton(readingButton, title: "Weave into a passage", symbol: "text.book.closed", target: self, action: #selector(tapReading))
        ReviewControls.actionButton(homeButton, title: "Back to home", symbol: "house", target: self, action: #selector(tapHome))

        for button in [redrillButton, continueButton, readingButton, homeButton] {
            button.controlSize = .large
            button.title += "  "
        }

        let actionRow = NSStackView(views: [redrillButton, continueButton, readingButton, homeButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8

        let stack = NSStackView(views: [
            seal, titleLabel, subtitleLabel, tileRow,
            missedHeader, missedStack, leechNote, actionRow
        ])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(6, after: missedHeader)

        let scroll = NSScrollView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = ReviewFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.heightAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -20),
            tileRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            missedStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            leechNote.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func setTiles(_ tiles: [(String, String, NSColor)]) {
        tileRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for tile in tiles {
            let value = NSTextField(labelWithString: tile.0)
            value.font = .monospacedDigitSystemFont(ofSize: 21, weight: .bold)
            value.textColor = tile.2
            value.alignment = .center
            let caption = NSTextField(labelWithString: tile.1)
            caption.font = .systemFont(ofSize: 11)
            caption.textColor = .secondaryLabelColor
            caption.alignment = .center
            let box = NSStackView(views: [value, caption])
            box.orientation = .vertical
            box.spacing = 2
            box.alignment = .centerX
            box.edgeInsets = NSEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
            box.wantsLayer = true
            box.layer?.cornerRadius = 9
            box.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor
            tileRow.addArrangedSubview(box)
        }
    }

    private func makeMissedRow(_ missed: Missed) -> NSView {
        let term = NSTextField(labelWithString: missed.term)
        term.font = .systemFont(ofSize: 13, weight: .semibold)
        let meaning = NSTextField(labelWithString: missed.meaning)
        meaning.font = .systemFont(ofSize: 12)
        meaning.textColor = .secondaryLabelColor
        meaning.lineBreakMode = .byTruncatingTail
        let tag = NSTextField(labelWithString: missed.isLeech ? "leech · \(Plural.count(missed.lapses, "time"))" : "missed \(Plural.count(missed.lapses, "time"))")
        tag.font = .systemFont(ofSize: 11, weight: .medium)
        tag.textColor = missed.isLeech ? .systemOrange : .systemRed
        tag.alignment = .right

        let row = NSStackView(views: [term, meaning, NSView(), tag])
        row.orientation = .horizontal
        row.spacing = 10
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        row.wantsLayer = true
        row.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.1).cgColor
        row.layer?.cornerRadius = 7
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalTo: missedStack.widthAnchor).isActive = true
        return row
    }

    static func clock(_ elapsed: TimeInterval) -> String {
        let seconds = max(0, Int(elapsed))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    @objc private func tapRedrill() { delegate?.summaryViewDidRequestRedrill(self) }
    @objc private func tapContinue() { delegate?.summaryViewDidRequestContinue(self) }
    @objc private func tapReading() { delegate?.summaryViewDidRequestReading(self) }
    @objc private func tapHome() { delegate?.summaryViewDidRequestHome(self) }
}
