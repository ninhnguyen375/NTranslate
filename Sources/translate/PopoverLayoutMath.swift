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

    /// Splits `available` across multiple stacked sections (e.g. Primary, Subtranslate, QA).
    static func multiStackedSectionHeights(
        available: CGFloat,
        primaryNeeded: CGFloat,
        subNeeded: CGFloat?,
        qaNeeded: CGFloat?,
        gap: CGFloat,
        minPaneHeight: CGFloat
    ) -> (primary: CGFloat, sub: CGFloat?, qa: CGFloat?) {
        var activeCount = 1
        if subNeeded != nil { activeCount += 1 }
        if qaNeeded != nil { activeCount += 1 }

        if activeCount == 1 {
            return (max(minPaneHeight, available), nil, nil)
        }

        let totalGaps = CGFloat(activeCount - 1) * gap
        let usable = max(minPaneHeight * CGFloat(activeCount), available - totalGaps)
        let fairShare = max(minPaneHeight, (usable / CGFloat(activeCount)).rounded(.down))

        var subHeight: CGFloat? = nil
        var qaHeight: CGFloat? = nil

        var remainingUsable = usable

        if let subNeeded {
            let cap = min(remainingUsable - minPaneHeight * CGFloat(activeCount - 1), max(fairShare, subNeeded))
            let allocated = min(max(minPaneHeight, subNeeded), cap)
            subHeight = allocated
            remainingUsable -= allocated
            activeCount -= 1
        }

        if let qaNeeded {
            let cap = min(remainingUsable - minPaneHeight * CGFloat(activeCount - 1), max(fairShare, qaNeeded))
            let allocated = min(max(minPaneHeight, qaNeeded), cap)
            qaHeight = allocated
            remainingUsable -= allocated
            activeCount -= 1
        }

        let primaryHeight = max(minPaneHeight, remainingUsable)
        return (primaryHeight, subHeight, qaHeight)
    }

    /// Splits `available` between the primary pane and an optional subtranslate pane, keeping each
    /// at least `minPaneHeight` and never above what it actually needs. Leftover goes to the primary.
    /// When both panes want more than fits, neither takes more than half so one can't squeeze the
    /// other down to the minimum.
    static func stackedSectionHeights(
        available: CGFloat,
        primaryNeeded: CGFloat,
        secondaryNeeded: CGFloat?,
        gap: CGFloat,
        minPaneHeight: CGFloat
    ) -> (primary: CGFloat, secondary: CGFloat?) {
        guard let secondaryNeeded else { return (max(minPaneHeight, available), nil) }
        let usable = max(minPaneHeight * 2, available - gap)
        let fairShare = max(minPaneHeight, (usable / 2).rounded(.down))
        let cap = min(usable - minPaneHeight, max(fairShare, usable - primaryNeeded))
        let secondary = min(max(minPaneHeight, secondaryNeeded), cap)
        return (max(minPaneHeight, usable - secondary), secondary)
    }

    /// Total Split Prism panel height from fixed chrome + split pane.
    static func splitPrismHeight(
        padding: CGFloat,
        paddingBottom: CGFloat? = nil,
        headerHeight: CGFloat,
        statusHeight: CGFloat,
        headerGap: CGFloat,
        splitPaneHeight: CGFloat,
        qaInputHeight: CGFloat = 0,
        footerGap: CGFloat,
        bottomBarHeight: CGFloat
    ) -> CGFloat {
        let bottom = paddingBottom ?? padding
        let qaAddition = qaInputHeight > 0 ? (qaInputHeight + 12) : 0
        return padding
            + headerHeight
            + statusHeight
            + headerGap
            + splitPaneHeight
            + qaAddition
            + footerGap
            + bottomBarHeight
            + bottom
    }
}
