import AppKit

/// The five primary action buttons (Images | Proofread | Learn | Translate | Ask). Shared by the
/// main pane and the subtranslate pane — each instance is wired to its own selectors by
/// `PopoverController.configureActionRow`, and laid out by `layoutActionRow`.
@MainActor
final class ActionRowSection {
    let imagesButton = NSButton(frame: .zero)
    let proofreadButton = NSButton(frame: .zero)
    let learnButton = NSButton(frame: .zero)
    let translateButton = NSButton(frame: .zero)
    let askButton = NSButton(frame: .zero)

    /// Left-to-right order in the row; Ask is pinned to the trailing edge by the layout.
    var buttons: [NSButton] { [imagesButton, proofreadButton, learnButton, translateButton, askButton] }

    var leadingButtons: [(NSButton, CGFloat)] {
        [(translateButton, 72), (learnButton, 88), (proofreadButton, 72), (imagesButton, 92)]
    }

    func applyEnabled(canRun: Bool, copyable: Bool, imagesEnabled: Bool) {
        translateButton.isEnabled = canRun
        learnButton.isEnabled = canRun
        proofreadButton.isEnabled = canRun
        askButton.isEnabled = copyable
        imagesButton.isEnabled = imagesEnabled
    }

    func addToSuperview(_ view: NSView) {
        for button in buttons { view.addSubview(button) }
    }

    func removeFromSuperview() {
        for button in buttons { button.removeFromSuperview() }
    }
}
