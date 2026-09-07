// A dedicated screen listing saved reading passages with per-record actions and dialogue creation.
import AppKit

@MainActor
protocol PassagesViewDelegate: AnyObject {
    func passagesViewDidTapBack(_ view: PassagesView)
    func passagesView(_ view: PassagesView, didSelectPassage passage: WeavePassage, key: String)
    func passagesView(_ view: PassagesView, didToggleDone key: String)
    func passagesView(_ view: PassagesView, didDeletePassage key: String)
    func passagesViewDidRequestCreate(_ view: PassagesView)
}

@MainActor
final class PassagesView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: PassagesViewDelegate?

    private var entries: [(key: String, passage: WeavePassage)] = []
    private let table = NSTableView()
    private let backButton = NSButton()
    private let createButton = NSButton()
    private let titleLabel = NSTextField(labelWithString: "Saved Passages")
    private let countLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No saved passages yet.")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    // MARK: - Data

    func reload(entries: [(key: String, passage: WeavePassage)]) {
        self.entries = entries
        table.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        countLabel.stringValue = entries.isEmpty ? "" : "\(entries.count) passages"
    }

    // MARK: - Layout

    private func build() {
        ReviewControls.iconButton(
            backButton,
            symbol: "chevron.backward",
            label: "Back to home (Esc)",
            target: self,
            action: #selector(tapBack)
        )

        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor

        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabelColor

        ReviewControls.actionButton(
            createButton,
            title: "Create Dialogue",
            symbol: "bubble.left.and.bubble.right",
            target: self,
            action: #selector(tapCreate)
        )
        createButton.bezelColor = .controlAccentColor
        createButton.contentTintColor = .white
        // Glass bezels tint the title from the label color, which stays dark on the accent fill.
        createButton.attributedTitle = NSAttributedString(
            string: createButton.title,
            attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
        )
        // The symbol picks up the same label color the title did, so paint it white too.
        createButton.image = createButton.image?.withSymbolConfiguration(
            .init(paletteColors: [.white])
        )

        let headerLeading = NSStackView(views: [backButton, titleLabel, countLabel])
        headerLeading.orientation = .horizontal
        headerLeading.spacing = 10
        headerLeading.alignment = .centerY

        let header = NSStackView(views: [headerLeading, NSView(), createButton])
        header.orientation = .horizontal
        header.spacing = 12
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("passage"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 56
        table.usesAlternatingRowBackgroundColors = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(tapRow)
        table.style = .inset

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13, weight: .regular)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        addSubview(header)
        addSubview(scroll)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            header.heightAnchor.constraint(equalToConstant: 34),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            emptyLabel.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < entries.count else { return nil }
        let entry = entries[row]
        let cellID = NSUserInterfaceItemIdentifier("PassageRowCell")
        let cellView = (tableView.makeView(withIdentifier: cellID, owner: self) as? PassageRowCell) ?? PassageRowCell()
        cellView.identifier = cellID

        let key = entry.key
        let passage = entry.passage
        cellView.configure(entry: entry)
        cellView.onToggleDone = { [weak self] in
            guard let self else { return }
            self.delegate?.passagesView(self, didToggleDone: key)
        }
        cellView.onDelete = { [weak self] in
            guard let self else { return }
            self.delegate?.passagesView(self, didDeletePassage: key)
        }
        cellView.onOpen = { [weak self] in
            guard let self else { return }
            self.delegate?.passagesView(self, didSelectPassage: passage, key: key)
        }
        return cellView
    }

    // MARK: - Actions

    @objc private func tapBack() {
        delegate?.passagesViewDidTapBack(self)
    }

    @objc private func tapCreate() {
        delegate?.passagesViewDidRequestCreate(self)
    }

    @objc private func tapRow() {
        let row = table.selectedRow
        guard row >= 0, row < entries.count else { return }
        let item = entries[row]
        delegate?.passagesView(self, didSelectPassage: item.passage, key: item.key)
    }
}

// MARK: - Cell View

@MainActor
final class PassageRowCell: NSTableCellView {
    var onToggleDone: (() -> Void)?
    var onDelete: (() -> Void)?
    var onOpen: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let doneButton = NSButton()
    private let deleteButton = NSButton()
    private let openButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func configure(entry: (key: String, passage: WeavePassage)) {
        var headline = ReviewWindowController.passageHeadline(entry.passage)
        if headline.isEmpty { headline = entry.passage.words.joined(separator: ", ") }
        titleLabel.stringValue = headline

        let isDone = entry.passage.isDone == true
        titleLabel.textColor = isDone ? .systemGreen : .labelColor

        let date = DateFormatter.localizedString(from: entry.passage.generatedAt, dateStyle: .medium, timeStyle: .short)
        subtitleLabel.stringValue = "\(entry.passage.words.count) words · \(date)"

        let doneSymbol = isDone ? "checkmark.circle.fill" : "circle"
        let doneConfig = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        doneButton.image = NSImage(systemSymbolName: doneSymbol, accessibilityDescription: isDone ? "Mark Not Done" : "Mark Done")?
            .withSymbolConfiguration(doneConfig)
        doneButton.contentTintColor = isDone ? .systemGreen : .secondaryLabelColor
        doneButton.toolTip = isDone ? "Mark as not done" : "Mark as done"
    }

    private func build() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false

        ReviewControls.iconButton(
            doneButton,
            symbol: "circle",
            label: "Toggle Done",
            target: self,
            action: #selector(tapDone)
        )

        ReviewControls.iconButton(
            deleteButton,
            symbol: "trash",
            label: "Delete passage",
            target: self,
            action: #selector(tapDelete)
        )
        deleteButton.contentTintColor = .systemRed

        ReviewControls.iconButton(
            openButton,
            symbol: "chevron.right",
            label: "Open passage",
            target: self,
            action: #selector(tapOpen)
        )

        let textStack = NSStackView(views: [titleLabel, subtitleLabel])
        textStack.orientation = .vertical
        textStack.spacing = 3
        textStack.alignment = .leading
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let actionStack = NSStackView(views: [doneButton, deleteButton, openButton])
        actionStack.orientation = .horizontal
        actionStack.spacing = 8
        actionStack.alignment = .centerY
        actionStack.translatesAutoresizingMaskIntoConstraints = false

        let mainStack = NSStackView(views: [textStack, NSView(), actionStack])
        mainStack.orientation = .horizontal
        mainStack.spacing = 10
        mainStack.alignment = .centerY
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
    }

    @objc private func tapDone() { onToggleDone?() }
    @objc private func tapDelete() { onDelete?() }
    @objc private func tapOpen() { onOpen?() }
}
