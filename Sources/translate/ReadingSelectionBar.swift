import AppKit

/// The floating row of actions that appears over a selection in the reading passage. It carries the
/// same buttons a bubble does, but they act on the selected text rather than on the whole line.
@MainActor
final class ReadingSelectionBar {
    var onSpeak: ((String, Bool) -> Void)?
    var onLearn: ((String) -> Void)?
    var onTranslate: ((String) -> Void)?

    private var text = ""
    private let panel: NSPanel
    private let speakButton = ReadingSelectionBar.button("speaker.wave.2", "Speak selection")
    private let slowButton = ReadingSelectionBar.button("tortoise", "Speak selection slowly")
    private let translateButton = ReadingSelectionBar.button("translate", "Translate selection")
    private let learnButton = ReadingSelectionBar.button("brain.head.profile", "Learn selection")

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 8
        background.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = []
        for (index, button) in [speakButton, slowButton, translateButton, learnButton].enumerated() {
            if index > 0 { views.append(Self.divider()) }
            button.target = self
            views.append(button)
        }
        speakButton.action = #selector(speak)
        slowButton.action = #selector(speakSlow)
        translateButton.action = #selector(translateSelection)
        learnButton.action = #selector(learn)

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -10),
            row.topAnchor.constraint(equalTo: background.topAnchor, constant: 6),
            row.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -6)
        ])
        panel.contentView = background
    }

    /// Puts the bar centred just above the selection, in screen coordinates.
    func show(text: String, over rect: NSRect, in parent: NSWindow?) {
        self.text = text
        panel.layoutIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        panel.setContentSize(size)
        var origin = NSPoint(x: rect.midX - size.width / 2, y: rect.maxY + 6)
        if let screen = parent?.screen ?? NSScreen.main {
            let frame = screen.visibleFrame
            origin.x = min(max(origin.x, frame.minX + 4), frame.maxX - size.width - 4)
            // No room above the line means the bar sits under it instead.
            if origin.y + size.height > frame.maxY { origin.y = rect.minY - size.height - 6 }
        }
        panel.setFrameOrigin(origin)
        if panel.parent == nil, let parent { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    /// True while the pointer is over the bar, which is how a click on it survives the selection
    /// being dropped as the label gives up focus.
    var isPointerInside: Bool {
        panel.isVisible && panel.frame.contains(NSEvent.mouseLocation)
    }

    @objc private func speak() { onSpeak?(text, false) }
    @objc private func speakSlow() { onSpeak?(text, true) }
    @objc private func learn() { onLearn?(text) }
    @objc private func translateSelection() { onTranslate?(text) }

    private static func button(_ symbol: String, _ title: String) -> NSButton {
        let button = NSButton(title: "", target: nil, action: nil)
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 11.5, weight: .regular))
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 20).isActive = true
        button.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return button
    }

    private static func divider() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: 1).isActive = true
        view.heightAnchor.constraint(equalToConstant: 11).isActive = true
        return view
    }
}
