import AppKit

enum PopoverLayoutMath {
    static func measuredTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let contentWidth = max(100, width)
        let storage = NSTextStorage(attributedString: text.length == 0 ? NSAttributedString(string: " ") : text)
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    static func clickIsInsidePanel(click: NSPoint, panelFrame: NSRect, padding: CGFloat = 2) -> Bool {
        panelFrame.insetBy(dx: -padding, dy: -padding).contains(click)
    }

    static func inputHeight(
        text: String,
        font: NSFont,
        inset: NSSize,
        lineFragmentPadding: CGFloat,
        minHeight: CGFloat,
        maxHeight: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let contentWidth = max(100, width - 20 - inset.width * 2 - lineFragmentPadding * 2)
        let storage = NSTextStorage(string: text.isEmpty ? " " : text)
        storage.addAttribute(.font, value: font, range: NSRange(location: 0, length: storage.length))
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = lineFragmentPadding
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        let measured = ceil(layoutManager.usedRect(for: container).height + inset.height * 2)
        return min(max(minHeight, measured), maxHeight)
    }

    /// Equal left/right pane widths for Split Prism; leftover pixel goes to the right pane.
    static func splitPaneWidth(contentWidth: CGFloat, divider: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let usable = max(0, contentWidth - divider)
        let left = floor(usable / 2)
        return (left, usable - left)
    }

    /// Shared dual-pane body height, clamped between min and max.
    static func splitPaneHeight(
        sourceMeasured: CGFloat,
        resultMeasured: CGFloat,
        paneHeaderHeight: CGFloat,
        minPaneHeight: CGFloat,
        maxPaneHeight: CGFloat
    ) -> CGFloat {
        let needed = paneHeaderHeight + max(sourceMeasured, resultMeasured)
        return min(max(minPaneHeight, needed), maxPaneHeight)
    }

    /// Total Split Prism panel height from fixed chrome + split pane.
    static func splitPrismHeight(
        padding: CGFloat,
        paddingBottom: CGFloat? = nil,
        headerHeight: CGFloat,
        statusHeight: CGFloat,
        headerGap: CGFloat,
        splitPaneHeight: CGFloat,
        footerGap: CGFloat,
        bottomBarHeight: CGFloat
    ) -> CGFloat {
        let bottom = paddingBottom ?? padding
        return padding
            + headerHeight
            + statusHeight
            + headerGap
            + splitPaneHeight
            + footerGap
            + bottomBarHeight
            + bottom
    }
}
