// A dedicated screen listing saved reading passages with per-record actions and dialogue creation.
import AppKit

@MainActor
protocol PassagesViewDelegate: AnyObject {
    func passagesViewDidTapBack(_ view: PassagesView)
    func passagesView(_ view: PassagesView, didSelectPassage passage: WeavePassage, key: String)
    func passagesView(_ view: PassagesView, didToggleDone key: String)
    func passagesView(_ view: PassagesView, didDeletePassage key: String)
    func passagesView(_ view: PassagesView, didResetCount key: String)
    func passagesViewDidRequestCreate(_ view: PassagesView)
}

@MainActor
final class PassagesView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: PassagesViewDelegate?

    private var entries: [(key: String, passage: WeavePassage)] = []
    private var allEntries: [(key: String, passage: WeavePassage)] = []
    private let groupLabel = NSTextField(labelWithString: "Topic")
    private let groupPopup = NSPopUpButton()
    private let tierLabel = NSTextField(labelWithString: "Tier")
    private let tierPopup = NSPopUpButton()
    private let filterBar = NSStackView()
    private static let allGroupsTitle = "All Topics"
    private static let allTiersTitle = "All Tiers"
    private static let groupKey = "local.ninh.ntranslate.passageGroup"
    private static let tierKey = "local.ninh.ntranslate.passageTier"
    private let table = NSTableView()
    private let backButton = NSButton()
    private let createButton = NSButton()
    private let importButton = NSButton()
    private let skillButton = NSButton()
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
        allEntries = entries
        let selected = groupPopup.titleOfSelectedItem ?? UserDefaults.standard.string(forKey: Self.groupKey) ?? Self.allGroupsTitle
        let groups = Set(entries.compactMap { $0.passage.group }.filter { !$0.isEmpty }).sorted()
        groupPopup.removeAllItems()
        groupPopup.addItems(withTitles: [Self.allGroupsTitle] + groups)
        groupPopup.selectItem(withTitle: groups.contains(selected) ? selected : Self.allGroupsTitle)
        groupLabel.isHidden = groups.isEmpty
        groupPopup.isHidden = groups.isEmpty
        applyFilter()
    }

    private func applyFilter() {
        let selectedGroup = groupPopup.titleOfSelectedItem ?? Self.allGroupsTitle
        let byGroup = selectedGroup == Self.allGroupsTitle ? allEntries : allEntries.filter { $0.passage.group == selectedGroup }
        let selectedTier = tierPopup.titleOfSelectedItem ?? UserDefaults.standard.string(forKey: Self.tierKey) ?? Self.allTiersTitle
        let tiers = Set(byGroup.compactMap { $0.passage.tier }.filter { !$0.isEmpty }).sorted()
        tierPopup.removeAllItems()
        tierPopup.addItems(withTitles: [Self.allTiersTitle] + tiers)
        let activeTier = tiers.contains(selectedTier) ? selectedTier : Self.allTiersTitle
        tierPopup.selectItem(withTitle: activeTier)
        tierLabel.isHidden = tiers.isEmpty
        tierPopup.isHidden = tiers.isEmpty
        filterBar.isHidden = groups.isEmpty && tiers.isEmpty
        let entries = activeTier == Self.allTiersTitle ? byGroup : byGroup.filter { $0.passage.tier == activeTier }
        self.entries = entries
        table.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        countLabel.stringValue = entries.isEmpty ? "" : "\(entries.count) passages"
    }

    private var groups: [String] {
        Set(allEntries.compactMap { $0.passage.group }.filter { !$0.isEmpty }).sorted()
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

        ReviewControls.actionButton(
            importButton,
            title: "Import",
            symbol: "square.and.arrow.down",
            target: self,
            action: #selector(tapImport)
        )

        ReviewControls.actionButton(
            skillButton,
            title: "Add Skill",
            symbol: "wand.and.stars",
            target: self,
            action: #selector(tapAddSkill)
        )
        skillButton.toolTip = "Install the Claude Code skill that builds dialogues from your project"

        for label in [groupLabel, tierLabel] {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .secondaryLabelColor
        }

        groupPopup.target = self
        groupPopup.action = #selector(changeGroup)
        groupPopup.toolTip = "Filter by topic"
        groupPopup.setAccessibilityLabel("Topic")
        groupPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        tierPopup.target = self
        tierPopup.action = #selector(changeTier)
        tierPopup.toolTip = "Filter by tier"
        tierPopup.setAccessibilityLabel("Tier")
        tierPopup.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let headerLeading = NSStackView(views: [backButton, titleLabel, countLabel])
        headerLeading.orientation = .horizontal
        headerLeading.spacing = 10
        headerLeading.alignment = .centerY

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [headerLeading, spacer, skillButton, importButton, createButton])
        header.orientation = .horizontal
        header.spacing = 10
        header.alignment = .centerY
        header.translatesAutoresizingMaskIntoConstraints = false

        filterBar.setViews([groupLabel, groupPopup, tierLabel, tierPopup, NSView()], in: .leading)
        filterBar.orientation = .horizontal
        filterBar.spacing = 10
        filterBar.alignment = .centerY
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        filterBar.setCustomSpacing(6, after: groupLabel)
        filterBar.setCustomSpacing(16, after: groupPopup)
        filterBar.setCustomSpacing(6, after: tierLabel)

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

        let topStack = NSStackView(views: [header, filterBar])
        topStack.orientation = .vertical
        topStack.spacing = 10
        topStack.alignment = .leading
        topStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(topStack)
        addSubview(scroll)
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            topStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            header.widthAnchor.constraint(equalTo: topStack.widthAnchor),
            header.heightAnchor.constraint(equalToConstant: 34),
            filterBar.widthAnchor.constraint(equalTo: topStack.widthAnchor),
            groupPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            tierPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 240),

            scroll.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 10),
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
        cellView.onResetCount = { [weak self] in
            guard let self else { return }
            self.delegate?.passagesView(self, didResetCount: key)
        }
        cellView.onDelete = { [weak self] in
            guard let self else { return }
            self.delegate?.passagesView(self, didDeletePassage: key)
        }
        cellView.onSetTopic = { [weak self] in
            guard let self else { return }
            let alert = NSAlert()
            alert.messageText = "Set Passage Topic"
            alert.informativeText = "Use the same topic to keep related passages together. Leave empty to remove the topic."
            let field = NSComboBox(frame: NSRect(x: 0, y: 0, width: 300, height: 26))
            field.addItems(withObjectValues: Set(self.allEntries.compactMap { $0.passage.group }.filter { !$0.isEmpty }).sorted())
            field.stringValue = passage.group ?? ""
            field.setAccessibilityLabel("Topic")
            alert.accessoryView = field
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn,
                  var updated = WeaveCache.load(key: key) else { return }
            let topic = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.group = topic.isEmpty ? nil : topic
            WeaveCache.store(updated, key: key)
            self.reload(entries: WeaveCache.entries())
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

    @objc private func changeGroup() {
        UserDefaults.standard.set(groupPopup.titleOfSelectedItem, forKey: Self.groupKey)
        applyFilter()
    }

    @objc private func changeTier() {
        UserDefaults.standard.set(tierPopup.titleOfSelectedItem, forKey: Self.tierKey)
        applyFilter()
    }

    @objc private func tapImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Choose a JSON array of passages"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let alert = NSAlert()
        do {
            let count = try WeaveCache.importPassages(from: Data(contentsOf: url))
            reload(entries: WeaveCache.entries())
            alert.messageText = "Imported \(count) passages."
        } catch {
            alert.messageText = "Could not import passages."
            alert.informativeText = error.localizedDescription
        }
        alert.runModal()
    }

    @objc private func tapAddSkill() {
        let alert = NSAlert()
        do {
            try ExtractDialogSkill.install()
            alert.messageText = "Skill installed."
            alert.informativeText = """
            Saved to \(ExtractDialogSkill.fileURL.path).

            1. Open Claude Code in your project folder.
            2. Run /\(ExtractDialogSkill.name) and approve the lesson list.
            3. The lessons land in Saved Passages automatically. Reopen this screen to see them.
            """
            alert.addButton(withTitle: "Copy Command")
            alert.addButton(withTitle: "Done")
            if alert.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("/\(ExtractDialogSkill.name)", forType: .string)
            }
        } catch {
            alert.messageText = "Could not install the skill."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
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
    var onResetCount: (() -> Void)?
    var onOpen: (() -> Void)?
    var onSetTopic: (() -> Void)?
    private let topicButton = NSButton()

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let doneButton = NSButton()
    private let deleteButton = NSButton()
    private let resetCountButton = NSButton()
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
        var parts = ["\(entry.passage.words.count) words", date]
        if let group = entry.passage.group, !group.isEmpty { parts.insert(group, at: 0) }
        let count = entry.passage.count ?? 0
        parts.append(count == 1 ? "Studied 1 time" : "Studied \(count) times")
        if let tier = entry.passage.tier, !tier.isEmpty { parts.insert(tier, at: 0) }
        subtitleLabel.stringValue = parts.joined(separator: ", ")
        resetCountButton.isHidden = count == 0

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
            resetCountButton,
            symbol: "arrow.counterclockwise",
            label: "Reset study count",
            target: self,
            action: #selector(tapResetCount)
        )
        resetCountButton.toolTip = "Reset study count"

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

        ReviewControls.iconButton(topicButton, symbol: "folder", label: "Set topic", target: self, action: #selector(tapTopic))
        let actionStack = NSStackView(views: [topicButton, doneButton, resetCountButton, deleteButton, openButton])
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
    @objc private func tapResetCount() { onResetCount?() }
    @objc private func tapOpen() { onOpen?() }
    @objc private func tapTopic() { onSetTopic?() }
}
