import AppKit

/// The reading passage drawn as a conversation: one bubble per turn, the first speaker on the left
/// and the other on the right, each bubble carrying its own source, translation and speak buttons
/// inside its own frame.
@MainActor
final class ReadingChatView: NSStackView {
    enum Mode: Int {
        case source = 0
        case translation = 1
        case both = 2
    }

    /// Called with the line to read out loud, and whether the slow button asked for it.
    var onSpeak: ((String, Bool) -> Void)?
    /// Called with the practised word behind an underlined term when it is clicked.
    var onWord: ((String) -> Void)?
    /// Called with the line to open in the translate panel's Learn mode.
    var onLearn: ((String) -> Void)?
    /// Called with the line to open in the translate panel's Translate mode.
    var onTranslate: ((String) -> Void)?

    private var bubbles: [BubbleView] = []
    private var globalMode: Mode = .both
    private let selectionBar = ReadingSelectionBar()

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        spacing = 10
        alignment = .leading
        translatesAutoresizingMaskIntoConstraints = false
        selectionBar.onSpeak = { [weak self] text, isSlow in self?.onSpeak?(text, isSlow) }
        selectionBar.onLearn = { [weak self] text in self?.onLearn?(text) }
        selectionBar.onTranslate = { [weak self] text in self?.onTranslate?(text) }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(selectionChanged),
            name: NSTextView.didChangeSelectionNotification,
            object: nil
        )
    }

    /// The bar follows the field editor rather than any one label: a selectable `NSTextField` hands
    /// its text to the window's shared editor, which is what reports the selection.
    @objc private func selectionChanged(_ note: Notification) {
        guard let editor = note.object as? NSTextView,
              let label = (editor.delegate as AnyObject?) as? LinkedLabel,
              label.isDescendant(of: self) else { return }
        let range = editor.selectedRange()
        guard range.length > 0 else {
            // Clicking the bar drops the label's selection, so a click already in flight wins.
            if !selectionBar.isPointerInside { selectionBar.hide() }
            return
        }
        let text = (editor.string as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { selectionBar.hide(); return }
        selectionBar.show(text: text, over: editor.firstRect(forCharacterRange: range, actualRange: nil), in: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(_ dialogue: ReadingDialogue, words: [String]) {
        selectionBar.hide()
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        bubbles = []
        for turn in dialogue.turns {
            let bubble = BubbleView(turn: turn, words: words)
            bubble.onSpeak = { [weak self] isSlow in self?.onSpeak?(turn.source, isSlow) }
            bubble.onWord = { [weak self] word in self?.onWord?(word) }
            bubble.onLearn = { [weak self] in self?.onLearn?(turn.source) }
            bubbles.append(bubble)

            // A spacer opposite the bubble is what pushes each speaker to their own side.
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            let views: [NSView] = turn.isFirstSpeaker ? [bubble, spacer] : [spacer, bubble]
            let row = NSStackView(views: views)
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            row.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        setGlobalMode(globalMode)
        needsLayout = true
    }

    /// Every bubble is as wide as its widest language, so switching the toolbar between source,
    /// translation and both never makes the column jump. The width is settled here rather than in
    /// `show` because the cap follows the window.
    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        let cap = min(bounds.width * 0.74, Self.readableColumn * Self.characterWidth)
        for bubble in bubbles {
            let width = ceil(bubble.preferredWidth(cap: cap))
            if abs(bubble.widthConstraint.constant - width) > 0.5 {
                bubble.widthConstraint.constant = width
            }
        }
    }

    /// Past roughly this many characters a line is tiring to read, however wide the window gets.
    private static let readableColumn: CGFloat = 54
    private static let characterWidth: CGFloat = {
        let font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        return NSAttributedString(string: "0", attributes: [.font: font]).size().width
    }()

    /// Switching the whole passage also clears every per-bubble choice, so what is on screen always
    /// matches what the toolbar says.
    func setGlobalMode(_ mode: Mode) {
        selectionBar.hide()
        globalMode = mode
        bubbles.forEach { $0.apply(global: mode, clearingOverride: true) }
    }

    var currentMode: Mode { globalMode }

    /// Loading, playing and paused belong to one line at one speed; every other button is idle.
    func updateSpeech(line: String?, isSlow: Bool, action: SpeechButtonAction) {
        for bubble in bubbles {
            bubble.applySpeech(bubble.source == line ? action : .play, isSlow: isSlow)
        }
    }

    // MARK: - One turn

    private final class BubbleView: NSView {
        var onSpeak: ((Bool) -> Void)?
        var onLearn: (() -> Void)?
        var onWord: ((String) -> Void)? {
            didSet { sourceLabel.onWord = onWord }
        }
        /// Set while this line is pinned to both languages; clearing it hands the line back to the
        /// toolbar's choice.
        private var isForcedBoth = false
        let source: String
        /// The row of buttons, inside the bubble under a hairline and always visible.
        let controls = NSStackView()
        /// Driven by `ReadingChatView.layout`; see `preferredWidth`.
        private(set) lazy var widthConstraint: NSLayoutConstraint = {
            let constraint = widthAnchor.constraint(equalToConstant: 240)
            constraint.priority = .init(999)
            constraint.isActive = true
            return constraint
        }()

        private let sourceLabel = LinkedLabel(wrappingLabelWithString: "")
        private let textDivider = NSBox()
        private let translationLabel = NSTextField(wrappingLabelWithString: "")
        private let bothButton: NSButton
        private let speakButton: NSButton
        private let slowButton: NSButton
        private let learnButton: NSButton
        private let isFirstSpeaker: Bool
        private var globalMode: Mode = .both

        init(turn: ReadingDialogue.Turn, words: [String]) {
            isFirstSpeaker = turn.isFirstSpeaker
            source = turn.source
            bothButton = Self.smallButton(title: "")
            speakButton = Self.smallButton(title: "")
            slowButton = Self.smallButton(title: "")
            learnButton = Self.smallButton(title: "")
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            layer?.cornerRadius = 14
            layer?.borderWidth = 1
            updateLayerColors()

            sourceLabel.attributedStringValue = ReadingHighlight.attributed(
                turn.source,
                words: words,
                font: .systemFont(ofSize: 13.5, weight: .regular),
                color: .labelColor,
                linked: true
            )
            sourceLabel.allowsEditingTextAttributes = true
            sourceLabel.isSelectable = true
            translationLabel.stringValue = turn.translation
            translationLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
            translationLabel.textColor = .labelColor
            translationLabel.isSelectable = true

            bothButton.target = self
            bothButton.action = #selector(bothClicked)
            speakButton.target = self
            speakButton.action = #selector(speakClicked)
            slowButton.target = self
            slowButton.action = #selector(speakSlowClicked)
            learnButton.target = self
            learnButton.action = #selector(learnClicked)
            symbolize(learnButton, symbol: "brain.head.profile", title: "Learn this line")
            // Each symbol has its own intrinsic width, so the buttons only line up once every cell
            // is the same square. Thin dividers give each action room to breathe.
            let buttonList = [speakButton, slowButton, bothButton, learnButton]
            for (index, button) in buttonList.enumerated() {
                if index > 0 {
                    controls.addArrangedSubview(Self.verticalDivider())
                }
                button.widthAnchor.constraint(equalToConstant: Self.buttonSide).isActive = true
                button.heightAnchor.constraint(equalToConstant: Self.buttonSide).isActive = true
                controls.addArrangedSubview(button)
            }
            applyBothButton()
            applySpeech(.play, isSlow: false)
            controls.orientation = .horizontal
            controls.alignment = .centerY
            controls.spacing = Self.buttonGap
            controls.translatesAutoresizingMaskIntoConstraints = false
            controls.setContentHuggingPriority(.required, for: .horizontal)
            controls.setContentCompressionResistancePriority(.required, for: .horizontal)

            // A spacer on the far side keeps the buttons under the speaker's own edge.
            let pusher = NSView()
            pusher.setContentHuggingPriority(.init(1), for: .horizontal)
            let controlsRow = NSStackView(views: isFirstSpeaker ? [controls, pusher] : [pusher, controls])
            controlsRow.orientation = .horizontal
            controlsRow.spacing = 0

            textDivider.boxType = .separator
            textDivider.translatesAutoresizingMaskIntoConstraints = false

            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false

            let stack = NSStackView(views: [sourceLabel, textDivider, translationLabel, separator, controlsRow])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 5
            stack.setCustomSpacing(6, after: sourceLabel)
            stack.setCustomSpacing(6, after: textDivider)
            stack.setCustomSpacing(7, after: translationLabel)
            stack.setCustomSpacing(4, after: separator)
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
                sourceLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
                textDivider.widthAnchor.constraint(equalTo: stack.widthAnchor),
                translationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
                separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
                controlsRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }

        override func layout() {
            super.layout()
            updateLayerColors()
        }

        private func updateLayerColors() {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = (isFirstSpeaker
                    ? NSColor.labelColor.withAlphaComponent(0.08)
                    : NSColor.controlAccentColor.withAlphaComponent(0.22)).cgColor
                layer?.borderColor = (isFirstSpeaker
                    ? NSColor.separatorColor
                    : NSColor.controlAccentColor.withAlphaComponent(0.35)).cgColor
            }
        }

        private static let padding: CGFloat = 12
        private static let buttonSide: CGFloat = 20
        private static let buttonGap: CGFloat = 8

        private static func verticalDivider() -> NSView {
            let view = VerticalDivider()
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: 1).isActive = true
            view.heightAnchor.constraint(equalToConstant: 11).isActive = true
            return view
        }

        /// The bubble is sized by whichever is widest: the source, the translation, or the row of
        /// buttons. Measuring the hidden language too is what stops the width from moving when the
        /// toolbar switches mode.
        func preferredWidth(cap: CGFloat) -> CGFloat {
            let chrome = Self.padding * 2
            let textCap = max(cap - chrome, 60)
            let widest = max(Self.measure(sourceLabel.attributedStringValue, cap: textCap),
                             Self.measure(translationLabel.attributedStringValue, cap: textCap))
            // 4 buttons + 3 dividers (1pt each) + 6 gaps
            let buttons = Self.buttonSide * 4 + 3 * 1 + Self.buttonGap * 6
            return ReadingBubbleWidth.clamp(text: widest, buttons: buttons, chrome: chrome, cap: cap)
        }

        private static func measure(_ text: NSAttributedString, cap: CGFloat) -> CGFloat {
            guard text.length > 0 else { return 0 }
            let box = NSSize(width: cap, height: .greatestFiniteMagnitude)
            let rect = text.boundingRect(with: box, options: [.usesLineFragmentOrigin, .usesFontLeading])
            // The label pads each line fragment, so the measured text needs the same slack.
            return min(ceil(rect.width) + 4, cap)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func apply(global mode: Mode, clearingOverride: Bool) {
            globalMode = mode
            if clearingOverride { isForcedBoth = false }
            let shown: Mode = isForcedBoth ? .both : mode
            sourceLabel.isHidden = shown == .translation
            // With no translation to show, the source stays rather than leaving an empty bubble.
            translationLabel.isHidden = shown == .source || translationLabel.stringValue.isEmpty
            if translationLabel.isHidden, shown == .translation { sourceLabel.isHidden = false }
            textDivider.isHidden = sourceLabel.isHidden || translationLabel.isHidden
            applyBothButton()
        }

        /// The button is lit only while it overrides the toolbar, so it always reads as "this line
        /// is doing something of its own".
        private func applyBothButton() {
            let title = isForcedBoth ? "Follow the toolbar again" : "Show both languages"
            symbolize(bothButton, symbol: "translate", title: title)
            bothButton.contentTintColor = isForcedBoth ? .controlAccentColor : .secondaryLabelColor
        }

        private func symbolize(_ button: NSButton, symbol: String, title: String) {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 11.5, weight: .regular))
            button.imagePosition = .imageOnly
            button.toolTip = title
            button.setAccessibilityLabel(title)
        }

        /// Only the button that asked for the audio shows its state; the other stays on its idle
        /// symbol, so it is always clear which speed is running.
        func applySpeech(_ action: SpeechButtonAction, isSlow: Bool) {
            style(speakButton, action: action.applies(whenSlow: false, activeIsSlow: isSlow), idle: "speaker.wave.2", label: "line")
            style(slowButton, action: action.applies(whenSlow: true, activeIsSlow: isSlow), idle: "tortoise", label: "line slowly")
        }

        private func style(_ button: NSButton, action: SpeechButtonAction, idle: String, label: String) {
            let presentation: (symbol: String, verb: String, enabled: Bool)
            switch action {
            case .play: presentation = (idle, "Speak", true)
            case .loading: presentation = ("hourglass", "Loading", false)
            case .pause: presentation = ("pause.fill", "Pause", true)
            case .resume: presentation = ("play.fill", "Resume", true)
            }
            symbolize(button, symbol: presentation.symbol, title: "\(presentation.verb) \(label)")
            button.isEnabled = presentation.enabled
        }

        @objc private func bothClicked() {
            isForcedBoth.toggle()
            apply(global: globalMode, clearingOverride: false)
        }

        @objc private func learnClicked() { onLearn?() }

        @objc private func speakClicked() { onSpeak?(false) }
        @objc private func speakSlowClicked() { onSpeak?(true) }

        private static func smallButton(title: String) -> NSButton {
            let button = NSButton(title: title, target: nil, action: nil)
            button.isBordered = false
            button.font = .systemFont(ofSize: 10, weight: .regular)
            button.contentTintColor = .secondaryLabelColor
            button.setButtonType(.momentaryChange)
            button.translatesAutoresizingMaskIntoConstraints = false
            return button
        }
    }

    /// A wrapping label that reports which practised word was clicked. The field editor is not
    /// involved: the click is mapped to a character with the label's own attributed string, so it
    /// works whether or not the label ever takes focus.
    private final class LinkedLabel: NSTextField {
        var onWord: ((String) -> Void)?

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if let word = word(at: point) {
                onWord?(word)
                return
            }
            super.mouseDown(with: event)
        }

        override func resetCursorRects() {
            super.resetCursorRects()
            addCursorRect(bounds, cursor: .arrow)
        }

        private func word(at point: NSPoint) -> String? {
            let storage = NSTextStorage(attributedString: attributedStringValue)
            let container = NSTextContainer(size: NSSize(width: bounds.width, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 2
            let layout = NSLayoutManager()
            layout.addTextContainer(container)
            storage.addLayoutManager(layout)
            layout.ensureLayout(for: container)
            let flipped = NSPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
            let index = layout.characterIndex(for: flipped, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
            guard index < storage.length else { return nil }
            return storage.attribute(ReadingHighlight.wordAttribute, at: index, effectiveRange: nil) as? String
        }
    }

    /// A 1pt wide vertical hairline between buttons, matching the current theme.
    private final class VerticalDivider: NSView {
        init() {
            super.init(frame: .zero)
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer?.backgroundColor = NSColor.separatorColor.cgColor
            }
        }
    }
}
