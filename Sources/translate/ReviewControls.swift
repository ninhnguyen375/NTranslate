// Chrome shared by every review screen. Kept in its own file so a standalone check in `Scripts/`
// can compile it without pulling in `ReviewSessionView` and the rest of the review stack.
import AppKit

/// AppKit lays out scroll documents from the bottom unless the view says otherwise.
@MainActor
final class ReviewFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Button styling shared by every review screen, so one change of look lands everywhere.
@MainActor
enum ReviewControls {
    static let iconSize: CGFloat = 20

    static let toolButtonSide: CGFloat = 30

    /// Shared square icon button: no fill, rounded border, symbol centred.
    static func toolButton(_ button: SquareToolButton, symbol: String, label: String, target: AnyObject, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        // smallSquare keeps alignment insets at zero, so the drawn layer matches the square frame.
        button.bezelStyle = .smallSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 7
        button.layer?.borderWidth = 1
        LayerAppearance.paint(button) { $0.borderColor = NSColor.separatorColor.cgColor }
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.target = target
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: toolButtonSide).isActive = true
        button.heightAnchor.constraint(equalToConstant: toolButtonSide).isActive = true
    }

    static func iconButton(_ button: NSButton, symbol: String, label: String, target: AnyObject, action: Selector) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(configuration)
        button.isBordered = false
        button.target = target
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.imageScaling = .scaleProportionallyUpOrDown
        button.contentTintColor = .secondaryLabelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
        button.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
    }

    /// Colours only the title, icon and border; the bezel stays the same as its neighbours.
    static func tint(_ button: NSButton, _ color: NSColor) {
        button.contentTintColor = color
        // The glass bezel ignores the tint for template symbols, so the colour is baked into the image.
        button.image = button.image?.withSymbolConfiguration(.init(paletteColors: [color]))
        button.attributedTitle = NSAttributedString(string: button.title, attributes: [
            .foregroundColor: color,
            .font: button.font ?? .systemFont(ofSize: 13, weight: .medium)
        ])
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.layer?.borderWidth = 1
        LayerAppearance.paint(button) { $0.borderColor = color.withAlphaComponent(0.6).cgColor }
    }

    /// Hairline border so a glass button stays visible on a white Light-mode window.
    static func outline(_ button: NSButton) {
        button.wantsLayer = true
        button.layer?.borderWidth = 1
        LayerAppearance.paint(button) { $0.borderColor = NSColor.separatorColor.cgColor }
    }

    static func actionButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        target: AnyObject,
        action: Selector,
        key: String? = nil
    ) {
        button.title = "  " + title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.target = target
        button.action = action
        if let key { button.keyEquivalent = key }
    }
}
