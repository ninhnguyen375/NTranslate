// Popup geometry: split-prism layout, pane sizing, and panel framing/positioning.
import AppKit

extension PopoverController {
    func reflowLayout(reanchorToMouse: Bool = false) {
        guard panel.contentView != nil else { return }
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        layoutSplitPrism(width: width, height: height)
        applyPanelFrame(size: NSSize(width: width, height: height), reanchorToMouse: reanchorToMouse)
        if !selectionFloatingBar.isHidden {
            updateFloatingSelectionBar()
        }
    }

    func layoutSplitPrism(width: CGFloat, height: CGFloat) {
        let L = ChromeLayout.self
        let contentWidth = width - L.padding * 2
        let panes = PopoverLayoutMath.splitPaneWidth(
            contentWidth: contentWidth,
            divider: L.dividerWidth,
            ratio: mainSplitRatio
        )
        let statusH: CGFloat = 0

        let headerY = height - L.padding - L.headerHeight
        let statusY = headerY
        let bottomY = L.paddingBottom
        let mergeQA = mergesQAInput
        let qaH = effectiveQAInputHeight
        let qaY = bottomY
        // Everything under the main split now stacks above the Q&A input: main action row, then the
        // subtranslate pane with its own action row, then the Q&A answer pane.
        let qaAddition = qaH > 0 ? qaH + PopoverLayoutMath.qaInputGap : 0
        let splitY = qaY + qaAddition
        let rowsHeight = PopoverLayoutMath.stackedChromeOverhead(
            hasSub: subSection != nil,
            hasQA: qaH > 0,
            bottomBarHeight: L.bottomBarHeight,
            sectionGap: L.sectionGap,
            footerGap: L.footerGap,
            qaInputHeight: qaH
        ) - qaAddition
        // Pin body under the header so extra panel height grows the pane — never a dead gap.
        let splitTop = (statusH > 0 ? statusY : headerY) - L.headerGap
        // The panel height is already the clamped truth; the split gets exactly what's left over.
        // Measuring again here and taking the larger value is what pushed panes past the chrome.
        let totalSplitHeight = max(0, splitTop - splitY - rowsHeight)
        let heights = PopoverLayoutMath.multiStackedSectionHeights(
            available: totalSplitHeight,
            primaryNeeded: measuredPrimaryPaneHeight(paneWidth: panes.left),
            subNeeded: subSection.map { measuredSubPaneHeight($0, paneWidth: subSectionPanes(contentWidth: contentWidth, mode: $0.mode).left) },
            qaNeeded: qaSection.map { measuredQAPaneHeight($0, paneWidth: contentWidth) },
            gap: L.sectionGap,
            minPaneHeight: stackedMinPaneHeight,
            subGap: L.sectionDividerReserved
        )
        let splitHeight = heights.primary
        let bodyHeight = max(0, splitHeight - L.paneHeaderHeight)

        glassContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
        if let containerHost = glassContainer.contentView {
            containerHost.frame = glassContainer.bounds
        }
        shellGlass.frame = glassContainer.bounds
        chromeHost.frame = shellGlass.bounds
        applySplitHostChrome()

        let chromeIcon = L.chromeIconSize
        let headerIconGap: CGFloat = 8
        closeButton.frame = NSRect(
            x: width - L.padding - chromeIcon,
            y: headerY + (L.headerHeight - chromeIcon) / 2,
            width: chromeIcon,
            height: chromeIcon
        )
        pinButton.frame = NSRect(
            x: closeButton.frame.minX - headerIconGap - chromeIcon,
            y: closeButton.frame.minY,
            width: chromeIcon,
            height: chromeIcon
        )
        historyButton.frame = NSRect(
            x: pinButton.frame.minX - headerIconGap - chromeIcon,
            y: closeButton.frame.minY,
            width: chromeIcon,
            height: chromeIcon
        )
        reviewButton.frame = NSRect(
            x: historyButton.frame.minX - headerIconGap - chromeIcon,
            y: closeButton.frame.minY,
            width: chromeIcon,
            height: chromeIcon
        )
        let badgeSize: CGFloat = 13
        reviewBadgeLabel.frame = NSRect(
            x: reviewButton.frame.maxX - 6,
            y: reviewButton.frame.maxY - 6,
            width: badgeSize,
            height: badgeSize
        )
        let updateX = updateButton.isHidden
            ? reviewButton.frame.minX
            : reviewButton.frame.minX - headerIconGap - chromeIcon
        updateButton.frame = NSRect(
            x: updateX,
            y: closeButton.frame.minY,
            width: chromeIcon,
            height: chromeIcon
        )
        let firstIconMinX = updateButton.isHidden ? reviewButton.frame.minX : updateButton.frame.minX
        let langH = L.languageControlHeight
        let langY = headerY + (L.headerHeight - langH) / 2
        let swapSize = L.swapWidth
        let iconsLeft = firstIconMinX - 12
        // Title takes only what its text needs so the language controls sit right beside it and
        // the leftover header room can hold the hint text.
        var titleWidth = min(118, max(48, ceil(titleLabel.attributedStringValue.size().width) + 8))
        var langWidth = L.languageWidth
        let titleGap: CGFloat = 8
        let needed = titleWidth + titleGap + langWidth + 5 + swapSize + 5 + langWidth
        let available = max(80, iconsLeft - (L.padding + 2))
        if needed > available {
            let overflow = needed - available
            let titleShrink = min(overflow, titleWidth - 48)
            titleWidth -= titleShrink
            let still = overflow - titleShrink
            if still > 0 {
                langWidth = max(58, langWidth - still / 2)
            }
        }
        titleLabel.frame = NSRect(x: L.padding + 2, y: langY, width: titleWidth, height: langH)
        let langX = titleLabel.frame.maxX + titleGap
        sourceLanguageButton.frame = NSRect(x: langX, y: langY, width: langWidth, height: langH)
        swapLanguagesButton.frame = NSRect(
            x: sourceLanguageButton.frame.maxX + 5,
            y: langY,
            width: swapSize,
            height: langH
        )
        targetLanguageButton.frame = NSRect(
            x: swapLanguagesButton.frame.maxX + 5,
            y: langY,
            width: langWidth,
            height: langH
        )
        applyStatusOverlay(headerY: langY, headerHeight: langH, iconsLeft: iconsLeft)
        styleLanguageButtonTitle(sourceLanguageButton, language: sourceLanguageSelection)
        styleLanguageButtonTitle(targetLanguageButton, language: targetLanguageSelection)
        applyControlCornerRadius(sourceLanguageButton)
        applyControlCornerRadius(targetLanguageButton)
        applyControlCornerRadius(swapLanguagesButton)
        applyControlCornerRadius(closeButton)
        applyControlCornerRadius(pinButton)
        applyControlCornerRadius(historyButton)
        applyControlCornerRadius(reviewButton)
        applyControlCornerRadius(updateButton)
        LiquidGlassChrome.clipToShell(glassContainer)
        LiquidGlassChrome.clipToShell(shellGlass)
        LiquidGlassChrome.clipToShell(chromeHost)
        LiquidGlassChrome.applyWindowShape(panel)

        // Stacked order from top to bottom: main split -> main action row -> Subtranslate
        // divider -> subtranslate split -> subtranslate action row -> QA -> QA input.
        var currentY = splitY
        if let qa = qaSection, let qaPaneH = heights.qa {
            layoutQASection(qa, x: L.padding, y: currentY, width: contentWidth, height: qaPaneH)
            currentY += qaPaneH + L.sectionGap
        }
        if let sub = subSection, let subH = heights.sub {
            layoutActionRow(sub.actionRow, y: currentY, contentWidth: contentWidth)
            currentY += L.bottomBarHeight + L.footerGap
            layoutSubSection(sub, x: L.padding, y: currentY, width: contentWidth, height: subH, panes: subSectionPanes(contentWidth: contentWidth, mode: sub.mode))
            currentY += subH
            layoutSectionDivider(sub, x: L.padding, y: currentY, width: contentWidth)
            currentY += L.sectionDividerReserved
        }
        let mainRowEnd = layoutActionRow(
            mainActionRow,
            y: currentY,
            contentWidth: contentWidth,
            reservedTrailing: mergeQA ? PopoverLayoutMath.actionButtonGap + mergedQAInputMinWidth : 0
        )
        if mergeQA {
            let fieldX = mainRowEnd + PopoverLayoutMath.actionButtonGap
            qaInputField.frame = NSRect(
                x: fieldX,
                y: currentY,
                width: max(0, L.padding + contentWidth - fieldX),
                height: L.bottomBarHeight
            )
        }
        currentY += L.bottomBarHeight + L.footerGap

        splitHost.frame = NSRect(x: L.padding, y: currentY, width: contentWidth, height: splitHeight)

        sourceCard.frame = NSRect(x: 0, y: 0, width: panes.left, height: splitHeight)
        splitDivider.frame = NSRect(x: panes.left, y: L.padding, width: max(1, L.dividerWidth), height: max(0, splitHeight - L.padding * 2))
        splitDividerGradient?.frame = splitDivider.bounds
        splitHost.addSubview(splitDivider, positioned: .above, relativeTo: nil)
        resultCard.frame = NSRect(x: panes.left + L.dividerWidth, y: 0, width: panes.right, height: splitHeight)

        layoutPaneChrome(
            headerBar: sourceHeaderBar,
            headerLabel: sourceHeaderLabel,
            scrollView: inputScrollView,
            textView: inputTextView,
            trailingIcons: [speakSourceButton, speakSourceSlowButton],
            paneWidth: panes.left,
            bodyHeight: bodyHeight
        )
        layoutPaneChrome(
            headerBar: resultHeaderBar,
            headerLabel: resultHeaderLabel,
            scrollView: textScrollView,
            textView: textView,
            trailingIcons: [speakResultButton, speakResultSlowButton, retryButton, copyButton, saveWordButton],
            paneWidth: panes.right,
            bodyHeight: bodyHeight
        )
        layoutSetupActions(in: resultCard)

        if !mergeQA {
            qaInputField.frame = NSRect(
                x: L.padding,
                y: qaY,
                width: contentWidth,
                height: qaH
            )
        }
        applyQAInputChrome()
    }

    func layoutSetupActions(in resultCard: NSView) {
        let buttons = [setupOpenSettingsButton, setupGrantAccessButton, inPaneRetryButton].filter { !$0.isHidden }
        let barH: CGFloat = buttons.isEmpty ? 0 : ChromeLayout.controlHeight + 2
        if barH > 0 {
            let scroll = textScrollView.frame
            let newH = max(0, scroll.height - barH)
            textScrollView.frame = NSRect(x: scroll.minX, y: scroll.minY + barH, width: scroll.width, height: newH)
            textView.minSize = NSSize(width: 0, height: newH)
        }
        guard !buttons.isEmpty else { return }
        var x: CGFloat = 12
        let y: CGFloat = 8
        let height: CGFloat = 26
        for button in buttons {
            button.sizeToFit()
            let width = max(88, button.frame.width + 12)
            button.frame = NSRect(x: x, y: y, width: width, height: height)
            x += width + 8
        }
    }

    /// Status shares the language-control slot. Hide the popups while a status is up so the
    /// message is readable; no split reflow (statusHeight stays 0).
    func applyStatusOverlay(headerY: CGFloat? = nil, headerHeight: CGFloat? = nil, iconsLeft: CGFloat? = nil) {
        let showing = !statusLabel.isHidden && !statusLabel.stringValue.isEmpty
        guard showing else { return }
        let L = ChromeLayout.self
        let y = headerY ?? titleLabel.frame.minY
        let h = headerHeight ?? L.headerHeight
        let right = iconsLeft ?? ((updateButton.isHidden ? reviewButton.frame.minX : updateButton.frame.minX) - 12)
        let statusX = targetLanguageButton.frame.maxX + 8
        statusLabel.frame = NSRect(
            x: statusX,
            y: y,
            width: max(0, right - statusX - 4),
            height: h
        )
        if statusLabel.superview !== chromeHost || chromeHost.subviews.last !== statusLabel {
            chromeHost.addSubview(statusLabel, positioned: .above, relativeTo: nil)
        }
    }

    func actionButtonChipWidth(_ button: NSButton) -> CGFloat {
        return actionChipWidth(
            forTitle: PopoverLayoutMath.visibleActionChipTitle(of: button)
        )
    }

    /// Positions chips; each width comes from `ActionChip`, not the window.
    /// Positions chips and returns the x where the row ends — Compact drops the Q&A field there.
    @discardableResult
    func layoutActionRow(
        _ row: ActionRowSection,
        y: CGFloat,
        contentWidth: CGFloat,
        reservedTrailing: CGFloat = 0
    ) -> CGFloat {
        let L = ChromeLayout.self
        let rowWidth = max(0, contentWidth - reservedTrailing)
        // The chip owns its height through `lockedSize`; density changes have to reach it or the
        // chips keep the old height and float inside the row slot.
        let btnH = L.bottomBarHeight
        let gap = PopoverLayoutMath.actionButtonGap
        let overflowWidth = actionChipWidth(forTitle: "•••")
        for case let chip as ActionChipButton in row.buttons where chip.lockedSize.height != btnH {
            chip.lockedSize.height = btnH
        }
        let widths = Dictionary(uniqueKeysWithValues: row.buttons.map { ($0, actionButtonChipWidth($0)) })
        var hidden = Set<ObjectIdentifier>()
        func visibleWidths() -> [CGFloat] {
            row.buttons.compactMap { button in
                hidden.contains(ObjectIdentifier(button)) ? nil : widths[button]
            }
        }
        func rowUsed(_ extra: CGFloat) -> CGFloat {
            let visible = visibleWidths()
            return visible.reduce(CGFloat(0), +) + gap * CGFloat(max(0, visible.count - 1)) + extra
        }
        for target in row.overflowHideOrder {
            if rowUsed(hidden.isEmpty ? 0 : overflowWidth + gap) <= rowWidth { break }
            hidden.insert(ObjectIdentifier(target))
        }
        var x = L.padding
        for button in row.buttons {
            if hidden.contains(ObjectIdentifier(button)) {
                button.isHidden = true
                button.frame = NSRect(x: x, y: y, width: 0, height: btnH)
                continue
            }
            button.isHidden = false
            let width = widths[button] ?? 0
            button.frame = NSRect(x: x, y: y, width: width, height: btnH)
            applyActionChipChrome(button)
            x = button.frame.maxX + gap
        }
        layoutActionRowDividers(row, hidden: hidden, y: y, height: btnH, gap: gap)
        let overflowed = row.buttons.filter { hidden.contains(ObjectIdentifier($0)) }
        layoutActionRowOverflow(row, overflowed: overflowed, x: x, y: y, width: overflowWidth, height: btnH)
        // Chips move by direct frame assignment, so their arrow cursor rects would keep the old
        // geometry until something else invalidated them.
        for button in row.buttons { button.window?.invalidateCursorRects(for: button) }
        return overflowed.isEmpty ? max(L.padding, x - gap) : row.overflowButton.frame.maxX
    }

    /// Chips that did not fit stay reachable through an ellipsis menu instead of vanishing.
    func layoutActionRowOverflow(
        _ row: ActionRowSection,
        overflowed: [NSButton],
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat
    ) {
        let button = row.overflowButton
        guard !overflowed.isEmpty else {
            button.isHidden = true
            button.menu = nil
            return
        }
        button.isHidden = false
        button.chipSymbol = "ellipsis"
        button.lockedSize = NSSize(width: width, height: height)
        button.frame = NSRect(x: x, y: y, width: width, height: height)
        button.target = self
        button.action = #selector(actionRowOverflowClicked(_:))
        button.toolTip = "More actions"
        button.setAccessibilityLabel("More actions")
        applyActionChipLabel(button, title: "", symbol: "ellipsis", accent: false)
        applyActionChipChrome(button)
        let menu = NSMenu()
        for chip in overflowed {
            let title = PopoverLayoutMath.visibleActionChipTitle(of: chip)
            let item = NSMenuItem(title: title, action: chip.action, keyEquivalent: "")
            item.target = chip.target
            item.isEnabled = chip.isEnabled
            menu.addItem(item)
        }
        button.menu = menu
    }

    @objc func actionRowOverflowClicked(_ sender: NSButton) {
        guard let menu = sender.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    /// One hairline in the middle of the gap between each pair of visible text buttons.
    func layoutActionRowDividers(
        _ row: ActionRowSection,
        hidden: Set<ObjectIdentifier>,
        y: CGFloat,
        height: CGFloat,
        gap: CGFloat
    ) {
        let visible = row.secondaryButtons.filter { !hidden.contains(ObjectIdentifier($0)) }
        let inset: CGFloat = 7
        for (index, divider) in row.dividers.enumerated() {
            guard index + 1 < visible.count else {
                divider.isHidden = true
                continue
            }
            divider.isHidden = false
            divider.layer?.backgroundColor = Palette.cg(Palette.hairline, in: divider)
            divider.frame = NSRect(
                x: (visible[index].frame.maxX + gap / 2 - 0.5).rounded(),
                y: y + inset,
                width: 1,
                height: max(0, height - inset * 2)
            )
        }
    }

    /// Height taken by the action row(s) — the subtranslate pane adds a second one.
    var actionRowsHeight: CGFloat {
        PopoverLayoutMath.stackedChromeOverhead(
            hasSub: subSection != nil,
            hasQA: false,
            bottomBarHeight: ChromeLayout.bottomBarHeight,
            sectionGap: ChromeLayout.sectionGap,
            footerGap: 0,
            qaInputHeight: 0
        )
    }

    func layoutPaneChrome(
        headerBar: NSView,
        headerLabel: NSTextField,
        scrollView: NSScrollView,
        textView: NSTextView,
        trailingIcons: [NSButton],
        paneWidth: CGFloat,
        bodyHeight: CGFloat
    ) {
        let L = ChromeLayout.self
        let icon = L.iconButtonSize
        let topInset = L.paneHeaderTopInset
        let sideInset = L.textSideInset / 2
        if L.density.hidesPaneHeader {
            layoutFloatingPaneIcons(
                headerBar: headerBar,
                headerLabel: headerLabel,
                textView: textView,
                trailingIcons: trailingIcons,
                paneWidth: paneWidth,
                bodyHeight: bodyHeight
            )
        } else {
            textView.textContainer?.exclusionPaths = []
            headerBar.isHidden = false
            headerLabel.isHidden = false
            headerBar.layer?.backgroundColor = NSColor.clear.cgColor
            headerBar.layer?.borderWidth = 0
            headerBar.layer?.cornerRadius = 0
            headerBar.frame = NSRect(x: 0, y: bodyHeight, width: paneWidth, height: L.paneHeaderHeight)
            headerLabel.sizeToFit()
            let labelH = max(11, headerLabel.fittingSize.height)
            // Shift content down slightly so the speak/copy row has a little top padding.
            let labelY = max(0, ((L.paneHeaderHeight - labelH) / 2 - topInset).rounded(.towardZero))
            headerLabel.frame = NSRect(
                x: sideInset,
                y: labelY,
                width: max(28, min(headerLabel.fittingSize.width + 2, paneWidth - 52)),
                height: labelH
            )
            let headerIconY = max(0, (L.paneHeaderHeight - icon) / 2 - topInset)
            var iconX = paneWidth - 10 - icon
            for button in trailingIcons.reversed() {
                button.isHidden = false
                button.frame = NSRect(x: iconX, y: headerIconY, width: icon, height: icon)
                iconX -= icon + 10
            }
        }
        if textView === inputTextView && !inputContextLabel.isHidden {
            let contextH: CGFloat = 16
            let scrollH = max(0, bodyHeight - contextH)
            inputContextLabel.frame = NSRect(x: sideInset, y: bodyHeight - contextH, width: max(0, paneWidth - sideInset * 2), height: contextH)
            scrollView.frame = NSRect(x: 0, y: 0, width: paneWidth, height: scrollH)
            textView.minSize = NSSize(width: 0, height: scrollH)
            imagePlaceholderLabel.frame = NSRect(x: sideInset, y: 10, width: max(0, paneWidth - sideInset * 2), height: 22)
        } else {
            scrollView.frame = NSRect(x: 0, y: 0, width: paneWidth, height: bodyHeight)
            textView.minSize = NSSize(width: 0, height: bodyHeight)
            if textView === inputTextView {
                imagePlaceholderLabel.frame = NSRect(x: sideInset, y: 10, width: max(0, paneWidth - sideInset * 2), height: 22)
            }
        }
        scrollView.hasVerticalScroller = true
    }

    /// Compact drops the header strip, so the pane icons become a glass pill floating over the top
    /// right of the body. Always visible — hover-only would hide the copy/speak affordance.
    private func layoutFloatingPaneIcons(
        headerBar: NSView,
        headerLabel: NSTextField,
        textView: NSTextView,
        trailingIcons: [NSButton],
        paneWidth: CGFloat,
        bodyHeight: CGFloat
    ) {
        let L = ChromeLayout.self
        let icon = L.iconButtonSize
        let gap: CGFloat = 8
        let inset: CGFloat = 5
        headerLabel.isHidden = true
        let visible = trailingIcons
        let pillW = CGFloat(visible.count) * icon + CGFloat(max(0, visible.count - 1)) * gap + inset * 2
        let pillH = icon + inset * 2
        let pillX = max(0, paneWidth - inset - pillW)
        let pillY = max(0, bodyHeight - inset - pillH)
        headerBar.isHidden = visible.isEmpty
        headerBar.wantsLayer = true
        headerBar.layer?.backgroundColor = Palette.cg(Palette.opaquePaneFill, in: headerBar)
        headerBar.layer?.borderWidth = 1
        headerBar.layer?.borderColor = Palette.cg(Palette.hairline, in: headerBar)
        headerBar.layer?.cornerRadius = pillH / 2
        headerBar.frame = NSRect(x: pillX, y: pillY, width: pillW, height: pillH)
        // The pane cards add the header strip before the scroll view, which is fine while the strip
        // sits above the body. Floating over it, the scroll view swallows every click — so raise it.
        if let card = headerBar.superview, card.subviews.last !== headerBar {
            card.addSubview(headerBar, positioned: .above, relativeTo: nil)
        }
        var iconX = pillW - inset - icon
        for button in visible.reversed() {
            button.frame = NSRect(x: iconX, y: inset, width: icon, height: icon)
            iconX -= icon + gap
        }
        applyPaneIconExclusion(textView: textView, pill: headerBar.frame, paneWidth: paneWidth, bodyHeight: bodyHeight)
    }

    /// Text flows around the floating pill instead of running under it. TextKit measures the
    /// exclusion in container space, whose origin is the top left of the text — not the pane.
    private func applyPaneIconExclusion(
        textView: NSTextView,
        pill: NSRect,
        paneWidth: CGFloat,
        bodyHeight: CGFloat
    ) {
        guard let container = textView.textContainer, !pill.isEmpty else {
            textView.textContainer?.exclusionPaths = []
            return
        }
        let padding: CGFloat = 6
        let originX = textView.textContainerInset.width + container.lineFragmentPadding
        let originY = textView.textContainerInset.height
        let rect = NSRect(
            x: max(0, pill.minX - originX - padding),
            y: max(0, bodyHeight - pill.maxY - originY),
            width: pill.width + padding,
            height: pill.height + padding
        )
        container.exclusionPaths = [NSBezierPath(rect: rect)]
    }

    /// Height the split body wants before the panel clamp — the sum of both sections plus the gap.
    func currentSplitPaneHeight(paneWidth: CGFloat) -> CGFloat {
        let primary = measuredPrimaryPaneHeight(paneWidth: paneWidth)
        var total = primary
        if let sub = subSection {
            let contentWidth = max(0, CGFloat(config.ui.width) - ChromeLayout.padding * 2)
            let subPaneWidth = subSectionPanes(contentWidth: contentWidth, mode: sub.mode).left
            total += ChromeLayout.sectionDividerReserved + measuredSubPaneHeight(sub, paneWidth: subPaneWidth)
        }
        if let qa = qaSection {
            total += ChromeLayout.sectionGap + measuredQAPaneHeight(qa, paneWidth: paneWidth * 2 + ChromeLayout.dividerWidth)
        }
        return total
    }

    func measuredPrimaryPaneHeight(paneWidth: CGFloat) -> CGFloat {
        return paneHeight(
            source: inputTextView.attributedString(),
            result: textView.attributedString(),
            paneWidth: paneWidth
        )
    }

    func measuredSubPaneHeight(_ section: SubtranslateSection, paneWidth: CGFloat) -> CGFloat {
        return paneHeight(
            source: section.sourceTextView.attributedString(),
            result: section.resultTextView.attributedString(),
            paneWidth: paneWidth
        )
    }

    func measuredQAPaneHeight(_ section: QAPaneSection, paneWidth: CGFloat) -> CGFloat {
        let L = ChromeLayout.self
        let measureWidth = max(80, paneWidth - L.textSideInset)
        let measured = measuredTextHeight(section.textView.attributedString(), width: measureWidth) + L.textInset
        let needed = L.paneHeaderHeight + measured
        return min(max(stackedMinPaneHeight, needed), qaMaxSectionHeight)
    }

    func paneHeight(source: NSAttributedString, result: NSAttributedString, paneWidth: CGFloat) -> CGFloat {
        let L = ChromeLayout.self
        let measureWidth = max(80, paneWidth - L.textSideInset)
        return PopoverLayoutMath.splitPaneHeight(
            sourceMeasured: measuredTextHeight(source, width: measureWidth) + L.textInset,
            resultMeasured: measuredTextHeight(result, width: measureWidth) + L.textInset,
            paneHeaderHeight: L.paneHeaderHeight,
            minPaneHeight: stackedMinPaneHeight,
            maxPaneHeight: maxSectionHeight
        )
    }

    /// Height ceiling for one pane — halved-ish once the subtranslate pane shares the panel.
    var maxSectionHeight: CGFloat {
        guard subSection != nil || qaSection != nil else { return ChromeLayout.splitMaxPaneHeight }
        // Q&A shares the panel with these two, so main/sub give up 10% of their stacked budget to it.
        return qaSection == nil
            ? ChromeLayout.splitMaxStackedPaneHeight
            : ChromeLayout.splitMaxStackedPaneHeight * 0.9
    }

    /// Q&A keeps the full stacked budget — it inherits the room main/sub gave back.
    var qaMaxSectionHeight: CGFloat { ChromeLayout.splitMaxStackedPaneHeight }

    /// Floor for one pane. Two panes at the single-pane floor don't fit a short panel, so stacking
    /// lowers it rather than letting the pair overflow.
    var stackedMinPaneHeight: CGFloat {
        (subSection == nil && qaSection == nil) ? ChromeLayout.splitMinPaneHeight : ChromeLayout.splitMinStackedPaneHeight
    }

    /// Resizes/repositions the panel around `size`. While the panel hasn't been dragged by the
    /// user, it stays anchored to `showMousePoint` (recomputed each time, so growth/shrinkage never
    /// straddles the cursor). Once dragged, resizes keep the panel's top-left corner fixed instead.
    func applyPanelFrame(size: NSSize, reanchorToMouse: Bool = false) {
        guard let screenFrame = currentScreenFrame() else {
            isProgrammaticFrameChange = true
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: panel.isVisible)
            isProgrammaticFrameChange = false
            LiquidGlassChrome.applyWindowShape(panel)
            return
        }
        let newFrame: NSRect
        if !reanchorToMouse && (userMovedWindow || panel.isVisible) {
            // Panel is already on screen (e.g. an async translate result just resized it) — keep
            // its top-left corner fixed instead of re-anchoring to the mouse, otherwise it jumps
            // out from under a click the user is mid-way through, which the outside-click monitor
            // then reads as a click outside the panel and closes it.
            let oldFrame = panel.frame
            let originY = clamp(oldFrame.maxY - size.height, minV: screenFrame.minY, maxV: screenFrame.maxY - size.height)
            let originX = clamp(oldFrame.minX, minV: screenFrame.minX, maxV: screenFrame.maxX - size.width)
            newFrame = NSRect(x: originX, y: originY, width: size.width, height: size.height)
        } else {
            let origin = computePopupOrigin(size: size, mouse: showMousePoint, screenFrame: screenFrame)
            newFrame = NSRect(origin: origin, size: size)
        }
        isProgrammaticFrameChange = true
        panel.setFrame(newFrame, display: panel.isVisible)
        isProgrammaticFrameChange = false
        LiquidGlassChrome.applyWindowShape(panel)
    }

    func currentScreenFrame() -> NSRect? {
        (NSScreen.screens.first { $0.frame.contains(showMousePoint) } ?? NSScreen.main)?.visibleFrame
    }

    /// Places the panel beside `mouse` (below, above, right, then left, in that preference order),
    /// falling back to a clamped on-screen position. The cursor point is never inside the resulting
    /// rect, so the panel never lands centered on top of it.
    func computePopupOrigin(size: NSSize, mouse: NSPoint, screenFrame: NSRect) -> NSPoint {
        let gap: CGFloat = 12
        if mouse.y - gap - size.height >= screenFrame.minY {
            let x = clamp(mouse.x - size.width / 2, minV: screenFrame.minX, maxV: screenFrame.maxX - size.width)
            return NSPoint(x: x, y: mouse.y - gap - size.height)
        }
        if mouse.y + gap + size.height <= screenFrame.maxY {
            let x = clamp(mouse.x - size.width / 2, minV: screenFrame.minX, maxV: screenFrame.maxX - size.width)
            return NSPoint(x: x, y: mouse.y + gap)
        }
        if mouse.x + gap + size.width <= screenFrame.maxX {
            let y = clamp(mouse.y - size.height / 2, minV: screenFrame.minY, maxV: screenFrame.maxY - size.height)
            return NSPoint(x: mouse.x + gap, y: y)
        }
        if mouse.x - gap - size.width >= screenFrame.minX {
            let y = clamp(mouse.y - size.height / 2, minV: screenFrame.minY, maxV: screenFrame.maxY - size.height)
            return NSPoint(x: mouse.x - gap - size.width, y: y)
        }
        let x = clamp(mouse.x, minV: screenFrame.minX, maxV: screenFrame.maxX - size.width)
        let y = clamp(mouse.y - size.height, minV: screenFrame.minY, maxV: screenFrame.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    func clamp(_ value: CGFloat, minV: CGFloat, maxV: CGFloat) -> CGFloat {
        guard maxV >= minV else { return minV }
        return min(max(value, minV), maxV)
    }

    /// Puts the panel next to `point` unless the user pinned it. Used when the hotkey fires
    /// while a leftover panel is already "visible" on another part of a large desktop.
    func movePanelToPointer(_ point: NSPoint) {
        guard !isPinned else { return }
        showMousePoint = point
        userMovedWindow = false
        reflowLayout(reanchorToMouse: true)
    }
    func preferredPopoverHeight() -> CGFloat {
        let width = CGFloat(config.ui.width)
        let L = ChromeLayout.self
        let contentWidth = width - L.padding * 2
        let panes = PopoverLayoutMath.splitPaneWidth(contentWidth: contentWidth, divider: L.dividerWidth, ratio: mainSplitRatio)
        let splitHeight = currentSplitPaneHeight(paneWidth: panes.left)
        return PopoverLayoutMath.splitPrismHeight(
            padding: L.padding,
            paddingBottom: L.paddingBottom,
            headerHeight: L.headerHeight,
            statusHeight: 0,
            headerGap: L.headerGap,
            splitPaneHeight: splitHeight,
            qaInputHeight: effectiveQAInputHeight,
            footerGap: L.footerGap,
            bottomBarHeight: L.bottomBarHeight,
            hasSub: subSection != nil,
            sectionGap: L.sectionGap
        )
    }

    func maxPopoverHeight() -> CGFloat {
        // A second pane needs its own room on top of the single-pane budget, but never more than
        // the screen can show.
        var stackedAllowance: CGFloat = 0
        if subSection != nil { stackedAllowance += ChromeLayout.splitMaxStackedPaneHeight + ChromeLayout.sectionDividerReserved }
        if qaSection != nil { stackedAllowance += ChromeLayout.splitMaxStackedPaneHeight + ChromeLayout.sectionGap }
        let base = min(CGFloat(config.ui.height) + 300 + stackedAllowance, 1200)
        guard let screen = currentScreenFrame() else { return base }
        return min(base, screen.height - 40)
    }

    /// Chrome + one min-height slot per visible stacked pane — floor so stacked panes never overlap.
    func stackedLayoutFloorHeight() -> CGFloat {
        let L = ChromeLayout.self
        var paneCount: CGFloat = 1
        if subSection != nil { paneCount += 1 }
        if qaSection != nil { paneCount += 1 }
        var stackedBody = stackedMinPaneHeight * paneCount
        if subSection != nil { stackedBody += L.sectionDividerReserved }
        if qaSection != nil { stackedBody += L.sectionGap }
        return PopoverLayoutMath.splitPrismHeight(
            padding: L.padding,
            paddingBottom: L.paddingBottom,
            headerHeight: L.headerHeight,
            statusHeight: 0,
            headerGap: L.headerGap,
            splitPaneHeight: stackedBody,
            qaInputHeight: effectiveQAInputHeight,
            footerGap: L.footerGap,
            bottomBarHeight: L.bottomBarHeight,
            hasSub: subSection != nil,
            sectionGap: L.sectionGap
        )
    }

    func currentPopoverHeight() -> CGFloat {
        let preferred = max(preferredPopoverHeight(), stackedLayoutFloorHeight())
        return min(max(preferred, 220), maxPopoverHeight())
    }

    /// Left-pane share of the main split. Auto-set by translation mode — 1:1 normally, 1:2 for Learn.
    var mainSplitRatio: CGFloat {
        lastExecutionMode == .learn ? 0.3 : 0.5
    }

    func measuredTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        PopoverLayoutMath.measuredTextHeight(text, width: width)
    }

    var visibleQAInputHeight: CGFloat {
        qaInputField.isHidden ? 0 : ChromeLayout.qaInputHeight
    }

    /// Width the merged Q&A field needs before it stops being worth sharing the action row.
    var mergedQAInputMinWidth: CGFloat { 150 }

    /// Compact puts the Q&A field on the action row — but only when the chips leave it real room.
    var mergesQAInput: Bool {
        guard ChromeLayout.density.mergesQAIntoActionRow, !qaInputField.isHidden else { return false }
        let contentWidth = max(0, CGFloat(config.ui.width) - ChromeLayout.padding * 2)
        let gap = PopoverLayoutMath.actionButtonGap
        let core = mainActionRow.buttons.filter { !mainActionRow.overflowHideOrder.contains($0) }
        let coreWidth = core.reduce(CGFloat(0)) { $0 + actionButtonChipWidth($1) }
            + gap * CGFloat(max(0, core.count - 1))
            + gap + actionChipWidth(forTitle: "•••")
        return contentWidth - coreWidth - gap >= mergedQAInputMinWidth
    }

    /// Zero once the field shares the action row — the stack must not reserve a second row for it.
    var effectiveQAInputHeight: CGFloat {
        mergesQAInput ? 0 : visibleQAInputHeight
    }

    /// Left-pane share of the subtranslate split. Auto-set by translation mode — 1:1 normally, 1:2 for Learn.
    func subSectionPanes(contentWidth: CGFloat, mode: TranslationMode) -> (left: CGFloat, right: CGFloat) {
        let L = ChromeLayout.self
        let ratio: CGFloat = mode == .learn ? 0.3 : 0.5
        return PopoverLayoutMath.splitPaneWidth(contentWidth: contentWidth, divider: L.dividerWidth, ratio: ratio)
    }

}
