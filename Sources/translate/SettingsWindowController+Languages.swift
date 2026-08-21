// SettingsWindowController: language/target-language table CRUD and datasource.
import AppKit

extension SettingsWindowController {
    func languageGroup(title: String, table: NSTableView, buttons: NSStackView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        let scroll = scrollView(for: table)
        let group = NSStackView(views: [label, scroll, buttons])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 8
        scroll.widthAnchor.constraint(equalTo: group.widthAnchor).isActive = true
        return group
    }

    func scrollView(for documentView: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = documentView
        return scroll
    }

    func integerFormatter(minimum: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = NSNumber(value: minimum)
        return formatter
    }

    func configureLanguageTable(_ table: NSTableView, identifier: String) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = "Language"
        table.addTableColumn(column)
        table.headerView = nil
        table.delegate = self
        table.dataSource = self
        table.usesAlternatingRowBackgroundColors = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === languagesTable ? workingConfig.languages.count : workingConfig.targetLanguages.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let value = tableView === languagesTable
            ? workingConfig.languages[row]
            : workingConfig.targetLanguages[row]
        let field = NSTextField(string: value)
        field.identifier = tableColumn?.identifier
        field.tag = row
        field.delegate = self
        return field
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field.identifier?.rawValue == "languages" || field.identifier?.rawValue == "targetLanguages"
        else { return }
        updateLanguage(field)
    }

    private func updateLanguage(_ field: NSTextField) {
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if field.identifier?.rawValue == "languages", workingConfig.languages.indices.contains(field.tag) {
            workingConfig.languages[field.tag] = value
        } else if workingConfig.targetLanguages.indices.contains(field.tag) {
            workingConfig.targetLanguages[field.tag] = value
        }
        reloadLanguagePopups()
    }

    @objc func addSourceLanguage() {
        workingConfig.languages.append("New Language")
        languagesTable.reloadData()
        let row = workingConfig.languages.count - 1
        languagesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        languagesTable.editColumn(0, row: row, with: nil, select: true)
    }

    @objc func removeSourceLanguage() {
        guard workingConfig.languages.indices.contains(languagesTable.selectedRow) else { return }
        workingConfig.languages.remove(at: languagesTable.selectedRow)
        languagesTable.reloadData()
        reloadLanguagePopups()
    }

    @objc func addTargetLanguage() {
        workingConfig.targetLanguages.append("New Language")
        targetLanguagesTable.reloadData()
        let row = workingConfig.targetLanguages.count - 1
        targetLanguagesTable.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        targetLanguagesTable.editColumn(0, row: row, with: nil, select: true)
    }

    @objc func removeTargetLanguage() {
        guard workingConfig.targetLanguages.indices.contains(targetLanguagesTable.selectedRow) else { return }
        workingConfig.targetLanguages.remove(at: targetLanguagesTable.selectedRow)
        targetLanguagesTable.reloadData()
        reloadLanguagePopups()
    }
}
