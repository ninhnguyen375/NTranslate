import AppKit

/// Action chip that keeps the size we assign. AppKit calls `sizeToFit` when the button
/// first enters a window, which used to widen Translate over Learn until the next reflow.
final class ActionChipButton: NSButton {
    var lockedSize = NSSize.zero
    /// SF Symbol name so title-only refreshes can rebuild the attributed icon+label.
    var chipSymbol = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        refusesFirstResponder = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        focusRingType = .none
        refusesFirstResponder = true
    }

    override func drawFocusRingMask() {}

    /// Claim the arrow over the chip. Pairs with `SelectableTextView.mouseMoved`, which stops the
    /// text panes from repainting the I-beam outside themselves.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override var intrinsicContentSize: NSSize {
        lockedSize.width > 0 ? lockedSize : super.intrinsicContentSize
    }

    override func sizeToFit() {
        if lockedSize.width > 0 {
            super.setFrameSize(lockedSize)
            return
        }
        super.sizeToFit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        if newSize.width > 0, lockedSize.width > 0 {
            super.setFrameSize(lockedSize)
            return
        }
        super.setFrameSize(newSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if lockedSize.width > 0, !isHidden {
            super.setFrameSize(lockedSize)
        }
    }
}

/// The five primary action buttons (Translate | Learn | Proofread | Images | Ask). Shared by the
/// main pane and the subtranslate pane — each instance is wired to its own selectors by
/// `PopoverController.configureActionRow`, and laid out by `layoutActionRow`.
@MainActor
final class ActionRowSection {
    let imagesButton = ActionChipButton(frame: .zero)
    let proofreadButton = ActionChipButton(frame: .zero)
    let learnButton = ActionChipButton(frame: .zero)
    let translateButton = ActionChipButton(frame: .zero)
    let askButton = ActionChipButton(frame: .zero)
    /// Holds the chips that do not fit the row; hidden while everything fits.
    let overflowButton = ActionChipButton(frame: .zero)

    /// Hairlines drawn between the plain text actions (Learn | Proofread | Images | Ask).
    let dividers: [NSView] = (0..<3).map { _ in
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        return view
    }

    /// Plain text buttons — no bezel, separated by `dividers`.
    var secondaryButtons: [NSButton] { [learnButton, proofreadButton, imagesButton, askButton] }

    /// Left-to-right visual order. Each chip hugs its icon + title.
    var buttons: [NSButton] { [translateButton, learnButton, proofreadButton, imagesButton, askButton] }

    /// Drop these first when the row is too narrow (Images, then Proofread).
    var overflowHideOrder: [NSButton] { [imagesButton, proofreadButton] }

    func applyEnabled(canRun: Bool, copyable: Bool, imagesEnabled: Bool, textActionsEnabled: Bool? = nil) {
        let textOK = textActionsEnabled ?? canRun
        translateButton.isEnabled = canRun
        learnButton.isEnabled = textOK
        proofreadButton.isEnabled = textOK
        askButton.isEnabled = copyable
        imagesButton.isEnabled = imagesEnabled
    }

    func addToSuperview(_ view: NSView) {
        for button in buttons { view.addSubview(button) }
        for divider in dividers { view.addSubview(divider) }
        view.addSubview(overflowButton)
    }

    func removeFromSuperview() {
        for button in buttons { button.removeFromSuperview() }
        for divider in dividers { divider.removeFromSuperview() }
        overflowButton.removeFromSuperview()
    }
}
