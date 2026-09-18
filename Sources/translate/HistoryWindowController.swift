import AppKit
import AVFoundation

enum HistoryTimeRange: CaseIterable {
    case all, today, hours24, week, month

    func cutoff(from now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .all: return nil
        case .today: return calendar.startOfDay(for: now)
        case .hours24: return now.addingTimeInterval(-86_400)
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        }
    }
}

/// Card row. The card is painted by the row view itself, so hover and selection only
/// change a fill colour instead of restyling a nested view.
private final class HistoryCellView: NSView {
    let actionStack = NSStackView()
}

private final class HistoryRowView: NSTableRowView {
    static let cardInset = NSEdgeInsets(top: 5, left: 2, bottom: 5, right: 2)
    /// Same gap on all four sides between the card edge and its content.
    static let cardPadding: CGFloat = 12

    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            refresh()
        }
    }

    override var selectionHighlightStyle: NSTableView.SelectionHighlightStyle {
        get { .none }
        set {}
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {}

    override var isSelected: Bool {
        didSet { refresh() }
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
        let rect = bounds.insetBy(dx: Self.cardInset.left, dy: Self.cardInset.top)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)

        let fill: NSColor
        if isSelected {
            fill = .controlAccentColor.withAlphaComponent(0.18)
        } else if isHovered {
            fill = .quaternaryLabelColor.withAlphaComponent(0.10)
        } else {
            fill = .quaternaryLabelColor.withAlphaComponent(0.05)
        }
        fill.setFill()
        path.fill()

        (isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.7) : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func refresh() {
        needsDisplay = true
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        refresh()
    }
}

/// One tracking area on the table instead of one per row: a per-row area stops firing
/// `mouseExited` while the rows scroll under a still cursor, which leaves rows stuck hovered.
private final class HoverTableView: NSTableView {
    private var hoveredRow = -1

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        syncHover()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(-1)
    }

    /// Called on scroll too, where no mouse event arrives but the row under the cursor changed.
    func syncHover() {
        guard let window, window.isKeyWindow else { setHovered(-1); return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(point) && visibleRect.contains(point) ? row(at: point) : -1)
    }

    private func setHovered(_ newRow: Int) {
        guard newRow != hoveredRow else { return }
        let previous = hoveredRow
        hoveredRow = newRow
        for index in [previous, newRow] where index >= 0 {
            (rowView(atRow: index, makeIfNecessary: false) as? HistoryRowView)?.isHovered = index == newRow
        }
    }
}

private extension TranslationMode {
    var accentColor: NSColor {
        switch self {
        case .learn: .systemPurple
        case .translate: .systemGreen
        case .proofread: .systemOrange
        }
    }
}

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, @preconcurrency AVAudioPlayerDelegate {
    private let store: TranslationHistoryStore
    private let onOpenRecord: ((TranslationRecord) -> Void)?
    private let tableView = HoverTableView()
    private let searchField = NSSearchField()
    private let filterSegmentedControl = NSSegmentedControl(labels: ["History", "Saved"], trackingMode: .selectOne, target: nil, action: nil)
    private let timeSegmentedControl = NSSegmentedControl(labels: ["All", "Today", "24h", "Week", "Month"], trackingMode: .selectOne, target: nil, action: nil)
    private let countLabel = NSTextField(labelWithString: "")
    private let exportButton = NSButton()
    private let deleteVisibleButton = NSButton()
    private var audioPlayer: AVAudioPlayer?
    private(set) var filteredRecords: [TranslationRecord] = []

    static func filter(records: [TranslationRecord], query: String, savedOnly: Bool, timeRange: HistoryTimeRange? = nil, now: Date = Date(), calendar: Calendar = .current) -> [TranslationRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return records.filter { record in
            if savedOnly && !record.isSaved { return false }
            if let cutoff = timeRange?.cutoff(from: now, calendar: calendar), max(record.timestamp, record.openedAt) < cutoff { return false }
            if trimmed.isEmpty { return true }
            return record.sourceText.lowercased().contains(trimmed) || record.resultText.lowercased().contains(trimmed)
        }.sorted {
            $0.openedAt != $1.openedAt ? $0.openedAt > $1.openedAt : $0.timestamp > $1.timestamp
        }
    }

    static func deleteSnapshot(records: [TranslationRecord]) -> (ids: Set<UUID>, count: Int) {
        (Set(records.map(\.id)), records.count)
    }

    init(store: TranslationHistoryStore, onOpenRecord: ((TranslationRecord) -> Void)? = nil) {
        self.store = store
        self.onOpenRecord = onOpenRecord
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Translation History"
        window.setFrameAutosaveName("TranslationHistoryWindow")

        super.init(window: window)
        window.delegate = self
        configureContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showHistory() {
        reloadHistory()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let loadError = store.loadError { presentHistoryError(loadError) }
    }

    func reloadHistory() {
        updateFilteredRecords()
        tableView.reloadData()
    }

    private func updateFilteredRecords() {
        let savedOnly = filterSegmentedControl.selectedSegment == 1
        let timeRange: HistoryTimeRange?
        switch timeSegmentedControl.selectedSegment {
        case 0: timeRange = .all
        case 1: timeRange = .today
        case 2: timeRange = .hours24
        case 3: timeRange = .week
        case 4: timeRange = .month
        default: timeRange = .today
        }
        filteredRecords = Self.filter(records: store.records, query: searchField.stringValue, savedOnly: savedOnly, timeRange: timeRange)
        countLabel.stringValue = filteredRecords.count == 1 ? "1 record" : "\(filteredRecords.count) records"
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRecords.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredRecords.indices.contains(row) else { return nil }
        return rowView(for: filteredRecords[row])
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        HistoryRowView()
    }

    @objc private func scrollBoundsChanged() {
        tableView.syncHover()
    }

    @objc private func filterChanged() {
        if filterSegmentedControl.selectedSegment == 1 {
            timeSegmentedControl.selectedSegment = 0
        }
        reloadHistory()
    }

    @objc private func exportTSV() {
        guard let window = window, !filteredRecords.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.tabSeparatedText, .plainText]
        panel.nameFieldStringValue = "NTranslate-Export-\(Date().formatted(date: .numeric, time: .omitted)).tsv"
        panel.prompt = "Export"
        panel.message = "Export \(filteredRecords.count) records to Anki TSV format"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            var tsvLines = ["Front\tBack\tMode\tSourceLang\tTargetLang"]
            for record in self.filteredRecords {
                let cleanSource = record.sourceText
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\n", with: "<br>")
                let cleanResult = record.resultText
                    .replacingOccurrences(of: "\t", with: " ")
                    .replacingOccurrences(of: "\n", with: "<br>")
                tsvLines.append("\(cleanSource)\t\(cleanResult)\t\(record.mode.displayName)\t\(record.sourceLanguage)\t\(record.targetLanguage)")
            }
            let tsvContent = tsvLines.joined(separator: "\n")
            do {
                try tsvContent.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.presentError(title: "Export Failed", message: error.localizedDescription)
            }
        }
    }

    @objc private func confirmDeleteVisible() {
        guard let window = window, !filteredRecords.isEmpty else { return }
        let snapshot = Self.deleteSnapshot(records: filteredRecords)
        let alert = NSAlert()
        alert.messageText = "Delete \(snapshot.count) records?"
        alert.informativeText = "This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            do {
                try self.store.remove(recordIDs: snapshot.ids)
                self.reloadHistory()
            } catch {
                self.presentError(title: "Delete Failed", message: error.localizedDescription)
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) == searchField {
            reloadHistory()
        }
    }

    private func configureContent() {
        guard let window else { return }

        let contentHost = NSView()
        window.contentView = contentHost

        filterSegmentedControl.selectedSegment = 0
        filterSegmentedControl.target = self
        filterSegmentedControl.action = #selector(filterChanged)
        filterSegmentedControl.setImage(
            NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "History"),
            forSegment: 0
        )
        filterSegmentedControl.setImage(
            NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: "Saved"),
            forSegment: 1
        )

        timeSegmentedControl.selectedSegment = 1
        timeSegmentedControl.target = self
        timeSegmentedControl.action = #selector(filterChanged)

        searchField.delegate = self
        searchField.placeholderString = "Search history..."
        searchField.target = self
        searchField.action = #selector(filterChanged)

        exportButton.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Export to TSV/Anki")
        exportButton.toolTip = "Export to TSV (Anki format)"
        exportButton.target = self
        exportButton.action = #selector(exportTSV)
        exportButton.bezelStyle = .regularSquare
        exportButton.isBordered = false
        exportButton.imageScaling = .scaleProportionallyUpOrDown

        deleteVisibleButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete visible records")
        deleteVisibleButton.target = self
        deleteVisibleButton.action = #selector(confirmDeleteVisible)
        deleteVisibleButton.bezelStyle = .regularSquare
        deleteVisibleButton.isBordered = false
        deleteVisibleButton.imageScaling = .scaleProportionallyUpOrDown

        countLabel.font = .systemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = .tertiaryLabelColor

        let topBar = NSStackView(views: [searchField, filterSegmentedControl, exportButton, deleteVisibleButton])
        topBar.orientation = .horizontal
        topBar.spacing = 8
        topBar.alignment = .centerY
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let filterBar = NSStackView(views: [timeSegmentedControl, spacer, countLabel])
        filterBar.orientation = .horizontal
        filterBar.spacing = 8
        filterBar.alignment = .centerY
        filterBar.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.rowHeight = 92
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedRecord)
        tableView.setAccessibilityLabel("Translation history")

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        let container = NSStackView(views: [topBar, filterBar, scrollView])
        container.orientation = .vertical
        container.spacing = 10
        container.alignment = .leading
        container.translatesAutoresizingMaskIntoConstraints = false

        contentHost.addSubview(container)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 16),
            container.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor, constant: -16),

            topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            filterBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        contentHost.layoutSubtreeIfNeeded()
        tableView.sizeLastColumnToFit()
        updateFilteredRecords()
    }

    private func rowView(for record: TranslationRecord) -> NSView {
        let view = HistoryCellView()

        let timestamp = record.timestamp.formatted(date: .abbreviated, time: .shortened)
        let savedState = record.isSaved ? "Saved" : "Not saved"
        let mode = record.mode.displayName
        let context = "\(mode), \(timestamp), \(record.sourceLanguage) to \(record.targetLanguage), \(savedState)"
        let summary = Self.summary(for: record)

        let pill = modePill(record.mode)
        let detail = historyTextField(
            "\(timestamp)  ·  \(record.sourceLanguage) → \(record.targetLanguage)",
            accessibilityLabel: "Metadata for \(context)"
        )
        detail.font = .systemFont(ofSize: 11, weight: .regular)
        detail.textColor = .tertiaryLabelColor
        detail.toolTip = detail.stringValue

        let metaStack = NSStackView(views: [pill, detail])
        metaStack.orientation = .horizontal
        metaStack.spacing = 7
        metaStack.alignment = .centerY

        let source = historyTextField(summary.title, accessibilityLabel: "Source text for \(context): \(summary.title)")
        source.font = .systemFont(ofSize: 15, weight: .semibold)
        source.textColor = .labelColor

        let result = historyTextField(summary.body, accessibilityLabel: "Translation for \(context): \(summary.body)")
        result.font = .systemFont(ofSize: 13, weight: .regular)
        result.textColor = .secondaryLabelColor

        source.toolTip = summary.title
        result.toolTip = record.resultText

        let textStack = NSStackView(views: [metaStack, source, result])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4
        [metaStack, source, result].forEach {
            $0.leadingAnchor.constraint(equalTo: textStack.leadingAnchor).isActive = true
            $0.trailingAnchor.constraint(equalTo: textStack.trailingAnchor).isActive = true
        }
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addSubview(textStack)
        view.setAccessibilityLabel("Translation record, \(context), source: \(summary.title), translation: \(record.resultText)")

        let actionStack = view.actionStack
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.orientation = .horizontal
        actionStack.spacing = 4
        actionStack.setContentHuggingPriority(.required, for: .horizontal)
        actionStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        if (try? store.audioExists(for: record.id, kind: .source)) == true {
            actionStack.addArrangedSubview(audioButton(record: record, kind: .source, context: context))
        }
        if (try? store.audioExists(for: record.id, kind: .result)) == true {
            actionStack.addArrangedSubview(audioButton(record: record, kind: .result, context: context))
        }

        let bookmarkBtn = Self.iconButton(
            symbol: record.isSaved ? "bookmark.fill" : "bookmark",
            description: "Toggle saved"
        )
        bookmarkBtn.contentTintColor = record.isSaved ? .controlAccentColor : nil
        bookmarkBtn.target = self
        bookmarkBtn.action = #selector(toggleBookmark(_:))
        bookmarkBtn.identifier = NSUserInterfaceItemIdentifier(record.id.uuidString)
        actionStack.addArrangedSubview(bookmarkBtn)

        let deleteBtn = Self.iconButton(symbol: "trash", description: "Delete record")
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteRecord(_:))
        deleteBtn.identifier = NSUserInterfaceItemIdentifier(record.id.uuidString)
        actionStack.addArrangedSubview(deleteBtn)

        view.addSubview(actionStack)

        let inset = HistoryRowView.cardInset
        let pad = HistoryRowView.cardPadding
        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset.left + pad),
            textStack.topAnchor.constraint(equalTo: view.topAnchor, constant: inset.top + pad),
            textStack.trailingAnchor.constraint(lessThanOrEqualTo: actionStack.leadingAnchor, constant: -10),
            textStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -(inset.bottom + pad)),

            actionStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -(inset.right + pad)),
            actionStack.topAnchor.constraint(equalTo: view.topAnchor, constant: inset.top + pad)
        ])

        return view
    }

    /// Learn records store the whole card in `resultText`; the list shows the term with its
    /// pronunciation on top and the meanings underneath, not the raw `Từ gốc:` block.
    static func summary(for record: TranslationRecord) -> (title: String, body: String) {
        guard record.mode == .learn else { return (record.sourceText, record.resultText) }
        let term = LearnCard.Encounter.split(record.sourceText).term
        let card = LearnCard.parse(record.resultText)
        let title = card.pronunciation.isEmpty ? term : "\(term)   \(card.pronunciation)"
        // A sentence card has no `n./v.` meanings; its first line already carries the gist,
        // so show that instead of every section run together on one line.
        let firstLine = record.resultText.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? record.resultText
        let body = card.meanings.isEmpty ? firstLine : card.meanings.joined(separator: " · ")
        return (title, body)
    }

    private func modePill(_ mode: TranslationMode) -> NSView {
        let label = NSTextField(labelWithString: mode.displayName.uppercased())
        label.font = .systemFont(ofSize: 9, weight: .semibold)
        label.textColor = mode.accentColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 4
        box.layer?.backgroundColor = mode.accentColor.withAlphaComponent(0.16).cgColor
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        box.setContentHuggingPriority(.required, for: .horizontal)
        box.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -2)
        ])
        return box
    }

    private func historyTextField(_ value: String, accessibilityLabel: String, lines: Int = 1) -> NSTextField {
        let line = value.components(separatedBy: .newlines).joined(separator: " ")
        let field = NSTextField(labelWithString: line)
        field.maximumNumberOfLines = lines
        field.lineBreakMode = .byTruncatingTail
        field.alignment = .left
        field.textColor = .labelColor
        field.cell?.wraps = lines > 1
        field.cell?.truncatesLastVisibleLine = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.setAccessibilityLabel(accessibilityLabel)
        return field
    }

    /// Same square hit area for every row action, so the stack never squeezes an icon.
    static func iconButton(symbol: String, description: String) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 24).isActive = true
        button.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return button
    }

    private func audioButton(record: TranslationRecord, kind: TranslationAudioKind, context: String) -> NSButton {
        let title = kind == .source ? "Play source" : "Play result"
        let button = Self.iconButton(symbol: "speaker.wave.2", description: title)
        button.target = self
        button.action = #selector(playAudio(_:))
        button.identifier = NSUserInterfaceItemIdentifier("\(record.id.uuidString)|\(kind.rawValue)")
        button.setAccessibilityLabel("\(title) audio for \(context), record \(record.id.uuidString)")
        return button
    }

    @objc private func playAudio(_ sender: NSButton) {
        guard let parts = sender.identifier?.rawValue.split(separator: "|"), parts.count == 2,
              let recordID = UUID(uuidString: String(parts[0])),
              let kind = TranslationAudioKind(rawValue: String(parts[1]))
        else { return }
        do {
            guard let data = try store.audioData(for: recordID, kind: kind) else {
                presentAudioError("The local audio file is missing.")
                return
            }
            let volume = AppConfig.load().speechVolume
            audioPlayer = try AVAudioPlayer(data: SpeechGain.boosted(data, volume: volume))
            audioPlayer?.delegate = self
            guard audioPlayer?.play() == true else { presentAudioError("The local audio file could not be played."); return }
        } catch {
            presentAudioError(error.localizedDescription)
        }
    }

    @objc private func toggleBookmark(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let id = UUID(uuidString: idString) else { return }
        do {
            try store.toggleSaved(recordID: id)
            reloadHistory()
        } catch {
            presentError(title: "Save Failed", message: error.localizedDescription)
        }
    }

    @objc private func deleteRecord(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let id = UUID(uuidString: idString) else { return }
        do {
            try store.remove(recordID: id)
            reloadHistory()
        } catch {
            presentError(title: "Delete Failed", message: error.localizedDescription)
        }
    }

    @objc private func openSelectedRecord() {
        let row = tableView.clickedRow
        guard row >= 0 else { return }
        openRecord(at: row)
    }

    func openRecord(at index: Int, stopAudio: (() -> Void)? = nil) {
        guard filteredRecords.indices.contains(index) else { return }
        (stopAudio ?? stopAudioPlayback)()
        let record = filteredRecords[index]
        try? store.markOpened(recordID: record.id)
        onOpenRecord?(record)
    }

    func stopAudioPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    func windowWillClose(_ notification: Notification) {
        stopAudioPlayback()
    }

    private func presentAudioError(_ message: String) {
        presentError(title: "Audio Playback Failed", message: message)
    }

    private func presentHistoryError(_ message: String) {
        presentError(title: "Translation History Could Not Be Loaded", message: message)
    }

    private func presentError(title: String, message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer else { return }
        audioPlayer = nil
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audioPlayer else { return }
        audioPlayer = nil
        if let error { presentAudioError(error.localizedDescription) }
    }
}