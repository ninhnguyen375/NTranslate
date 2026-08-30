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

    static let splitPaneMinRatio: CGFloat = 0.15
    static let splitPaneMaxRatio: CGFloat = 0.85
    static let qaInputGap: CGFloat = 12
    static let actionButtonGap: CGFloat = 5

    /// Chrome below the main split: action row(s) + footer gap + optional Q&A input.
    static func stackedChromeOverhead(
        hasSub: Bool,
        hasQA: Bool,
        bottomBarHeight: CGFloat,
        sectionGap: CGFloat,
        footerGap: CGFloat,
        qaInputHeight: CGFloat
    ) -> CGFloat {
        let actionRows = hasSub ? bottomBarHeight * 2 + sectionGap : bottomBarHeight
        let qaAddition = (hasQA && qaInputHeight > 0) ? qaInputHeight + qaInputGap : 0
        return actionRows + footerGap + qaAddition
    }

    /// Left/right pane widths for Split Prism. `ratio` is the left-pane share of usable width
    /// (0.5 = equal split). Leftover pixel goes to the right pane.
    static func splitPaneWidth(contentWidth: CGFloat, divider: CGFloat, ratio: CGFloat = 0.5) -> (left: CGFloat, right: CGFloat) {
        let usable = max(0, contentWidth - divider)
        let clamped = min(max(ratio, splitPaneMinRatio), splitPaneMaxRatio)
        let left = floor(usable * clamped)
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
    /// Each section is sized to its own content need, independent of the others — leftover room
    /// (when content needs less than `available`) goes to Primary. Only shrinks below what each
    /// needs, proportionally down to `minPaneHeight`, when `available` can't fit them all.
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

        let totalGaps = CGFloat(activeCount - 1) * gap
        let result: (primary: CGFloat, sub: CGFloat?, qa: CGFloat?)
        if activeCount == 1 {
            result = (max(minPaneHeight, available), nil, nil)
        } else {
            let usable = max(minPaneHeight * CGFloat(activeCount), available - totalGaps)
            let neededSum = primaryNeeded + (subNeeded ?? 0) + (qaNeeded ?? 0)

            if usable >= neededSum {
                let leftover = usable - neededSum
                result = (max(minPaneHeight, primaryNeeded + leftover), subNeeded, qaNeeded)
            } else {
                let scale = neededSum > 0 ? usable / neededSum : 0
                func scaled(_ needed: CGFloat) -> CGFloat { max(minPaneHeight, (needed * scale).rounded(.down)) }
                result = (scaled(primaryNeeded), subNeeded.map(scaled), qaNeeded.map(scaled))
            }
        }

        // Min-pane floors can make panes + gaps exceed `available`; clamp so they never overflow.
        let paneSum = result.primary + (result.sub ?? 0) + (result.qa ?? 0)
        let consumed = paneSum + totalGaps
        guard consumed > available, paneSum > 0 else { return result }
        let target = max(0, available - totalGaps)
        let fit = target / paneSum
        return (result.primary * fit, result.sub.map { $0 * fit }, result.qa.map { $0 * fit })
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
        bottomBarHeight: CGFloat,
        hasSub: Bool = false,
        sectionGap: CGFloat = 0
    ) -> CGFloat {
        let bottom = paddingBottom ?? padding
        let chrome = stackedChromeOverhead(
            hasSub: hasSub,
            hasQA: qaInputHeight > 0,
            bottomBarHeight: bottomBarHeight,
            sectionGap: sectionGap,
            footerGap: footerGap,
            qaInputHeight: qaInputHeight
        )
        return padding
            + headerHeight
            + statusHeight
            + headerGap
            + splitPaneHeight
            + chrome
            + bottom
    }
}
