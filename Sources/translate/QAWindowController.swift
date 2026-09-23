import AppKit

/// Standalone Q&A window: the same multi-turn conversation as the popover's Q&A pane, but in a
/// regular focused window (like Study) so it survives the popover closing. Context is the
/// source/translation snapshot taken when the window was opened.
@MainActor
final class QAWindowController: NSWindowController, NSWindowDelegate {
    struct Context {
        let source: String
        let result: String
        let sourceLang: String
        let targetLang: String
        let parentContext: String?
    }

    var translator: Translator?
    var onWindowClosed: (() -> Void)?

    private var context: Context?
    private let section = QAPaneSection()
    private let contextLabel = NSTextField(wrappingLabelWithString: "")
    private let inputField = NSTextField(frame: .zero)
    private let modelBox = NSComboBox()
    private static let recentModelsKey = "local.ninh.ntranslate.askRecentModels"
    private var request: RequestHandle?
    private var generation = 0

    init() {
        let window = AskWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ask"
        window.minSize = NSSize(width: 380, height: 360)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.onNewChat = { [weak self] in self?.clearConversation() }
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        contextLabel.font = .systemFont(ofSize: 12)
        contextLabel.textColor = .secondaryLabelColor
        contextLabel.maximumNumberOfLines = 4
        contextLabel.lineBreakMode = .byTruncatingTail
        contextLabel.isSelectable = true

        let textView = section.textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true

        let scroll = section.scrollView
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = textView

        inputField.placeholderString = "Ask a question about this translation..."
        inputField.font = .systemFont(ofSize: 14)
        inputField.bezelStyle = .roundedBezel
        inputField.target = self
        inputField.action = #selector(submit(_:))

        let copyButton = NSButton(image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy transcript")!, target: self, action: #selector(copyTranscript))
        copyButton.bezelStyle = .texturedRounded
        copyButton.toolTip = "Copy transcript"
        let clearButton = NSButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear conversation")!, target: self, action: #selector(clearConversation))
        clearButton.bezelStyle = .texturedRounded
        clearButton.toolTip = "Clear conversation (Cmd+N)"

        modelBox.font = .systemFont(ofSize: 12)
        modelBox.placeholderString = "Model"
        modelBox.toolTip = "Model used for Ask. Default comes from Settings > Ask Model."
        modelBox.completes = true
        modelBox.widthAnchor.constraint(equalToConstant: 170).isActive = true

        let separator = NSBox()
        separator.boxType = .separator
        let inputRow = NSStackView(views: [modelBox, inputField, copyButton, clearButton])
        inputRow.spacing = 6

        for view in [contextLabel, separator, scroll, inputRow] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            contextLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            contextLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            contextLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            separator.topAnchor.constraint(equalTo: contextLabel.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            inputRow.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 10),
            inputRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            inputRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            inputRow.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            inputField.heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
        ])
    }

    /// Opens (or re-targets) the window. A new context starts a fresh conversation; `turns`
    /// carries over whatever the popover pane already had.
    func show(context: Context, turns: [QAPaneSection.Turn], draft: String = "") {
        if self.context?.source != context.source || self.context?.result != context.result || !turns.isEmpty {
            resetConversation()
            turns.filter { !$0.isPending }.forEach {
                section.appendQuestion($0.question, placeholder: "")
                section.completeLastTurn(with: $0.answer, failed: $0.failed)
            }
        }
        self.context = context
        contextLabel.stringValue = context.result.isEmpty
            ? "No translation context"
            : "\(context.source)\n\u{2192} \(context.result)"
        if !draft.isEmpty { inputField.stringValue = draft }
        reloadModels()
        render()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(inputField)
    }

    @objc private func submit(_ sender: NSTextField) {
        let question = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, let context else { return }
        guard let translator else {
            section.appendQuestion(question, placeholder: "")
            section.completeLastTurn(with: "API key is not configured", failed: true)
            render()
            return
        }

        request?.cancel()
        generation += 1
        let current = generation
        let history = section.completedTurns
        let model = modelBox.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty { rememberModel(model) }
        section.appendQuestion(question, placeholder: "Answering...")
        sender.stringValue = ""
        render()

        request = translator.ask(
            question,
            sourceText: context.source,
            translatedText: context.result,
            sourceLang: context.sourceLang,
            targetLang: context.targetLang,
            history: history,
            parentContext: context.parentContext,
            model: model.isEmpty ? nil : model,
            onPartial: { [weak self] partial in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.section.updateLastAnswer(partial)
                    self.render()
                }
            }
        ) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.request = nil
                switch result {
                case let .success(answer):
                    self.section.completeLastTurn(with: answer)
                case let .failure(error):
                    let message = PopoverFeedback.userFacingError(error)
                    self.section.completeLastTurn(with: message, failed: message != PopoverFeedback.stopped)
                }
                self.render()
            }
        }
    }

    /// Recent models first; the Settings model is always offered. The box keeps the last pick.
    private func reloadModels() {
        let recent = UserDefaults.standard.stringArray(forKey: Self.recentModelsKey) ?? []
        let config = translator?.config
        let fallback = (config?.askModel.isEmpty == false ? config?.askModel : config?.model) ?? ""
        var items = recent
        if !fallback.isEmpty, !items.contains(fallback) { items.append(fallback) }
        modelBox.removeAllItems()
        modelBox.addItems(withObjectValues: items)
        if modelBox.stringValue.isEmpty { modelBox.stringValue = items.first ?? "" }
    }

    private func rememberModel(_ model: String) {
        var recent = UserDefaults.standard.stringArray(forKey: Self.recentModelsKey) ?? []
        recent.removeAll { $0 == model }
        recent.insert(model, at: 0)
        UserDefaults.standard.set(Array(recent.prefix(8)), forKey: Self.recentModelsKey)
        reloadModels()
    }

    private func render() {
        section.render(
            font: .systemFont(ofSize: 14),
            questionColor: .labelColor,
            answerColor: .labelColor,
            pendingColor: .secondaryLabelColor,
            errorColor: .systemRed
        )
        section.textView.scrollToEndOfDocument(nil)
    }

    private func resetConversation() {
        request?.cancel()
        request = nil
        generation += 1
        section.removeAllTurns()
    }

    @objc private func copyTranscript() {
        guard !section.transcriptText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(section.transcriptText, forType: .string)
    }

    @objc private func clearConversation() {
        resetConversation()
        render()
        window?.makeFirstResponder(inputField)
    }

    func windowWillClose(_ notification: Notification) {
        request?.cancel()
        request = nil
        generation += 1
        onWindowClosed?()
    }
}

/// Cmd+N clears the chat. The key window sees key equivalents before the main menu, so this wins
/// over Study's "Learn New Words" while Ask is in front.
final class AskWindow: NSWindow {
    var onNewChat: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "n" {
            onNewChat?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
