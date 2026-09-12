// Structured Learn result for the popup. Layout follows prototype A in
// `.design/learn-ui-prototypes.html`: hero, then one section per parsed field.
import AppKit

@MainActor
final class LearnStructuredCardView: NSView {
    var onSpeak: (() -> Void)?
    var onLearnWord: ((String) -> Void)?
    var onOpenSubtranslate: ((String) -> Void)?
    var onNeedsReflow: (() -> Void)?

    private(set) var card = LearnCard()
    private var exampleFilter: LearnCard.Level?
    private var concealedSentences: Set<String> = []
    private var clozeFailCount = 0
    private var clozeDidSucceed = false
    private var savedAnswer = ""

    /// Compact density floats pane icons over the card; keep this much top inset so the headword
    /// is not hidden under the toolbar. This is padding, not a scroll offset.
    static func headerReserve(hidesPaneHeader: Bool, iconButtonSize: CGFloat = 18) -> CGFloat {
        hidesPaneHeader ? iconButtonSize + 16 : 0
    }

    private let stack = NSStackView()
    private var stackTopConstraint: NSLayoutConstraint!
    private let badgeView = LearnBadgeView()
    private let badgeRow = NSStackView()
    let speakButton = HitFillButton(title: "", target: nil, action: nil)
    private let answerField = NSTextField(string: "")
    private let checkButton = NSButton(title: "Check", target: nil, action: nil)
    private let feedbackLabel = NSTextField(labelWithString: "")
    private var exampleRows: [ExampleRow] = []
    private var filterPills: [FilterPill] = []
    private var confusablePairs: [NSStackView] = []
    private var wrappingStacks: [WrappingStack] = []
    private var lastFittingWidth: CGFloat = 0
    private var isMeasuringHeight = false

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 14
        stack.userInterfaceLayoutDirection = .leftToRight
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        userInterfaceLayoutDirection = .leftToRight
        stackTopConstraint = stack.topAnchor.constraint(equalTo: topAnchor, constant: 14)
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.isHidden = true
        badgeView.setContentHuggingPriority(.required, for: .vertical)
        badgeView.setContentHuggingPriority(.required, for: .horizontal)
        badgeView.heightAnchor.constraint(equalToConstant: LearnBadgeView.height).isActive = true
        let badgeSpacer = NSView()
        badgeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        badgeRow.orientation = .horizontal
        badgeRow.alignment = .centerY
        badgeRow.spacing = 0
        badgeRow.isHidden = true
        badgeRow.addArrangedSubview(badgeView)
        badgeRow.addArrangedSubview(badgeSpacer)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stackTopConstraint,
        ])

        speakButton.target = self
        speakButton.action = #selector(speakClicked)
        speakButton.isBordered = false
        speakButton.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: "Speak source")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        speakButton.imagePosition = .imageOnly
        speakButton.contentTintColor = .secondaryLabelColor
        speakButton.toolTip = "Speak source"
        speakButton.setAccessibilityLabel("Speak source")
        speakButton.wantsLayer = true
        speakButton.layer?.cornerRadius = 7
        speakButton.layer?.borderWidth = 1
        speakButton.translatesAutoresizingMaskIntoConstraints = false
        speakButton.widthAnchor.constraint(equalToConstant: 26).isActive = true
        speakButton.heightAnchor.constraint(equalToConstant: 26).isActive = true

        answerField.placeholderString = "Type the answer"
        answerField.font = .systemFont(ofSize: scaled(13))
        answerField.bezelStyle = .roundedBezel
        answerField.focusRingType = .exterior
        answerField.target = self
        answerField.action = #selector(checkClicked)

        checkButton.isBordered = false
        checkButton.wantsLayer = true
        checkButton.layer?.cornerRadius = 7
        checkButton.focusRingType = .none
        checkButton.translatesAutoresizingMaskIntoConstraints = false
        checkButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true
        checkButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        checkButton.target = self
        checkButton.action = #selector(checkClicked)
        paintCheckButton()

        feedbackLabel.font = .systemFont(ofSize: scaled(12), weight: .semibold)
        feedbackLabel.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshChromeColors()
    }

    override func layout() {
        super.layout()
        refreshChromeColors()
        guard !isMeasuringHeight else { return }
        let width = bounds.width >= 1 ? bounds.width : lastFittingWidth
        if width >= 1 {
            applyConfusableOrientation(width: width)
        }
    }

    func preferredHeight(fittingWidth width: CGFloat) -> CGFloat {
        let target = max(120, width)
        lastFittingWidth = target
        applyConfusableOrientation(width: target)
        if window == nil, superview == nil {
            return measureDetached(width: target)
        }
        return measureInPlace(width: target)
    }

    /// Gắn tạm vào window ẩn để Auto Layout chia cột giống lúc view đã vào pane.
    private func measureDetached(width: CGFloat) -> CGFloat {
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 20),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        host.alphaValue = 0
        let box = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 20))
        host.contentView = box
        box.addSubview(self)
        frame = NSRect(x: 0, y: 0, width: width, height: 20)
        let height = measureInPlace(width: width)
        removeFromSuperview()
        host.contentView = nil
        host.close()
        return height
    }

    private func measureInPlace(width: CGFloat) -> CGFloat {
        isMeasuringHeight = true
        defer { isMeasuringHeight = false }
        var next = frame
        next.size.width = width
        if next.size.height < 1 { next.size.height = 10 }
        frame = next
        applyConfusableOrientation(width: width)
        let inner = max(80, width - 28)
        var locks: [NSLayoutConstraint] = []
        let stackLock = stack.widthAnchor.constraint(equalToConstant: inner)
        stackLock.priority = .required
        stackLock.isActive = true
        locks.append(stackLock)
        for pair in confusablePairs {
            let lock = pair.widthAnchor.constraint(equalToConstant: inner)
            lock.priority = .required
            lock.isActive = true
            locks.append(lock)
        }
        for wrap in wrappingStacks {
            let lock = wrap.widthAnchor.constraint(equalToConstant: inner)
            lock.priority = .required
            lock.isActive = true
            locks.append(lock)
        }
        applyPreferredMaxLayoutWidths(innerWidth: inner)
        stack.layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
        // Confusable columns pad 10pt each side; wrap width must use that inner
        // column or a long gloss measures as one line and paints across the rule.
        syncConfusableWrapWidths()
        stack.layoutSubtreeIfNeeded()
        layoutSubtreeIfNeeded()
        let height = stack.fittingSize.height + stackTopConstraint.constant + 16
        locks.forEach { $0.isActive = false }
        return ceil(max(height, 1))
    }

    private func applyPreferredMaxLayoutWidths(innerWidth: CGFloat) {
        let wide = lastFittingWidth >= 300
        let pairWidth = wide ? max(40, (innerWidth - 8) / 2) : innerWidth
        func walk(_ view: NSView, width: CGFloat) {
            if let field = view as? NSTextField {
                field.preferredMaxLayoutWidth = max(40, width)
            }
            if let wrap = view as? WrappingStack {
                wrap.prepare(forWidth: width)
            }
            var next = width
            if confusablePairs.contains(where: { $0 === view }) {
                next = pairWidth
            } else if view is ConfusableSide {
                next = max(40, width - 20)
            }
            for child in view.subviews {
                walk(child, width: next)
            }
        }
        walk(stack, width: innerWidth)
    }

    private func syncConfusableWrapWidths() {
        func walk(_ view: NSView) {
            if let side = view as? ConfusableSide {
                side.syncWrapWidth()
            }
            view.subviews.forEach(walk)
        }
        walk(self)
    }

    /// Extra top padding so floating pane icons do not cover the headword. Lives on the
    /// card itself — scroll-view contentInsets plus a flipped document jumps off the top.
    func applyChromeReserve(_ reserve: CGFloat) {
        let next = 14 + reserve
        guard abs(stackTopConstraint.constant - next) > 0.5 else { return }
        stackTopConstraint.constant = next
    }

    func applyZoom() {
        rebuild()
        answerField.stringValue = savedAnswer
        restoreClozeFeedback()
    }

    /// Usage badge sits in the pane toolbar now. Kept so callers can still strip/apply without a row here.
    @discardableResult
    func applyUsage(from text: String, live: Bool) -> Bool {
        _ = text
        _ = live
        badgeView.clear()
        badgeRow.isHidden = true
        return false
    }

    var isUsageBadgeHidden: Bool { badgeView.isHidden }

    func display(_ card: LearnCard) {
        if card == self.card { return }
        let sameHeadword = LearnCard.normalizeAnswer(card.headword) == LearnCard.normalizeAnswer(self.card.headword)
        if sameHeadword {
            savedAnswer = answerField.stringValue
        } else {
            exampleFilter = nil
            concealedSentences = []
            clozeFailCount = 0
            clozeDidSucceed = false
            savedAnswer = ""
        }
        self.card = card
        rebuild()
        answerField.stringValue = savedAnswer
    }

    func resetScrollState() {
        exampleFilter = nil
        concealedSentences = []
        clozeFailCount = 0
        clozeDidSucceed = false
        savedAnswer = ""
        answerField.stringValue = ""
        feedbackLabel.isHidden = true
        // Xóa card đang giữ để lần display() sau cùng nội dung vẫn dựng lại cây,
        // thay vì thoát sớm và để lại tab lọc / lớp che cũ.
        card = LearnCard()
    }

    /// Trạng thái lọc và lớp che, dùng cho self-check sau reset rồi hiển thị lại.
    func chromeState() -> (filterCleared: Bool, visibleExamples: Int, revealed: Int) {
        (
            exampleFilter == nil,
            exampleRows.filter { !$0.isHidden }.count,
            exampleRows.filter { !$0.isHidden && $0.revealed }.count
        )
    }

    func pickFilterTab(_ raw: String) {
        selectFilter(raw)
    }

    func revealExample(at index: Int) {
        guard exampleRows.indices.contains(index) else { return }
        let row = exampleRows[index]
        row.revealed = true
        concealedSentences.remove(row.example.sentence)
    }

    private func rebuild() {
        // Dựng lại cả cây khi card đổi. Vá từng section lúc stream phức tạp hơn lợi ích:
        // filter, lớp che, cloze và wrap chip đều gắn với hàng cũ.
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        exampleRows = []
        filterPills = []
        confusablePairs = []
        wrappingStacks = []

        addSection(makeHero())
        if !card.meanings.isEmpty { addSection(makeMeanings()) }
        if !card.synonyms.isEmpty { addSection(makeWordList(title: "SYNONYMS", words: card.synonyms)) }
        if !card.antonyms.isEmpty { addSection(makeWordList(title: "ANTONYMS", words: card.antonyms)) }
        if !card.examples.isEmpty { addSection(makeExamples()) }
        if !card.confusables.isEmpty { addSection(makeConfusables()) }
        if !card.familyForms.isEmpty { addSection(makeFamily()) }
        if !card.collocations.isEmpty { addSection(makeCollocations()) }
        if !card.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addSection(makeMnemonic())
        }
        if card.cloze != nil { addSection(makeCloze()) }
        applyExampleFilter()
        restoreClozeFeedback()
    }

    private func addSection(_ view: NSView) {
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(view)
        pinWidth(view, to: stack)
    }

    private func makeHero() -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.setHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.setHuggingPriority(.defaultLow, for: .horizontal)

        let headword = NSTextField(labelWithString: card.headword)
        headword.font = .systemFont(ofSize: scaled(23), weight: .bold)
        headword.textColor = .labelColor
        headword.alignment = .left
        headword.setContentHuggingPriority(.required, for: .horizontal)
        headword.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        enableLearnTextSelection(headword)
        row.addArrangedSubview(headword)

        if !card.pronunciation.isEmpty {
            let ipa = NSTextField(labelWithString: card.pronunciation)
            ipa.font = .monospacedSystemFont(ofSize: scaled(13), weight: .regular)
            ipa.textColor = .secondaryLabelColor
            ipa.setContentHuggingPriority(.required, for: .horizontal)
            enableLearnTextSelection(ipa)
            row.addArrangedSubview(ipa)
        }

        speakButton.setContentHuggingPriority(.required, for: .horizontal)
        row.addArrangedSubview(speakButton)
        speakButton.isHidden = onSpeak == nil

        column.addArrangedSubview(row)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        return column
    }

    private func makeMnemonic() -> NSView {
        let section = sectionStack(title: "MNEMONIC")
        let line = wrappingLabel(card.mnemonic, size: 13, color: .labelColor)
        section.addArrangedSubview(line)
        pinWidth(line, to: section)
        return section
    }

    private func makeMeanings() -> NSView {
        let section = sectionStack(title: "MEANING")
        let cardBox = RoundedBox()
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 4
        rows.translatesAutoresizingMaskIntoConstraints = false
        for line in card.meanings {
            let parts = LearnCard.splitMeaning(line)
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 7
            if !parts.pos.isEmpty {
                let pos = NSTextField(labelWithString: parts.pos)
                pos.font = .monospacedSystemFont(ofSize: scaled(11), weight: .semibold)
                pos.textColor = .controlAccentColor
                pos.setContentHuggingPriority(.required, for: .horizontal)
                enableLearnTextSelection(pos)
                row.addArrangedSubview(pos)
            }
            row.addArrangedSubview(wrappingLabel(parts.gloss.isEmpty ? line : parts.gloss, size: 13, color: .labelColor))
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        cardBox.fill(rows)
        section.addArrangedSubview(cardBox)
        pinWidth(cardBox, to: section)
        return section
    }

    private func makeExamples() -> NSView {
        let section = sectionStack(title: "EXAMPLES")
        let tabs = NSStackView()
        tabs.orientation = .horizontal
        tabs.spacing = 5
        tabs.alignment = .centerY
        let items: [(title: String, level: LearnCard.Level?)] = [
            ("All", nil),
            ("Easy", .easy),
            ("Medium", .medium),
            ("Hard", .hard),
        ]
        for item in items {
            let pill = FilterPill(title: item.title, levelRaw: item.level?.rawValue ?? "all")
            pill.onPick = { [weak self] raw in self?.selectFilter(raw) }
            filterPills.append(pill)
            tabs.addArrangedSubview(pill)
        }
        section.addArrangedSubview(tabs)
        pinWidth(tabs, to: section)

        let cardBox = RoundedBox()
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        for (index, example) in card.examples.enumerated() {
            let row = ExampleRow(example: example, headword: card.headword, showDivider: index > 0)
            row.revealed = !concealedSentences.contains(example.sentence)
            row.onToggle = { [weak self] sentence, revealed in
                guard let self else { return }
                if revealed { self.concealedSentences.remove(sentence) }
                else { self.concealedSentences.insert(sentence) }
            }
            exampleRows.append(row)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        cardBox.fill(rows)
        section.addArrangedSubview(cardBox)
        pinWidth(cardBox, to: section)
        return section
    }

    private func makeConfusables() -> NSView {
        let section = sectionStack(title: "EASILY CONFUSED")
        let list = NSStackView()
        list.orientation = .vertical
        list.alignment = .width
        list.spacing = 8
        let leftGloss = card.meanings.first.map { LearnCard.splitMeaning($0).gloss } ?? ""
        for item in card.confusables {
            let pair = NSStackView()
            pair.orientation = .horizontal
            pair.alignment = .top
            pair.spacing = 8
            pair.distribution = .fillEqually
            // Cột phải luôn giữ câu tương phản của từ dễ nhầm. Cột trái chỉ lấy ví dụ
            // fallback khi câu đó không chứa từ gốc.
            let contrastHitsHeadword = ConfusableDrillItem.blankOutInflected(
                card.headword, in: item.contrastSentence
            ) != nil
            let leftSentence = contrastHitsHeadword
                ? item.contrastSentence
                : (card.examples.first?.sentence ?? "")
            let rightSentence = item.contrastSentence
            pair.addArrangedSubview(ConfusableSide(
                word: card.headword,
                detail: leftGloss,
                sentence: leftSentence,
                accent: .controlAccentColor
            ))
            pair.addArrangedSubview(ConfusableSide(
                word: item.other,
                detail: item.difference,
                sentence: rightSentence,
                accent: .systemRed
            ))
            confusablePairs.append(pair)
            list.addArrangedSubview(pair)
        }
        section.addArrangedSubview(list)
        pinWidth(list, to: section)
        return section
    }

    private func makeWordList(title: String, words: [LearnCard.FamilyForm]) -> NSView {
        let section = sectionStack(title: title)
        let wrap = WrappingStack(spacing: 6)
        wrappingStacks.append(wrap)
        for word in words {
            let chip = FamilyChip(form: word, actionName: "Look up")
            chip.onPick = { [weak self] picked in self?.onOpenSubtranslate?(picked) }
            wrap.addArrangedSubview(chip)
        }
        section.addArrangedSubview(wrap)
        pinWidth(wrap, to: section)
        return section
    }

    private func makeFamily() -> NSView {
        let section = sectionStack(title: "WORD FAMILY")
        let wrap = WrappingStack(spacing: 6)
        wrappingStacks.append(wrap)
        for form in card.familyForms {
            let chip = FamilyChip(form: form, actionName: "Look up")
            chip.onPick = { [weak self] word in self?.onOpenSubtranslate?(word) }
            wrap.addArrangedSubview(chip)
        }
        section.addArrangedSubview(wrap)
        pinWidth(wrap, to: section)
        return section
    }

    private func makeCollocations() -> NSView {
        let section = sectionStack(title: "COLLOCATIONS")
        let cardBox = RoundedBox()
        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        for (index, item) in card.collocations.enumerated() {
            let row = CollocationRow(phrase: item.phrase, meaning: item.meaning, showDivider: index > 0)
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        cardBox.fill(rows)
        section.addArrangedSubview(cardBox)
        pinWidth(cardBox, to: section)
        return section
    }

    private func makeCloze() -> NSView {
        let section = sectionStack(title: "SELF-CHECK")
        let box = AccentBox()
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 9
        inner.translatesAutoresizingMaskIntoConstraints = false
        if let cloze = card.cloze {
            let blank = LearnCard.ClozeQuestion.hint(for: cloze.answer)
            let text = cloze.prompt.contains("___")
                ? cloze.prompt.replacingOccurrences(of: "___", with: blank)
                : cloze.hintedPrompt
            let field = wrappingLabel(text, size: 13, color: .labelColor)
            field.alignment = .left
            inner.addArrangedSubview(field)
            pinWidth(field, to: inner)
        }
        let row = NSStackView(views: [answerField, checkButton])
        row.orientation = .horizontal
        row.spacing = 7
        row.alignment = .centerY
        answerField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        inner.addArrangedSubview(row)
        pinWidth(row, to: inner)
        inner.addArrangedSubview(feedbackLabel)
        pinWidth(feedbackLabel, to: inner)
        box.fill(inner)
        section.addArrangedSubview(box)
        pinWidth(box, to: section)
        return section
    }

    private func sectionStack(title: String) -> NSStackView {
        let header = NSTextField(labelWithString: "")
        header.drawsBackground = false
        header.isBezeled = false
        header.isEditable = false
        header.isSelectable = false
        header.lineBreakMode = .byClipping
        header.usesSingleLineMode = true
        header.maximumNumberOfLines = 1
        header.baseWritingDirection = .leftToRight
        header.setContentHuggingPriority(.required, for: .horizontal)
        header.setContentCompressionResistancePriority(.required, for: .horizontal)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        header.attributedStringValue = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: scaled(10.5), weight: .bold),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .kern: 0.9,
            .paragraphStyle: paragraph,
        ])
        header.alignment = .left
        (header.cell as? NSTextFieldCell)?.alignment = .left

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [header, spacer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.userInterfaceLayoutDirection = .leftToRight

        let section = NSStackView(views: [row])
        section.orientation = .vertical
        section.alignment = .width
        section.spacing = 7
        section.userInterfaceLayoutDirection = .leftToRight
        pinWidth(row, to: section)
        return section
    }

    private func pinWidth(_ view: NSView, to section: NSStackView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: section.widthAnchor).isActive = true
    }

    private func wrappingLabel(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: scaled(size))
        field.textColor = color
        field.alignment = .left
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        enableLearnTextSelection(field)
        return field
    }

    private func scaled(_ base: CGFloat) -> CGFloat {
        TextZoom.size(base)
    }

    private func applyExampleFilter() {
        for row in exampleRows {
            let level = row.example.level
            let visible: Bool
            if let filter = exampleFilter {
                visible = level == filter
            } else {
                visible = true
            }
            row.isHidden = !visible
        }
        refreshChromeColors()
    }

    private func applyConfusableOrientation(width: CGFloat) {
        let wide = width >= 300
        for pair in confusablePairs {
            pair.orientation = wide ? .horizontal : .vertical
            pair.distribution = wide ? .fillEqually : .fill
        }
    }

    private func refreshChromeColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            speakButton.layer?.borderColor = NSColor.separatorColor.cgColor
            paintCheckButton()
            for pill in filterPills {
                let selected = (exampleFilter == nil && pill.levelRaw == "all")
                    || pill.levelRaw == exampleFilter?.rawValue
                pill.isSelected = selected
                pill.paint()
            }
        }
    }

    private func paintCheckButton() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            checkButton.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            checkButton.attributedTitle = NSAttributedString(string: "Check", attributes: [
                .font: NSFont.systemFont(ofSize: scaled(12.5), weight: .semibold),
                .foregroundColor: NSColor.white,
            ])
        }
    }

    private func restoreClozeFeedback() {
        guard let cloze = card.cloze else { return }
        if clozeDidSucceed {
            feedbackLabel.stringValue = "Correct: \(cloze.answer)"
            feedbackLabel.textColor = .systemGreen
            feedbackLabel.isHidden = false
        } else if clozeFailCount >= 2 {
            feedbackLabel.stringValue = "Answer: \(cloze.answer)"
            feedbackLabel.textColor = .systemRed
            feedbackLabel.isHidden = false
        } else if clozeFailCount == 1 {
            feedbackLabel.stringValue = "Not quite. Try again, or check once more to see the answer."
            feedbackLabel.textColor = .systemRed
            feedbackLabel.isHidden = false
        } else {
            feedbackLabel.isHidden = true
        }
    }

    @objc private func speakClicked() {
        onSpeak?()
    }

    private func selectFilter(_ raw: String) {
        exampleFilter = raw == "all" ? nil : LearnCard.Level(rawValue: raw)
        applyExampleFilter()
        onNeedsReflow?()
    }

    @objc private func checkClicked() {
        guard let cloze = card.cloze else { return }
        let input = answerField.stringValue
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            feedbackLabel.isHidden = true
            return
        }
        if cloze.matches(input) {
            clozeDidSucceed = true
            clozeFailCount = 0
            feedbackLabel.stringValue = "Correct: \(cloze.answer)"
            feedbackLabel.textColor = .systemGreen
            feedbackLabel.isHidden = false
        } else if clozeFailCount >= 1 {
            clozeFailCount = 2
            feedbackLabel.stringValue = "Answer: \(cloze.answer)"
            feedbackLabel.textColor = .systemRed
            feedbackLabel.isHidden = false
        } else {
            clozeFailCount = 1
            feedbackLabel.stringValue = "Not quite. Try again, or check once more to see the answer."
            feedbackLabel.textColor = .systemRed
            feedbackLabel.isHidden = false
        }
        onNeedsReflow?()
    }
}

// MARK: - Pieces

/// Borderless image buttons on macOS route the icon through a child image view that
/// swallows clicks. `hitTest` receives a point in the superview, so convert first —
/// comparing `bounds` to that point made the icon unclickable.
final class HitFillButton: NSButton {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

private final class FilterPill: NSView {
    let levelRaw: String
    private let title: String
    var onPick: ((String) -> Void)?
    var isSelected = false {
        didSet { paint() }
    }

    private let label = NSTextField(labelWithString: "")

    init(title: String, levelRaw: String) {
        self.title = title
        self.levelRaw = levelRaw
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = title
        label.font = .systemFont(ofSize: TextZoom.size(10.5))
        label.alignment = .center
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        paint()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let text = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: TextZoom.size(10.5))])
        return NSSize(width: ceil(text.width) + 16, height: 20)
    }

    override func mouseDown(with event: NSEvent) {
        onPick?(levelRaw)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    override func layout() {
        super.layout()
        paint()
    }

    func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            if isSelected {
                layer?.backgroundColor = NSColor.labelColor.cgColor
                label.textColor = NSColor.windowBackgroundColor
            } else {
                layer?.backgroundColor = NSColor.clear.cgColor
                label.textColor = NSColor.secondaryLabelColor
            }
        }
    }
}

private class RoundedBox: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
    }

    override func layout() {
        super.layout()
        paint()
    }

    func fill(_ content: NSView) {
        subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 9),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
            layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }
}

private final class AccentBox: RoundedBox {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintAccent()
    }

    override func layout() {
        super.layout()
        paintAccent()
    }

    private func paintAccent() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
        }
    }
}

/// Vẽ bóng chữ bị smear, không phải một thanh xám đặc, để lớp che vẫn trông như bản dịch.
private final class SpoilerVeil: NSView {
    var spoilerText = ""
    var spoilerFont: NSFont = .systemFont(ofSize: 13)

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !spoilerText.isEmpty else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 16
            shadow.shadowOffset = .zero
            shadow.shadowColor = NSColor.secondaryLabelColor.withAlphaComponent(0.32)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: spoilerFont,
                .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.06),
                .shadow: shadow,
            ]
            (spoilerText as NSString).draw(
                with: bounds,
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
        }
    }
}

private final class ExampleRow: NSView {
    let example: LearnCard.LeveledExample
    var onToggle: ((String, Bool) -> Void)?
    var revealed = true {
        didSet { applyReveal() }
    }

    private let translation = NSTextField(wrappingLabelWithString: "")
    private let veil = SpoilerVeil()
    private var levelTag: NSTextField?

    init(example: LearnCard.LeveledExample, headword: String, showDivider: Bool) {
        self.example = example
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let sentence = NSTextField(wrappingLabelWithString: "")
        sentence.translatesAutoresizingMaskIntoConstraints = false
        sentence.attributedStringValue = Self.highlighted(example.sentence, headword: headword)
        sentence.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        enableLearnTextSelection(sentence)

        let tag = NSTextField(labelWithString: example.level.displayLabel.uppercased())
        tag.font = .systemFont(ofSize: TextZoom.size(9.5), weight: .bold)
        tag.wantsLayer = true
        tag.layer?.cornerRadius = 4
        tag.alignment = .center
        tag.translatesAutoresizingMaskIntoConstraints = false
        tag.isHidden = example.level == .unspecified
        self.levelTag = tag

        let line = NSStackView(views: tag.isHidden ? [sentence] : [tag, sentence])
        line.orientation = .horizontal
        line.alignment = .firstBaseline
        line.spacing = 6
        line.translatesAutoresizingMaskIntoConstraints = false

        translation.stringValue = example.translation
        translation.font = .systemFont(ofSize: TextZoom.size(12.5))
        translation.textColor = Self.translationColor
        translation.translatesAutoresizingMaskIntoConstraints = false
        translation.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        translation.isHidden = example.translation.isEmpty
        enableLearnTextSelection(translation)

        veil.translatesAutoresizingMaskIntoConstraints = false
        veil.spoilerFont = .systemFont(ofSize: TextZoom.size(12.5))
        veil.isHidden = example.translation.isEmpty

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.isHidden = !showDivider

        addSubview(divider)
        addSubview(line)
        addSubview(translation)
        addSubview(veil)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: showDivider ? 8 : 2),
            translation.leadingAnchor.constraint(equalTo: leadingAnchor),
            translation.trailingAnchor.constraint(equalTo: trailingAnchor),
            translation.topAnchor.constraint(equalTo: line.bottomAnchor, constant: 3),
            translation.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            veil.leadingAnchor.constraint(equalTo: translation.leadingAnchor),
            veil.trailingAnchor.constraint(equalTo: translation.trailingAnchor),
            veil.topAnchor.constraint(equalTo: translation.topAnchor),
            veil.bottomAnchor.constraint(equalTo: translation.bottomAnchor),
        ])
        applyReveal()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paint()
        applyReveal()
    }

    override func layout() {
        super.layout()
        paint()
        applyReveal()
    }

    private func paint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            veil.needsDisplay = true
            guard let tag = levelTag else { return }
            switch example.level {
            case .easy:
                tag.textColor = .systemGreen
                tag.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.14).cgColor
            case .medium:
                tag.textColor = .systemOrange
                tag.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.14).cgColor
            case .hard:
                tag.textColor = .systemRed
                tag.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.14).cgColor
            case .unspecified:
                break
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !translation.isHidden, veil.frame.contains(point) || translation.frame.contains(point) {
            revealed.toggle()
            onToggle?(example.sentence, revealed)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if !translation.isHidden {
            addCursorRect(veil.frame, cursor: .pointingHand)
        }
    }

    private func applyReveal() {
        let spoiler = !revealed && !example.translation.isEmpty
        veil.isHidden = !spoiler
        veil.spoilerText = spoiler ? example.translation : ""
        veil.needsDisplay = true
        // Chữ thật ẩn; veil vẽ bóng chữ bị smear để nhìn ra một dòng dịch, không đọc được.
        translation.textColor = revealed ? Self.translationColor : .clear
    }

    private static var translationColor: NSColor {
        .secondaryLabelColor
    }

    private static func highlighted(_ sentence: String, headword: String) -> NSAttributedString {
        let font = NSFont.systemFont(ofSize: TextZoom.size(13))
        let result = NSMutableAttributedString(string: sentence, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ])
        let mark = NSColor.systemYellow.withAlphaComponent(0.42)
        let bold = NSFont.systemFont(ofSize: TextZoom.size(13), weight: .semibold)
        for range in ConfusableDrillItem.highlightRanges(of: headword, in: sentence) {
            let nsRange = NSRange(range, in: sentence)
            result.addAttribute(.backgroundColor, value: mark, range: nsRange)
            result.addAttribute(.font, value: bold, range: nsRange)
        }
        return result
    }
}

private final class ConfusableSide: RoundedBox {
    private let rail = NSView()
    private let accent: NSColor
    private var wrappingFields: [NSTextField] = []

    init(word: String, detail: String, sentence: String, accent: NSColor) {
        self.accent = accent
        super.init(frame: .zero)
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 3
        inner.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: word)
        title.font = .systemFont(ofSize: TextZoom.size(13), weight: .bold)
        enableLearnTextSelection(title)
        inner.addArrangedSubview(title)
        if !detail.isEmpty {
            let line = wrappingLine(detail, color: .secondaryLabelColor)
            inner.addArrangedSubview(line)
            line.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }
        if !sentence.isEmpty {
            let rule = NSBox()
            rule.boxType = .separator
            inner.addArrangedSubview(rule)
            rule.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
            let quote = wrappingLine(sentence, color: .labelColor)
            inner.addArrangedSubview(quote)
            quote.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }
        fill(inner)
        wantsLayer = true
        layer?.borderWidth = 1
        // Viền trái màu nhấn, vẽ bằng lớp phụ vì CALayer không có border theo cạnh.
        rail.wantsLayer = true
        rail.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rail)
        NSLayoutConstraint.activate([
            rail.leadingAnchor.constraint(equalTo: leadingAnchor),
            rail.topAnchor.constraint(equalTo: topAnchor),
            rail.bottomAnchor.constraint(equalTo: bottomAnchor),
            rail.widthAnchor.constraint(equalToConstant: 2),
        ])
        paintRail()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintRail()
    }

    override func layout() {
        super.layout()
        paintRail()
        syncWrapWidth()
    }

    fileprivate func syncWrapWidth() {
        for field in wrappingFields {
            let width = field.bounds.width
            guard width > 0, abs(field.preferredMaxLayoutWidth - width) > 0.5 else { continue }
            field.preferredMaxLayoutWidth = width
            field.invalidateIntrinsicContentSize()
        }
    }

    private func wrappingLine(_ text: String, color: NSColor) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: TextZoom.size(12))
        field.textColor = color
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        enableLearnTextSelection(field)
        wrappingFields.append(field)
        return field
    }

    private func paintRail() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            rail.layer?.backgroundColor = accent.cgColor
        }
    }
}

private final class FamilyChip: NSView {
    var onPick: ((String) -> Void)?
    private let form: String
    private let titleLabel = NSTextField(labelWithString: "")
    private let glossLabel = NSTextField(labelWithString: "")

    init(form: LearnCard.FamilyForm, actionName: String = "Learn") {
        self.form = form.form
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        toolTip = "\(actionName) \(form.form)"
        setAccessibilityLabel("\(actionName) \(form.form)")

        let (pos, gloss) = LearnCard.splitMeaning(form.gloss)
        let title = NSMutableAttributedString(string: form.form, attributes: [
            .font: NSFont.systemFont(ofSize: TextZoom.size(12), weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ])
        if !pos.isEmpty {
            title.append(NSAttributedString(string: " \(pos)", attributes: [
                .font: NSFont.systemFont(ofSize: TextZoom.size(10.5)),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]))
        }
        titleLabel.attributedStringValue = title
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        glossLabel.stringValue = gloss
        glossLabel.font = .systemFont(ofSize: TextZoom.size(11.5))
        glossLabel.textColor = .secondaryLabelColor
        glossLabel.drawsBackground = false
        glossLabel.isBezeled = false
        glossLabel.isHidden = gloss.isEmpty
        glossLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(titleLabel)
        var pins: [NSLayoutConstraint] = [
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
        ]
        if gloss.isEmpty {
            pins.append(titleLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5))
        } else {
            addSubview(glossLabel)
            pins.append(contentsOf: [
                glossLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                glossLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
                glossLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 1),
                glossLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            ])
        }
        NSLayoutConstraint.activate(pins)
        paintChip()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        paintChip()
    }

    override func layout() {
        super.layout()
        paintChip()
    }

    private func paintChip() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.cgColor
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onPick?(form)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override var intrinsicContentSize: NSSize {
        let title = titleLabel.attributedStringValue.size()
        let gloss = glossLabel.isHidden
            ? .zero
            : (glossLabel.stringValue as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: TextZoom.size(11.5)),
            ])
        return NSSize(
            width: ceil(max(title.width, gloss.width)) + 18,
            height: glossLabel.isHidden ? 24 : 38
        )
    }
}

private final class CollocationRow: NSView {
    init(phrase: String, meaning: String, showDivider: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let phraseField = NSTextField(wrappingLabelWithString: phrase)
        phraseField.font = .systemFont(ofSize: TextZoom.size(13), weight: .semibold)
        phraseField.alignment = .left
        phraseField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        enableLearnTextSelection(phraseField)

        let meaningField = NSTextField(wrappingLabelWithString: meaning)
        meaningField.font = .systemFont(ofSize: TextZoom.size(12.5))
        meaningField.textColor = .secondaryLabelColor
        meaningField.alignment = .left
        meaningField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        meaningField.isHidden = meaning.isEmpty
        enableLearnTextSelection(meaningField)

        let column = NSStackView(views: meaning.isEmpty ? [phraseField] : [phraseField, meaningField])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 2
        column.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.isHidden = !showDivider

        addSubview(divider)
        addSubview(column)
        NSLayoutConstraint.activate([
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            divider.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: showDivider ? 8 : 2),
            column.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}

/// Hàng chip tự xuống dòng khi hết chiều ngang.
private final class WrappingStack: NSView {
    override var isFlipped: Bool { true }
    private let spacing: CGFloat
    private var chips: [NSView] = []
    private var preparedWidth: CGFloat = 0

    init(spacing: CGFloat) {
        self.spacing = spacing
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    func prepare(forWidth width: CGFloat) {
        preparedWidth = width
        if bounds.width < 1 {
            setFrameSize(NSSize(width: width, height: max(bounds.height, 1)))
        }
        invalidateIntrinsicContentSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func addArrangedSubview(_ view: NSView) {
        chips.append(view)
        addSubview(view)
        invalidateIntrinsicContentSize()
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        let width = max(bounds.width, preparedWidth)
        for chip in chips {
            let size = chip.intrinsicContentSize
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            chip.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    override var intrinsicContentSize: NSSize {
        let width = bounds.width > 1 ? bounds.width : (preparedWidth > 1 ? preparedWidth : 280)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for chip in chips {
            let size = chip.intrinsicContentSize
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return NSSize(width: NSView.noIntrinsicMetric, height: y + rowHeight)
    }
}

/// Labels on the structured card must be selectable so the floating phrase bar can attach.
private func enableLearnTextSelection(_ field: NSTextField) {
    field.isSelectable = true
    field.isEditable = false
    field.focusRingType = .none
}
