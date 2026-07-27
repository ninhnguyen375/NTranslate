import AppKit
import AVFoundation

enum HistoryTimeRange: CaseIterable {
    case today, hours24, week, month

    func cutoff(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .today: return calendar.startOfDay(for: now)
        case .hours24: return now.addingTimeInterval(-86_400)
        case .week: return now.addingTimeInterval(-7 * 86_400)
        case .month: return calendar.date(byAdding: .month, value: -1, to: now) ?? .distantPast
        }
    }
}

@MainActor
final class HistoryWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, @preconcurrency AVAudioPlayerDelegate {
    private let store: TranslationHistoryStore
    private let onOpenRecord: ((TranslationRecord) -> Void)?
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let filterSegmentedControl = NSSegmentedControl(labels: ["History", "Saved"], trackingMode: .selectOne, target: nil, action: nil)
    private let timeSegmentedControl = NSSegmentedControl(labels: ["Today", "24h", "Week", "Month"], trackingMode: .selectOne, target: nil, action: nil)
    private let deleteVisibleButton = NSButton()
    private var audioPlayer: AVAudioPlayer?
    private(set) var filteredRecords: [TranslationRecord] = []

    static func filter(records: [TranslationRecord], query: String, savedOnly: Bool, timeRange: HistoryTimeRange? = nil, now: Date = Date(), calendar: Calendar = .current) -> [TranslationRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return records.filter { record in
            if savedOnly && !record.isSaved { return false }
            if let timeRange, record.timestamp < timeRange.cutoff(from: now, calendar: calendar) { return false }
            if trimmed.isEmpty { return true }
            return record.sourceText.lowercased().contains(trimmed) || record.resultText.lowercased().contains(trimmed)
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
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Translation History"
        window.setFrameAutosaveName("TranslationHistoryWindow")

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

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
        case 0: timeRange = .today
        case 1: timeRange = .hours24
        case 2: timeRange = .week
        case 3: timeRange = .month
        default: timeRange = nil
        }
        filteredRecords = Self.filter(records: store.records, query: searchField.stringValue, savedOnly: savedOnly, timeRange: timeRange)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredRecords.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filteredRecords.indices.contains(row) else { return nil }
        return rowView(for: filteredRecords[row])
    }

    @objc private func filterChanged() {
        reloadHistory()
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
        guard let window, let contentLayoutGuide = window.contentLayoutGuide as? NSLayoutGuide else { return }

        let visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 22
        visualEffect.layer?.masksToBounds = true

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

        timeSegmentedControl.selectedSegment = 0
        timeSegmentedControl.target = self
        timeSegmentedControl.action = #selector(filterChanged)

        searchField.delegate = self
        searchField.placeholderString = "Search history..."
        searchField.target = self
        searchField.action = #selector(filterChanged)

        deleteVisibleButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete visible records")
        deleteVisibleButton.target = self
        deleteVisibleButton.action = #selector(confirmDeleteVisible)
        deleteVisibleButton.bezelStyle = .regularSquare
        deleteVisibleButton.isBordered = false
        deleteVisibleButton.imageScaling = .scaleProportionallyUpOrDown

        let topBar = NSStackView(views: [searchField, filterSegmentedControl, timeSegmentedControl, deleteVisibleButton])
        topBar.orientation = .horizontal
        topBar.spacing = 8
        topBar.alignment = .centerY
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.headerView = nil
        tableView.rowHeight = 88
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.intercellSpacing = NSSize(width: 0, height: 8)
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

        let container = NSStackView(views: [topBar, scrollView])
        container.orientation = .vertical
        container.spacing = 16
        container.alignment = .leading
        container.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(container)
        window.contentView = visualEffect

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            container.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
            container.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 16),
            container.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor, constant: -16),

            topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor)
        ])

        visualEffect.layoutSubtreeIfNeeded()
        tableView.sizeLastColumnToFit()
        updateFilteredRecords()
    }

    private func rowView(for record: TranslationRecord) -> NSView {
        let view = NSTableCellView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 16
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.2).cgColor

        let timestamp = record.timestamp.formatted(date: .abbreviated, time: .shortened)
        let savedState = record.isSaved ? "Saved" : "Not saved"
        let context = "\(timestamp), \(record.sourceLanguage) to \(record.targetLanguage), \(savedState)"

        let metadata = historyTextField(
            "\(timestamp)  ·  \(record.sourceLanguage) → \(record.targetLanguage)",
            accessibilityLabel: "Metadata for \(context)"
        )
        metadata.font = .systemFont(ofSize: 11, weight: .medium)
        metadata.textColor = .secondaryLabelColor
        metadata.toolTip = metadata.stringValue

        let source = historyTextField(record.sourceText, accessibilityLabel: "Source text for \(context): \(record.sourceText)")
        source.font = .systemFont(ofSize: 14, weight: .regular)
        let result = historyTextField(record.resultText, accessibilityLabel: "Translation for \(context): \(record.resultText)")
        result.font = .systemFont(ofSize: 14, weight: .semibold)

        source.toolTip = record.sourceText
        result.toolTip = record.resultText

        let textStack = NSStackView(views: [metadata, source, result])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .width
        textStack.spacing = 3
        [metadata, source, result].forEach {
            $0.leadingAnchor.constraint(equalTo: textStack.leadingAnchor).isActive = true
            $0.trailingAnchor.constraint(equalTo: textStack.trailingAnchor).isActive = true
        }
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.addSubview(textStack)
        view.setAccessibilityLabel("Translation record, \(context), source: \(record.sourceText), translation: \(record.resultText)")

        let actionStack = NSStackView()
        actionStack.translatesAutoresizingMaskIntoConstraints = false
        actionStack.orientation = .horizontal
        actionStack.spacing = 8
        actionStack.setContentHuggingPriority(.required, for: .horizontal)
        actionStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        if (try? store.audioExists(for: record.id, kind: .source)) == true {
            actionStack.addArrangedSubview(audioButton(record: record, kind: .source, context: context))
        }
        if (try? store.audioExists(for: record.id, kind: .result)) == true {
            actionStack.addArrangedSubview(audioButton(record: record, kind: .result, context: context))
        }

        let bookmarkBtn = NSButton()
        bookmarkBtn.image = NSImage(systemSymbolName: record.isSaved ? "bookmark.fill" : "bookmark", accessibilityDescription: "Toggle saved")
        bookmarkBtn.isBordered = false
        bookmarkBtn.target = self
        bookmarkBtn.action = #selector(toggleBookmark(_:))
        bookmarkBtn.identifier = NSUserInterfaceItemIdentifier(record.id.uuidString)
        actionStack.addArrangedSubview(bookmarkBtn)

        let deleteBtn = NSButton()
        deleteBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete record")
        deleteBtn.isBordered = false
        deleteBtn.target = self
        deleteBtn.action = #selector(deleteRecord(_:))
        deleteBtn.identifier = NSUserInterfaceItemIdentifier(record.id.uuidString)
        actionStack.addArrangedSubview(deleteBtn)
        actionStack.widthAnchor.constraint(equalToConstant: actionStack.fittingSize.width).isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)
        view.addSubview(actionStack)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            textStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            textStack.trailingAnchor.constraint(equalTo: separator.leadingAnchor, constant: -12),
            textStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),

            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12),
            separator.trailingAnchor.constraint(equalTo: actionStack.leadingAnchor, constant: -12),

            actionStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            actionStack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }

    private func historyTextField(_ value: String, accessibilityLabel: String) -> NSTextField {
        let line = value.components(separatedBy: .newlines).joined(separator: " ")
        let field = NSTextField(labelWithString: line)
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.alignment = .left
        field.cell?.wraps = false
        field.cell?.truncatesLastVisibleLine = true
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.setAccessibilityLabel(accessibilityLabel)
        return field
    }

    private func audioButton(record: TranslationRecord, kind: TranslationAudioKind, context: String) -> NSButton {
        let title = kind == .source ? "Play source" : "Play result"
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: title)
        button.isBordered = false
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
            audioPlayer = try AVAudioPlayer(data: data)
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
        onOpenRecord?(filteredRecords[index])
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