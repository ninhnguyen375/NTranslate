// The list behind "Saved Passages": pick one to reopen, or delete the ones no longer wanted.
import AppKit

@MainActor
final class PassageListPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var entries: [(key: String, passage: WeavePassage)] = []
    private let table = NSTableView()
    private let openButton = NSButton()
    private let deleteButton = NSButton()
    private let doneButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "No saved passages yet.")
    private var panel: NSWindow?
    private var host: NSWindow?
    private var onOpen: ((WeavePassage, String) -> Void)?

    /// Shows the sheet over `window`; `onOpen` gets the chosen passage and its cache key.
    func present(over window: NSWindow, onOpen: @escaping (WeavePassage, String) -> Void) {
        self.host = window
        self.onOpen = onOpen
        entries = WeaveCache.entries()

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "Saved Passages"
        let content = NSView()
        panel.contentView = content
        self.panel = panel

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("passage"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 46
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(tapOpen)
        table.style = .inset

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = !entries.isEmpty

        ReviewControls.actionButton(openButton, title: "Open", symbol: "book", target: self, action: #selector(tapOpen))
        ReviewControls.actionButton(deleteButton, title: "Delete", symbol: "trash", target: self, action: #selector(tapDelete))
        ReviewControls.actionButton(doneButton, title: "Mark Done", symbol: "checkmark.circle", target: self, action: #selector(tapDone))
        let closeButton = NSButton()
        ReviewControls.actionButton(closeButton, title: "Close", symbol: "xmark", target: self, action: #selector(tapClose))
        deleteButton.contentTintColor = .systemRed
        openButton.bezelColor = .controlAccentColor
        openButton.contentTintColor = .white

        let buttons = NSStackView(views: [deleteButton, doneButton, NSView(), closeButton, openButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(scroll)
        content.addSubview(emptyLabel)
        content.addSubview(buttons)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -14),
            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            openButton.heightAnchor.constraint(equalToConstant: 34),
            deleteButton.heightAnchor.constraint(equalToConstant: 34),
            doneButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.heightAnchor.constraint(equalToConstant: 34)
        ])

        // The table survives between presentations, so it still holds the rows built last time.
        table.reloadData()
        if !entries.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
        refreshButtons()
        window.beginSheet(panel)
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        // A passage made before titles existed has neither title nor topic; its words name it.
        var headline = ReviewWindowController.passageHeadline(entry.passage)
        if headline.isEmpty { headline = entry.passage.words.joined(separator: ", ") }
        let title = NSTextField(labelWithString: headline)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        let date = DateFormatter.localizedString(from: entry.passage.generatedAt, dateStyle: .medium, timeStyle: .short)
        let subtitle = NSTextField(labelWithString: "\(entry.passage.words.count) words  ·  \(date)")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.spacing = 2
        text.alignment = .leading

        // Both states draw a mark, so a row is never ambiguous about being unread or unstyled.
        let isDone = entry.passage.isDone == true
        let check = NSImageView()
        check.image = NSImage(
            systemSymbolName: isDone ? "checkmark.circle.fill" : "circle",
            accessibilityDescription: isDone ? "Done" : "Not done"
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        check.contentTintColor = isDone ? .systemGreen : .tertiaryLabelColor
        if isDone { title.textColor = .systemGreen }
        check.imageScaling = .scaleProportionallyDown
        check.translatesAutoresizingMaskIntoConstraints = false
        check.widthAnchor.constraint(equalToConstant: 20).isActive = true
        check.heightAnchor.constraint(equalToConstant: 20).isActive = true

        let stack = NSStackView(views: [check, text])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        return stack
    }

    func tableViewSelectionDidChange(_ notification: Notification) { refreshButtons() }

    private func refreshButtons() {
        let row = table.selectedRow
        let hasSelection = row >= 0 && row < entries.count
        openButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        doneButton.isEnabled = hasSelection
        let isDone = hasSelection && entries[row].passage.isDone == true
        doneButton.title = isDone ? "  Mark Not Done" : "  Mark Done"
        doneButton.contentTintColor = isDone ? .systemGreen : .secondaryLabelColor
    }

    // MARK: - Actions

    @objc private func tapOpen() {
        let row = table.selectedRow
        guard row >= 0, row < entries.count else { return }
        let entry = entries[row]
        close()
        onOpen?(entry.passage, entry.key)
    }

    @objc private func tapDelete() {
        let row = table.selectedRow
        guard row >= 0, row < entries.count else { return }
        WeaveCache.delete(key: entries[row].key)
        entries.remove(at: row)
        table.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        if !entries.isEmpty {
            table.selectRowIndexes([min(row, entries.count - 1)], byExtendingSelection: false)
        }
        refreshButtons()
    }

    /// Flips the Done flag on the selected passage and writes it straight back to its cache file.
    @objc private func tapDone() {
        let row = table.selectedRow
        guard row >= 0, row < entries.count else { return }
        var passage = entries[row].passage
        passage.isDone = !(passage.isDone ?? false)
        WeaveCache.store(passage, key: entries[row].key)
        entries[row] = (entries[row].key, passage)
        table.reloadData(forRowIndexes: [row], columnIndexes: [0])
        refreshButtons()
    }

    @objc private func tapClose() { close() }

    private func close() {
        guard let panel, let host else { return }
        host.endSheet(panel)
        self.panel = nil
    }
}
