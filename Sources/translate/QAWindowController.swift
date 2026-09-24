import AppKit

/// Standalone Q&A window: the same multi-turn conversation as the popover's Q&A pane, but in a
/// regular focused window (like Study) so it survives the popover closing. Plain chat: it never
/// takes the popover's translation or conversation as context.
@MainActor
final class QAWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {

    var translator: Translator?
    var onWindowClosed: (() -> Void)?

    private let section = QAPaneSection()
    private let inputField = AskInputView(frame: .zero)
    private let inputScroll = NSScrollView()
    private lazy var inputHeight = inputScroll.heightAnchor.constraint(equalToConstant: 28)
    private let modelBox = NSComboBox()
    private static let recentModelsKey = "local.ninh.ntranslate.askRecentModels"
    private static let webSearchKey = "local.ninh.ntranslate.askWebSearch"
    private let webSearchBox = NSButton(checkboxWithTitle: "Web search", target: nil, action: nil)
    private let attachmentStrip = NSStackView()
    /// PNG data of images pasted into the composer, sent with the next question.
    private var attachments: [Data] = []
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

        // Enter sends, Shift+Enter inserts a newline; box grows up to 6 lines then scrolls.
        inputField.setValue("Ask anything...", forKey: "placeholderString")
        inputField.font = .systemFont(ofSize: 14)
        inputField.isRichText = false
        inputField.allowsUndo = true
        inputField.drawsBackground = false
        inputField.textContainerInset = NSSize(width: 4, height: 5)
        inputField.isVerticallyResizable = true
        inputField.autoresizingMask = [.width]
        inputField.textContainer?.widthTracksTextView = true
        inputField.delegate = self
        inputField.onPasteImages = { [weak self] images in self?.addAttachments(images) }
        inputScroll.documentView = inputField
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.borderType = .noBorder
        inputScroll.drawsBackground = false

        modelBox.font = .systemFont(ofSize: 11)
        modelBox.controlSize = .small
        modelBox.placeholderString = "Model"
        modelBox.toolTip = "Model used for Ask. Default comes from Settings > Ask Model."
        modelBox.completes = true
        modelBox.widthAnchor.constraint(equalToConstant: 150).isActive = true

        let copyButton = Self.toolbarButton("doc.on.doc", tip: "Copy transcript", target: self, action: #selector(copyTranscript))
        let clearButton = Self.toolbarButton("trash", tip: "Clear conversation (Cmd+N)", target: self, action: #selector(clearConversation))
        let sendButton = Self.toolbarButton("arrow.up.circle.fill", tip: "Send (Return)", target: self, action: #selector(sendClicked), size: 20)
        sendButton.contentTintColor = .controlAccentColor

        webSearchBox.font = .systemFont(ofSize: 11)
        webSearchBox.controlSize = .small
        webSearchBox.toolTip = "Let the model search and read the web when it needs to"
        webSearchBox.state = UserDefaults.standard.bool(forKey: Self.webSearchKey) ? .on : .off
        webSearchBox.target = self
        webSearchBox.action = #selector(webSearchToggled)

        attachmentStrip.orientation = .horizontal
        attachmentStrip.spacing = 6
        attachmentStrip.isHidden = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let toolbar = NSStackView(views: [modelBox, webSearchBox, spacer, copyButton, clearButton, sendButton])
        toolbar.spacing = 10
        toolbar.alignment = .centerY

        // Composer card: input on top, controls tucked into a quiet row underneath.
        let card = ComposerCardView()
        let cardStack = NSStackView(views: [attachmentStrip, inputScroll, toolbar])
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 6
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)
        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            toolbar.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
            inputScroll.widthAnchor.constraint(equalTo: cardStack.widthAnchor),
        ])

        for view in [scroll, card] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            card.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            card.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            inputHeight,
        ])
    }

    private static func toolbarButton(_ symbol: String, tip: String, target: AnyObject, action: Selector, size: CGFloat = 13) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))!
        let button = NSButton(image: image, target: target, action: action)
        button.isBordered = false
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tip
        return button
    }

    @objc private func sendClicked() { submit() }

    @objc private func webSearchToggled() {
        UserDefaults.standard.set(webSearchBox.state == .on, forKey: Self.webSearchKey)
    }

    private func addAttachments(_ images: [NSImage]) {
        attachments += images.compactMap(Self.pngData)
        renderAttachments()
    }

    @objc private func removeAttachment(_ sender: NSButton) {
        guard attachments.indices.contains(sender.tag) else { return }
        attachments.remove(at: sender.tag)
        renderAttachments()
    }

    private func renderAttachments() {
        attachmentStrip.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (index, data) in attachments.enumerated() {
            let thumb = NSImageView(image: NSImage(data: data) ?? NSImage())
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 6
            thumb.layer?.masksToBounds = true
            thumb.translatesAutoresizingMaskIntoConstraints = false
            let remove = Self.toolbarButton("xmark.circle.fill", tip: "Remove image", target: self, action: #selector(removeAttachment(_:)), size: 14)
            remove.tag = index
            remove.translatesAutoresizingMaskIntoConstraints = false
            let cell = NSView()
            cell.addSubview(thumb)
            cell.addSubview(remove)
            NSLayoutConstraint.activate([
                cell.widthAnchor.constraint(equalToConstant: 56),
                cell.heightAnchor.constraint(equalToConstant: 56),
                thumb.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                thumb.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                thumb.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                thumb.bottomAnchor.constraint(equalTo: cell.bottomAnchor),
                remove.topAnchor.constraint(equalTo: cell.topAnchor),
                remove.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
            ])
            attachmentStrip.addArrangedSubview(cell)
        }
        attachmentStrip.isHidden = attachments.isEmpty
    }

    /// PNG capped at 2048 px on the long side; full-size Retina screenshots only waste tokens.
    private static func pngData(_ image: NSImage) -> Data? {
        guard var cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, 2048 / CGFloat(max(cg.width, cg.height)))
        if scale < 1,
           let context = CGContext(data: nil, width: Int(CGFloat(cg.width) * scale), height: Int(CGFloat(cg.height) * scale),
                                   bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            cg = context.makeImage() ?? cg
        }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    /// Opens the window; the conversation persists across opens until cleared.
    func show() {
        reloadModels()
        render()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(inputField)
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)),
              !(NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false) else { return false }
        submit()
        return true
    }

    func textDidChange(_ notification: Notification) {
        guard let layout = inputField.layoutManager, let container = inputField.textContainer else { return }
        layout.ensureLayout(for: container)
        let lineHeight = layout.defaultLineHeight(for: inputField.font ?? .systemFont(ofSize: 14))
        let textHeight = layout.usedRect(for: container).height + inputField.textContainerInset.height * 2 + 4
        inputHeight.constant = min(max(textHeight, 28), lineHeight * 6 + 14)
    }

    private func submit() {
        let question = inputField.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = attachments
        let webSearch = webSearchBox.state == .on
        guard !question.isEmpty || !images.isEmpty else { return }
        let shown = images.isEmpty ? question
            : question + (question.isEmpty ? "" : "\n") + "[\(images.count) image\(images.count == 1 ? "" : "s")]"
        guard let translator else {
            section.appendQuestion(shown, placeholder: "")
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
        section.appendQuestion(shown, placeholder: "Answering...")
        inputField.string = ""
        attachments = []
        renderAttachments()
        textDidChange(Notification(name: NSText.didChangeNotification))
        render()

        let onPartial: @Sendable (String) -> Void = { [weak self] partial in
            Task { @MainActor in
                guard let self, self.generation == current else { return }
                self.section.updateLastAnswer(partial)
                self.render()
            }
        }
        let completion: @Sendable (Result<String, Error>) -> Void = { [weak self] result in
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
        // Plain text keeps streaming; images or web tools go through the non-streaming tool loop.
        if images.isEmpty && !webSearch {
            request = translator.chat(question, history: history, model: model.isEmpty ? nil : model,
                                      onPartial: onPartial, completion: completion)
        } else {
            request = translator.chatWithTools(
                question.isEmpty ? "Describe the attached image." : question,
                images: images, history: history, model: model.isEmpty ? nil : model,
                webTools: webSearch, onStatus: { onPartial("\($0)...") }, completion: completion
            )
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

/// Composer input that turns pasted images into attachments instead of inline text.
final class AskInputView: NSTextView {
    var onPasteImages: (([NSImage]) -> Void)?

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        // Copied files also carry their icon as an image; only take real image content.
        let isFile = pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        let images = pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage] ?? []
        let fileImages = (pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["public.image"],
        ]) as? [URL] ?? []).compactMap(NSImage.init(contentsOf:))
        let picked = isFile ? fileImages : images
        guard !picked.isEmpty else { return super.paste(sender) }
        onPasteImages?(picked)
    }
}

/// Rounded composer background; drawn rather than layer-backed so system colors follow light/dark.
private final class ComposerCardView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}
