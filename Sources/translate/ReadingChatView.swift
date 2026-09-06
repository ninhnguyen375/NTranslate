import AppKit

/// The reading passage drawn as a conversation: one bubble per turn, the first speaker on the left
/// and the other on the right, each bubble carrying its own source, translation and speak buttons.
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

    private var bubbles: [BubbleView] = []
    private var globalMode: Mode = .both

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        spacing = 10
        alignment = .leading
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(_ dialogue: ReadingDialogue, words: [String]) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }
        bubbles = []
        for turn in dialogue.turns {
            let bubble = BubbleView(turn: turn, words: words)
            bubble.onSpeak = { [weak self] isSlow in self?.onSpeak?(turn.source, isSlow) }
            bubble.onWord = { [weak self] word in self?.onWord?(word) }
            bubbles.append(bubble)

            // A spacer opposite the bubble is what pushes each speaker to their own side.
            let spacer = NSView()
            spacer.setContentHuggingPriority(.init(1), for: .horizontal)
            let row = NSStackView(views: turn.isFirstSpeaker ? [bubble, spacer] : [spacer, bubble])
            row.orientation = .horizontal
            row.spacing = 0
            row.translatesAutoresizingMaskIntoConstraints = false
            addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
            bubble.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.82).isActive = true
        }
        setGlobalMode(globalMode)
    }

    /// Switching the whole passage also clears every per-bubble choice, so what is on screen always
    /// matches what the toolbar says.
    func setGlobalMode(_ mode: Mode) {
        globalMode = mode
        bubbles.forEach { $0.apply(mode: mode, isOverride: false) }
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
        var onWord: ((String) -> Void)? {
            didSet { sourceLabel.onWord = onWord }
        }
        let source: String

        private let sourceLabel = LinkedLabel(wrappingLabelWithString: "")
        private let translationLabel = NSTextField(wrappingLabelWithString: "")
        private let controls = NSStackView()
        private var modeButtons: [NSButton] = []
        private let speakButton: NSButton
        private let slowButton: NSButton
        private let isFirstSpeaker: Bool

        init(turn: ReadingDialogue.Turn, words: [String]) {
            isFirstSpeaker = turn.isFirstSpeaker
            source = turn.source
            speakButton = Self.smallButton(title: "")
            slowButton = Self.smallButton(title: "")
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false
            wantsLayer = true
            layer?.cornerRadius = 14
            layer?.backgroundColor = (isFirstSpeaker
                ? NSColor.controlBackgroundColor
                : NSColor.controlAccentColor.withAlphaComponent(0.22)).cgColor

            sourceLabel.attributedStringValue = ReadingHighlight.attributed(
                turn.source,
                words: words,
                font: .systemFont(ofSize: 13.5, weight: .regular),
                color: .labelColor,
                linked: true
            )
            sourceLabel.allowsEditingTextAttributes = true
            translationLabel.stringValue = turn.translation
            translationLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
            translationLabel.textColor = .secondaryLabelColor
            translationLabel.isSelectable = true

            for (title, mode) in [("EN", Mode.source), ("VI", .translation), ("EN+VI", .both)] {
                let button = Self.smallButton(title: title)
                button.tag = mode.rawValue
                button.action = #selector(modeClicked(_:))
                button.target = self
                modeButtons.append(button)
                controls.addArrangedSubview(button)
            }
            speakButton.target = self
            speakButton.action = #selector(speakClicked)
            slowButton.target = self
            slowButton.action = #selector(speakSlowClicked)
            controls.addArrangedSubview(speakButton)
            controls.addArrangedSubview(slowButton)
            applySpeech(.play, isSlow: false)
            controls.orientation = .horizontal
            controls.spacing = 4
            controls.translatesAutoresizingMaskIntoConstraints = false

            let stack = NSStackView(views: [sourceLabel, translationLabel, controls])
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 5
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
                stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
                stack.topAnchor.constraint(equalTo: topAnchor, constant: 9),
                stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
                sourceLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
                translationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        func apply(mode: Mode, isOverride: Bool) {
            sourceLabel.isHidden = mode == .translation
            // With no translation to show, the source stays rather than leaving an empty bubble.
            translationLabel.isHidden = mode == .source || translationLabel.stringValue.isEmpty
            if translationLabel.isHidden, mode == .translation { sourceLabel.isHidden = false }
            for button in modeButtons {
                let selected = button.tag == mode.rawValue
                button.contentTintColor = selected ? .controlAccentColor : .tertiaryLabelColor
                button.font = .systemFont(ofSize: 10, weight: selected ? .bold : .regular)
            }
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
            let title = "\(presentation.verb) \(label)"
            button.image = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: title)
            button.imagePosition = .imageOnly
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.isEnabled = presentation.enabled
        }

        @objc private func modeClicked(_ sender: NSButton) {
            guard let mode = Mode(rawValue: sender.tag) else { return }
            apply(mode: mode, isOverride: true)
        }

        @objc private func speakClicked() { onSpeak?(false) }
        @objc private func speakSlowClicked() { onSpeak?(true) }

        private static func smallButton(title: String) -> NSButton {
            let button = NSButton(title: title, target: nil, action: nil)
            button.isBordered = false
            button.font = .systemFont(ofSize: 10, weight: .regular)
            button.contentTintColor = .tertiaryLabelColor
            button.setButtonType(.momentaryChange)
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
}
