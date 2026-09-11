// The home screen: what the deck looks like today, and every way into it.
import AppKit

@MainActor
protocol ReviewHomeViewDelegate: AnyObject {
    func homeViewDidStart(_ view: ReviewHomeView)
    func homeViewDidRequestNewWords(_ view: ReviewHomeView)
    func homeViewDidRequestReading(_ view: ReviewHomeView)
    func homeView(_ view: ReviewHomeView, didRequestPassagesFrom sender: NSButton)
    func homeViewDidRequestPracticeAll(_ view: ReviewHomeView, shuffled: Bool)
    /// Filter, limit or question kind changed and should be remembered.
    func homeViewDidChangeOptions(_ view: ReviewHomeView)
}

@MainActor
final class ReviewHomeView: NSView {
    weak var delegate: ReviewHomeViewDelegate?

    /// nil means every bucket.
    private(set) var selectedBucket: DeckStats.Bucket?
    /// nil means no cap on the session.
    private(set) var sessionLimit: Int?
    /// nil means Auto.
    private(set) var requestedKind: ReviewPlanner.QuestionKind?

    private let ring = DeckRingView()
    private let legendStack = NSStackView()
    private let streakLabel = NSTextField(labelWithString: "")
    private let heatRow = NSStackView()
    private let heatCaption = NSTextField(labelWithString: "")
    private let limitRow = NSStackView()
    private let modeGrid = NSStackView()
    private let startButton = NSButton()
    private let newWordsButton = NSButton()
    private let readingButton = NSButton()
    private let passagesButton = NSButton()
    private let practiceButton = NSButton()
    private let shuffleButton = NSButton()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "")

    private var legendTiles: [DeckStats.Bucket: LegendRow] = [:]
    private var limitTiles: [ReviewTile] = []
    private var modeTiles: [ReviewTile] = []
    private var stats = DeckStats()

    private static let limits: [Int?] = [10, 20, nil]
    /// Every section lines up on this width: 3 mode columns + 2 gaps.
    private static let contentWidth: CGFloat = 526
    /// Limit chips, mode tiles, and action buttons share this so the left edge is one curve.
    fileprivate static let controlCornerRadius: CGFloat = 12

    init(limit: Int?, kind: ReviewPlanner.QuestionKind?, bucket: DeckStats.Bucket?) {
        sessionLimit = limit
        requestedKind = kind
        selectedBucket = bucket
        super.init(frame: .zero)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Data

    func update(stats: DeckStats, readingEnabled: Bool, missedCount: Int, hasSavedCards: Bool) {
        self.stats = stats
        ring.segments = [
            (NSColor.systemBlue, stats.count(.learning)),
            (NSColor.systemOrange, stats.count(.due)),
            (NSColor.systemGreen, stats.count(.new)),
            (NSColor.systemRed, stats.count(.leech)),
            (NSColor.tertiaryLabelColor, stats.count(.mastered))
        ]
        ring.headline = "\(stats.dueToday)"
        ring.caption = "due hôm nay"
        for (bucket, row) in legendTiles {
            row.count = stats.count(bucket)
            row.isSelected = selectedBucket == bucket
            row.isEnabled = stats.count(bucket) > 0
        }
        streakLabel.stringValue = "\(stats.dayStreak)"
        let week = stats.last7Days
        let peak = max(1, week.max() ?? 1)
        for (index, cell) in heatRow.arrangedSubviews.enumerated() {
            guard let cell = cell as? HeatCell else { continue }
            cell.level = index < week.count ? Double(week[index]) / Double(peak) : 0
            cell.toolTip = index < week.count ? "\(week[index]) thẻ" : nil
        }
        let total = week.reduce(0, +)
        heatCaption.stringValue = "7 ngày gần nhất: \(total) thẻ · ngày mai: \(stats.dueTomorrow) thẻ"

        emptyLabel.isHidden = hasSavedCards
        emptyLabel.stringValue = "Chưa có thẻ nào được lưu. Bấm Học từ mới để lấy thẻ từ kho có sẵn, hoặc lưu từ trong popup dịch."
        startButton.isHidden = !hasSavedCards
        practiceButton.isHidden = !hasSavedCards
        shuffleButton.isHidden = !hasSavedCards
        readingButton.isEnabled = readingEnabled
        readingButton.isHidden = !hasSavedCards
        passagesButton.isHidden = !hasSavedCards
        readingButton.title = missedCount == 0 ? "  Reading Passage" : "  Reading Passage (\(missedCount))"

        let count = plannedCount()
        setStartTitle(count > 0 ? "  Start Review (\(count))" : "  Review Anyway")
        hintLabel.stringValue = selectionHint()
    }

    /// How many cards the current filter and limit would actually queue.
    func plannedCount() -> Int {
        let available = selectedBucket.map { stats.count($0) } ?? stats.dueToday
        guard let sessionLimit else { return available }
        return min(available, sessionLimit)
    }

    private func selectionHint() -> String {
        var parts: [String] = []
        if let selectedBucket { parts.append("Lọc: \(selectedBucket.label)") }
        parts.append(sessionLimit.map { "Tối đa \($0) thẻ" } ?? "Không giới hạn")
        parts.append("Kiểu hỏi: \(requestedKind?.label ?? "Auto")")
        return parts.joined(separator: "   ·   ")
    }

    // MARK: - Build

    private func build() {
        translatesAutoresizingMaskIntoConstraints = false

        ring.translatesAutoresizingMaskIntoConstraints = false
        ring.widthAnchor.constraint(equalToConstant: 132).isActive = true
        ring.heightAnchor.constraint(equalToConstant: 132).isActive = true

        legendStack.orientation = .vertical
        legendStack.spacing = 6
        legendStack.alignment = .leading
        for bucket in [DeckStats.Bucket.learning, .due, .new, .mastered, .leech] {
            let row = LegendRow(bucket: bucket, color: Self.color(for: bucket))
            row.onClick = { [weak self] in self?.toggleBucket(bucket) }
            legendTiles[bucket] = row
            legendStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: legendStack.widthAnchor).isActive = true
        }

        streakLabel.font = .systemFont(ofSize: 20, weight: .bold)
        let streakCaption = NSTextField(labelWithString: "ngày liên tiếp")
        streakCaption.font = .systemFont(ofSize: 11)
        streakCaption.textColor = .secondaryLabelColor

        heatRow.orientation = .horizontal
        heatRow.spacing = 4
        for _ in 0..<7 { heatRow.addArrangedSubview(HeatCell()) }

        heatCaption.font = .systemFont(ofSize: 11)
        heatCaption.textColor = .tertiaryLabelColor

        let streakRow = NSStackView(views: [streakLabel, streakCaption, heatRow])
        streakRow.orientation = .horizontal
        streakRow.spacing = 8
        streakRow.alignment = .centerY

        // The caption is a full sentence; on the same line as the strip it gets truncated.
        let streakColumn = NSStackView(views: [streakRow, heatCaption])
        streakColumn.orientation = .vertical
        streakColumn.spacing = 4
        streakColumn.alignment = .leading

        let statsColumn = NSStackView(views: [legendStack, streakColumn])
        statsColumn.orientation = .vertical
        statsColumn.spacing = 12
        statsColumn.alignment = .leading

        let heroContent = NSStackView(views: [ring, statsColumn])
        heroContent.orientation = .horizontal
        heroContent.spacing = 22
        heroContent.alignment = .centerY
        heroContent.translatesAutoresizingMaskIntoConstraints = false

        let hero = NSView()
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.wantsLayer = true
        hero.layer?.cornerRadius = 12
        hero.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor
        hero.addSubview(heroContent)
        NSLayoutConstraint.activate([
            heroContent.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 18),
            heroContent.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -18),
            heroContent.topAnchor.constraint(equalTo: hero.topAnchor, constant: 18),
            heroContent.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -18)
        ])

        limitRow.orientation = .horizontal
        limitRow.spacing = 8
        limitRow.distribution = .fillEqually
        for limit in Self.limits {
            let tile = ReviewTile(title: limit.map { "\($0) thẻ" } ?? "Tất cả", detail: nil, compact: true)
            tile.isSelected = limit == sessionLimit
            tile.onClick = { [weak self] in self?.selectLimit(limit) }
            limitTiles.append(tile)
            limitRow.addArrangedSubview(tile)
        }

        var tiles: [ReviewTile] = []
        for option in Self.modeOptions {
            let tile = ReviewTile(title: option.title, detail: option.detail, compact: false)
            tile.isSelected = option.kind == requestedKind
            tile.onClick = { [weak self] in self?.selectKind(option.kind) }
            tiles.append(tile)
        }
        modeTiles = tiles
        // NSGridView hugs vertically too weakly and swallowed the window's spare height,
        // so the rows are plain stacks that keep their intrinsic height.
        modeGrid.orientation = .vertical
        modeGrid.spacing = 8
        modeGrid.distribution = .fillEqually
        let columns = 3
        let rows = (tiles.count + columns - 1) / columns
        for row in 0..<rows {
            let slice = Array(tiles[(row * columns)..<min(tiles.count, row * columns + columns)])
            let rowStack = NSStackView(views: slice)
            rowStack.orientation = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually
            modeGrid.addArrangedSubview(rowStack)
            rowStack.widthAnchor.constraint(equalTo: modeGrid.widthAnchor).isActive = true
        }
        // One tile with two lines of detail must not make its row taller than the other.
        for tile in tiles.dropFirst() {
            tile.heightAnchor.constraint(equalTo: tiles[0].heightAnchor).isActive = true
        }

        ReviewControls.actionButton(startButton, title: "Start Review", symbol: "play.fill", target: self, action: #selector(tapStart))
        ReviewControls.actionButton(newWordsButton, title: "Học từ mới", symbol: "sparkles", target: self, action: #selector(tapNewWords))
        ReviewControls.actionButton(readingButton, title: "Reading Passage", symbol: "text.book.closed", target: self, action: #selector(tapReading))
        ReviewControls.actionButton(passagesButton, title: "Saved Passages", symbol: "list.bullet.rectangle", target: self, action: #selector(tapPassages))
        ReviewControls.actionButton(practiceButton, title: "Review All", symbol: "arrow.clockwise", target: self, action: #selector(tapPractice))
        ReviewControls.actionButton(shuffleButton, title: "Review All (Shuffled)", symbol: "shuffle", target: self, action: #selector(tapShuffle))
        practiceButton.toolTip = "Practice only — does not change due dates"
        shuffleButton.toolTip = "Practice only — does not change due dates"

        // One accented primary, the rest tinted by role so the block is scannable.
        let tints: [(NSButton, NSColor)] = [
            (newWordsButton, .systemGreen),
            (readingButton, .systemPurple),
            (passagesButton, .systemTeal),
            (practiceButton, .systemOrange),
            (shuffleButton, .systemPink)
        ]
        for (button, color) in tints { button.contentTintColor = color }
        startButton.bezelColor = .controlAccentColor
        startButton.contentTintColor = .white
        // The glass bezel ignores contentTintColor for the symbol, so paint it into the image.
        startButton.image = startButton.image?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(paletteColors: [.white])
        )
        startButton.keyEquivalent = "\r"
        for button in [startButton, newWordsButton, readingButton, passagesButton, practiceButton, shuffleButton] {
            button.translatesAutoresizingMaskIntoConstraints = false
            button.heightAnchor.constraint(equalToConstant: 54).isActive = true
            applyControlCornerRadius(button)
        }
        setStartTitle(startButton.title)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor

        // Four buttons on one line overflow the window; two rows of two keep every label on one line.
        let buttonRows = [
            NSStackView(views: [startButton, newWordsButton]),
            NSStackView(views: [readingButton, passagesButton]),
            NSStackView(views: [practiceButton, shuffleButton])
        ]
        for row in buttonRows {
            row.orientation = .horizontal
            row.spacing = 10
            row.distribution = .fillEqually
        }

        let limitHeader = Self.sectionHeader("Mục tiêu phiên")
        let modeHeader = Self.sectionHeader("Kiểu hỏi")
        let stack = NSStackView(views: [
            hero,
            emptyLabel,
            limitHeader,
            limitRow,
            modeHeader,
            modeGrid,
            hintLabel
        ] + buttonRows)
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading
        // Headers start a new section; the control they label stays tight under them.
        // A hidden empty label collapses, so the gap before the first header hangs off the hero.
        stack.setCustomSpacing(28, after: hero)
        stack.setCustomSpacing(28, after: emptyLabel)
        stack.setCustomSpacing(8, after: limitHeader)
        stack.setCustomSpacing(28, after: limitRow)
        stack.setCustomSpacing(8, after: modeHeader)
        stack.setCustomSpacing(14, after: modeGrid)
        stack.setCustomSpacing(22, after: hintLabel)
        // One spacing rule for every button row, so the block reads as an even grid.
        for row in buttonRows.dropLast() { stack.setCustomSpacing(10, after: row) }
        stack.translatesAutoresizingMaskIntoConstraints = false

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
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.centerXAnchor.constraint(equalTo: document.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: document.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalToConstant: Self.contentWidth),
            hero.widthAnchor.constraint(equalTo: stack.widthAnchor),
            emptyLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            limitRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            modeGrid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRows[0].widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRows[1].widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRows[2].widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private struct ModeOption {
        let kind: ReviewPlanner.QuestionKind?
        let title: String
        let detail: String
    }

    private static let modeOptions: [ModeOption] = [
        ModeOption(kind: nil, title: "Auto", detail: "Thẻ mới thì nhận mặt, thẻ cũ thì bắt tự nhớ."),
        ModeOption(kind: .flip, title: "Flip", detail: "Xem từ, tự đánh giá rồi lật đáp án."),
        ModeOption(kind: .cloze, title: "Cloze", detail: "Điền từ bị khuyết trong câu ví dụ."),
        ModeOption(kind: .recall, title: "Recall", detail: "Thấy nghĩa, gõ lại từ gốc."),
        ModeOption(kind: .listen, title: "Listen", detail: "Nghe phát âm rồi gõ lại từ."),
        ModeOption(kind: .contrast, title: "Contrast", detail: "Chọn đúng giữa hai từ dễ nhầm."),
        ModeOption(kind: .collocation, title: "Collocation", detail: "Type the common pairing from its meaning."),
        ModeOption(kind: .family, title: "Family", detail: "Type a related form from its gloss.")
    ]

    private static func color(for bucket: DeckStats.Bucket) -> NSColor {
        switch bucket {
        case .learning: return .systemBlue
        case .due: return .systemOrange
        case .new: return .systemGreen
        case .mastered: return .tertiaryLabelColor
        case .leech: return .systemRed
        }
    }

    override func layout() {
        super.layout()
        for button in [startButton, newWordsButton, readingButton, passagesButton, practiceButton, shuffleButton] {
            applyControlCornerRadius(button)
        }
    }

    private func applyControlCornerRadius(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = Self.controlCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    /// The accented primary needs its title drawn white; contentTintColor only tints the symbol.
    private func setStartTitle(_ title: String) {
        startButton.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: startButton.font ?? .systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ])
    }

    private static func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text.uppercased())
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        return label
    }

    // MARK: - Selection

    private func toggleBucket(_ bucket: DeckStats.Bucket) {
        guard stats.count(bucket) > 0 || selectedBucket == bucket else { return }
        selectedBucket = selectedBucket == bucket ? nil : bucket
        for (key, row) in legendTiles { row.isSelected = key == selectedBucket }
        hintLabel.stringValue = selectionHint()
        setStartTitle(plannedCount() > 0 ? "  Start Review (\(plannedCount()))" : "  Review Anyway")
        delegate?.homeViewDidChangeOptions(self)
    }

    private func selectLimit(_ limit: Int?) {
        sessionLimit = limit
        for (index, tile) in limitTiles.enumerated() {
            tile.isSelected = Self.limits[index] == limit
        }
        hintLabel.stringValue = selectionHint()
        setStartTitle(plannedCount() > 0 ? "  Start Review (\(plannedCount()))" : "  Review Anyway")
        delegate?.homeViewDidChangeOptions(self)
    }

    private func selectKind(_ kind: ReviewPlanner.QuestionKind?) {
        requestedKind = kind
        for (index, tile) in modeTiles.enumerated() {
            tile.isSelected = Self.modeOptions[index].kind == kind
        }
        hintLabel.stringValue = selectionHint()
        delegate?.homeViewDidChangeOptions(self)
    }

    @objc private func tapStart() { delegate?.homeViewDidStart(self) }
    @objc private func tapNewWords() { delegate?.homeViewDidRequestNewWords(self) }
    @objc private func tapReading() { delegate?.homeViewDidRequestReading(self) }
    @objc private func tapPassages() { delegate?.homeView(self, didRequestPassagesFrom: passagesButton) }
    @objc private func tapPractice() { delegate?.homeViewDidRequestPracticeAll(self, shuffled: false) }
    @objc private func tapShuffle() { delegate?.homeViewDidRequestPracticeAll(self, shuffled: true) }
}

/// Donut of the deck: one arc per bucket, sized by share, with today's workload in the middle.
@MainActor
final class DeckRingView: NSView {
    var segments: [(color: NSColor, value: Int)] = [] { didSet { needsDisplay = true } }
    var headline = "0" { didSet { needsDisplay = true } }
    var caption = "" { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 132, height: 132) }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = side / 2 - 8
        let width: CGFloat = 13

        let track = NSBezierPath()
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        track.lineWidth = width
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        track.stroke()

        let total = segments.reduce(0) { $0 + $1.value }
        guard total > 0 else { drawText(center: center); return }
        var angle: CGFloat = 90
        for segment in segments where segment.value > 0 {
            let sweep = CGFloat(segment.value) / CGFloat(total) * 360
            let path = NSBezierPath()
            // Negative sweep so the ring fills clockwise from the top, the way progress reads.
            path.appendArc(withCenter: center, radius: radius, startAngle: angle, endAngle: angle - sweep, clockwise: true)
            path.lineWidth = width
            path.lineCapStyle = .butt
            segment.color.setStroke()
            path.stroke()
            angle -= sweep
        }
        drawText(center: center)
    }

    private func drawText(center: NSPoint) {
        let headlineAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .bold),
            .foregroundColor: NSColor.labelColor
        ]
        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let headlineSize = headline.size(withAttributes: headlineAttributes)
        let captionSize = caption.size(withAttributes: captionAttributes)
        headline.draw(
            at: NSPoint(x: center.x - headlineSize.width / 2, y: center.y - headlineSize.height / 2 + 6),
            withAttributes: headlineAttributes
        )
        caption.draw(
            at: NSPoint(x: center.x - captionSize.width / 2, y: center.y - headlineSize.height / 2 - captionSize.height + 4),
            withAttributes: captionAttributes
        )
    }
}

/// One deck bucket: swatch, name, count, and a click that filters the session by it.
@MainActor
final class LegendRow: NSView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { refresh() } }
    var isEnabled = true { didSet { refresh() } }
    var count = 0 { didSet { countLabel.stringValue = "\(count)" } }

    private let swatch = NSView()
    private let nameLabel: NSTextField
    private let countLabel = NSTextField(labelWithString: "0")

    init(bucket: DeckStats.Bucket, color: NSColor) {
        nameLabel = NSTextField(labelWithString: "\(bucket.label) — \(bucket.detail)")
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        toolTip = "Chỉ học nhóm \(bucket.label)"

        swatch.wantsLayer = true
        swatch.layer?.backgroundColor = color.cgColor
        swatch.layer?.cornerRadius = 3
        swatch.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 12)
        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        countLabel.alignment = .right

        let stack = NSStackView(views: [swatch, nameLabel, NSView(), countLabel])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            swatch.widthAnchor.constraint(equalToConstant: 10),
            swatch.heightAnchor.constraint(equalToConstant: 10),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        onClick?()
    }

    private func refresh() {
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            : NSColor.clear.cgColor
        alphaValue = isEnabled ? 1 : 0.45
    }
}

/// One day of the streak strip.
@MainActor
final class HeatCell: NSView {
    var level: Double = 0 { didSet { refresh() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 4
        widthAnchor.constraint(equalToConstant: 18).isActive = true
        heightAnchor.constraint(equalToConstant: 18).isActive = true
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func refresh() {
        let clamped = min(1, max(0, level))
        layer?.backgroundColor = clamped == 0
            ? NSColor.separatorColor.withAlphaComponent(0.5).cgColor
            : NSColor.systemGreen.withAlphaComponent(0.25 + 0.75 * clamped).cgColor
    }
}

/// A pickable option: chips for the session limit, larger tiles for the question kinds.
@MainActor
final class ReviewTile: NSView {
    var onClick: (() -> Void)?
    var isSelected = false { didSet { refresh() } }

    private let titleLabel: NSTextField
    private let detailLabel: NSTextField?

    init(title: String, detail: String?, compact: Bool) {
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = detail.map { NSTextField(wrappingLabelWithString: $0) }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = ReviewHomeView.controlCornerRadius
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1.5

        titleLabel.font = .systemFont(ofSize: compact ? 12 : 13, weight: .semibold)
        detailLabel?.font = .systemFont(ofSize: 11)
        detailLabel?.textColor = .secondaryLabelColor
        // Inside the grid the tile has no natural width to wrap against, so name one.
        detailLabel?.preferredMaxLayoutWidth = 148

        titleLabel.alignment = compact ? .center : .left
        let stack = NSStackView(views: [titleLabel] + (detailLabel.map { [$0] } ?? []))
        stack.orientation = .vertical
        stack.spacing = 2
        stack.alignment = compact ? .centerX : .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: compact ? 13 : 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: compact ? -13 : -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: compact ? 18 : 17),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: compact ? -18 : -17)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { onClick?() }

    /// The labels would otherwise eat the click, leaving only the tile's padding clickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    private func refresh() {
        layer?.borderColor = isSelected
            ? NSColor.controlAccentColor.cgColor
            : NSColor.separatorColor.cgColor
        layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor
            : NSColor.clear.cgColor
    }
}
