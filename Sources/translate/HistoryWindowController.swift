import AppKit
import AVFoundation

@MainActor
final class HistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, @preconcurrency AVAudioPlayerDelegate {
    private let store: TranslationHistoryStore
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let filterSegmentedControl = NSSegmentedControl(labels: ["All history", "Saved words"], trackingMode: .selectOne, target: nil, action: nil)
    private let clearFilterButton = NSButton(title: "Clear Filter", target: nil, action: nil)
    private var audioPlayer: AVAudioPlayer?
    private(set) var filteredRecords: [TranslationRecord] = []

    static func filter(records: [TranslationRecord], query: String, savedOnly: Bool) -> [TranslationRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return records.filter { record in
            if savedOnly && !record.isSaved { return false }
            if trimmed.isEmpty { return true }
            return record.sourceText.lowercased().contains(trimmed) || record.resultText.lowercased().contains(trimmed)
        }
    }

    init(store: TranslationHistoryStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Translation History"
        window.setFrameAutosaveName("TranslationHistoryWindow")
        super.init(window: window)
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
        filteredRecords = Self.filter(records: store.records, query: searchField.stringValue, savedOnly: savedOnly)
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

    @objc private func clearFilter() {
        searchField.stringValue = ""
        filterSegmentedControl.selectedSegment = 0
        reloadHistory()
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) == searchField {
            reloadHistory()
        }
    }

    private func configureContent() {
        guard let window else { return }
        filterSegmentedControl.selectedSegment = 0
        filterSegmentedControl.target = self
        filterSegmentedControl.action = #selector(filterChanged)

        searchField.delegate = self
        searchField.placeholderString = "Search history..."
        searchField.target = self
        searchField.action = #selector(filterChanged)

        clearFilterButton.target = self
        clearFilterButton.action = #selector(clearFilter)
        clearFilterButton.bezelStyle = .rounded

        let topBar = NSStackView(views: [searchField, filterSegmentedControl, clearFilterButton])
        topBar.orientation = .horizontal
        topBar.spacing = 8
        topBar.alignment = .centerY
        topBar.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 150
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel("Translation history")

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView

        let container = NSStackView(views: [topBar, scrollView])
        container.orientation = .vertical
        container.spacing = 8
        container.alignment = .leading
        container.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = container

        NSLayoutConstraint.activate([
            topBar.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            topBar.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            topBar.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
        updateFilteredRecords()
    }

    private func rowView(for record: TranslationRecord) -> NSView {
        let view = NSTableCellView()
        let timestamp = record.timestamp.formatted(date: .abbreviated, time: .shortened)
        let savedState = record.isSaved ? "Saved" : "Not saved"
        let context = "\(timestamp), \(record.sourceLanguage) to \(record.targetLanguage), \(savedState)"
        let metadata = NSTextField(labelWithString: "\(timestamp)  ·  \(record.sourceLanguage) → \(record.targetLanguage)  ·  \(savedState)")
        let source = historyTextField(record.sourceText, accessibilityLabel: "Source text for \(context): \(record.sourceText)")
        let result = historyTextField(record.resultText, accessibilityLabel: "Translation for \(context): \(record.resultText)")
        let text = NSStackView(views: [metadata, source, result])
        text.translatesAutoresizingMaskIntoConstraints = false
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        view.addSubview(text)
        view.setAccessibilityLabel("Translation record, \(context), source: \(record.sourceText), translation: \(record.resultText)")

        let buttons = NSStackView()
        buttons.translatesAutoresizingMaskIntoConstraints = false
        buttons.orientation = .horizontal
        buttons.spacing = 6
        if (try? store.audioExists(for: record.id, kind: .source)) == true {
            buttons.addArrangedSubview(audioButton(record: record, kind: .source, context: context))
        }
        if (try? store.audioExists(for: record.id, kind: .result)) == true {
            buttons.addArrangedSubview(audioButton(record: record, kind: .result, context: context))
        }
        view.addSubview(buttons)

        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            text.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: buttons.leadingAnchor, constant: -8),
            text.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8),
            buttons.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            buttons.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func historyTextField(_ value: String, accessibilityLabel: String) -> NSTextField {
        let field = NSTextField(labelWithString: value)
        field.maximumNumberOfLines = 3
        field.lineBreakMode = .byTruncatingTail
        field.setAccessibilityLabel(accessibilityLabel)
        return field
    }

    private func audioButton(record: TranslationRecord, kind: TranslationAudioKind, context: String) -> NSButton {
        let title = kind == .source ? "Play source" : "Play result"
        let button = NSButton(title: title, target: self, action: #selector(playAudio(_:)))
        button.bezelStyle = .rounded
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
