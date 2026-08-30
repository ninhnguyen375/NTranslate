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
    static let actionButtonGap: CGFloat = 10
    static let actionButtonPadX: CGFloat = 12
    static let actionIconSize: CGFloat = 14
    static let actionIconTitleGap: CGFloat = 5
    static let actionButtonHeight: CGFloat = 32

    /// Fixed chip size per verb — not `fittingSize` / window. `.glass` metrics change
    /// after the panel appears; these values stay the same for every row and every open.
    enum ActionChip: String {
        case translate = "Translate"
        case learn = "Learn"
        case proofread = "Proofread"
        case images = "Images"
        case ask = "Ask"
        case stop = "Stop"

        var width: CGFloat {
            switch self {
            case .translate: 110
            case .learn: 86
            case .proofread: 116
            case .images: 96
            case .ask: 76
            case .stop: 80
            }
        }

        static func width(forTitle title: String) -> CGFloat {
            let visible = visibleActionChipTitle(title)
            return ActionChip(rawValue: visible)?.width ?? measuredChipWidth(title: visible)
        }
    }

    /// `NSTextAttachment` contributes U+FFFC; chip verbs must compare without it.
    static func visibleActionChipTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\u{FFFC}", with: "")
    }

    @MainActor
    static func visibleActionChipTitle(of button: NSButton) -> String {
        let raw = button.attributedTitle.length > 0 ? button.attributedTitle.string : button.title
        return visibleActionChipTitle(raw)
    }

    /// Centers the icon on the title's cap-height box (baseline-relative).
    static func actionChipIconTitleYOffset(font: NSFont, iconHeight: CGFloat) -> CGFloat {
        (font.capHeight - iconHeight) / 2
    }

    /// SF Symbols pad their canvas differently per glyph, so centering the *image* leaves the
    /// icon visibly off against the title. Trim to the drawn ink, then bake `gap` points of
    /// transparent padding on the trailing edge — `NSTextAttachment` has no spacing knob and an
    /// image-less spacer attachment renders zero width.
    static func chipIconImage(
        symbol: String,
        tint: NSColor,
        pointSize: CGFloat,
        weight: NSFont.Weight = .medium,
        gap: CGFloat = actionIconTitleGap
    ) -> NSImage? {
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: nil),
              let image = base.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [tint])
                    .applying(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
              ) else { return nil }
        let size = image.size
        let scale: CGFloat = 2
        guard let probe = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(ceil(size.width * scale)),
            pixelsHigh: Int(ceil(size.height * scale)),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return image }
        probe.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: probe)
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<probe.pixelsHigh {
            for x in 0..<probe.pixelsWide {
                guard let color = probe.colorAt(x: x, y: y), color.alphaComponent > 0.05 else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return image }
        let inkX = CGFloat(minX) / scale
        let inkWidth = CGFloat(maxX - minX + 1) / scale
        let inkHeight = CGFloat(maxY - minY + 1) / scale
        let inkY = size.height - CGFloat(minY) / scale - inkHeight
        let canvas = NSImage(size: NSSize(width: inkWidth + gap, height: inkHeight))
        canvas.lockFocus()
        image.draw(at: NSPoint(x: -inkX, y: -inkY), from: .zero, operation: .sourceOver, fraction: 1)
        canvas.unlockFocus()
        return canvas
    }

    /// `icon` must come from `chipIconImage` — ink-tight, so centering its box on the
    /// cap-height box centers the glyph itself.
    static func actionChipAttributedTitle(
        title: String,
        icon: NSImage?,
        font: NSFont,
        color: NSColor
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let result = NSMutableAttributedString()
        if let icon {
            let iconAttachment = NSTextAttachment()
            iconAttachment.image = icon
            iconAttachment.bounds = CGRect(
                x: 0,
                y: actionChipIconTitleYOffset(font: font, iconHeight: icon.size.height),
                width: icon.size.width,
                height: icon.size.height
            )
            result.append(NSAttributedString(attachment: iconAttachment))
        }
        result.append(NSAttributedString(string: title, attributes: attrs))
        result.addAttributes(attrs, range: NSRange(location: 0, length: result.length))
        return result
    }

    static func fittedButtonWidth(intrinsic: CGFloat, pad: CGFloat = actionButtonPadX) -> CGFloat {
        ceil(max(0, intrinsic) + pad * 2)
    }

    static func actionChipWidth(title: String) -> CGFloat {
        ActionChip.width(forTitle: title)
    }

    static func measuredChipWidth(title: String, fontSize: CGFloat = 12, pad: CGFloat = actionButtonPadX) -> CGFloat {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let textW = ceil((title as NSString).size(withAttributes: [.font: font]).width)
        return ceil(pad * 2 + actionIconSize + actionIconTitleGap + textW)
    }

    static func fittedRowWidth(intrinsics: [CGFloat], pad: CGFloat = actionButtonPadX, gap: CGFloat = actionButtonGap) -> CGFloat {
        guard !intrinsics.isEmpty else { return 0 }
        let chips = intrinsics.reduce(CGFloat(0)) { $0 + fittedButtonWidth(intrinsic: $1, pad: pad) }
        return chips + gap * CGFloat(intrinsics.count - 1)
    }

    /// Chrome below the main split: each action row sits `footerGap` under its pane.
    static func stackedChromeOverhead(
        hasSub: Bool,
        hasQA: Bool,
        bottomBarHeight: CGFloat,
        sectionGap: CGFloat,
        footerGap: CGFloat,
        qaInputHeight: CGFloat
    ) -> CGFloat {
        // `sectionGap` is the pane-stack gap (Q&A); the labeled Subtranslate rule is
        // reserved separately via `sectionDividerHeight` in the pane-height math.
        _ = sectionGap
        let actionRows = hasSub ? (bottomBarHeight + footerGap) * 2 : bottomBarHeight + footerGap
        let qaAddition = (hasQA && qaInputHeight > 0) ? qaInputHeight + qaInputGap : 0
        return actionRows + qaAddition
    }

    /// Hairline + centered caption frames for the Subtranslate section divider.
    static func labeledHairlineDivider(
        width: CGFloat,
        height: CGFloat,
        labelWidth: CGFloat,
        lineHeight: CGFloat = 1,
        labelGap: CGFloat = 8
    ) -> (left: NSRect, label: NSRect, right: NSRect) {
        let labelW = min(max(0, labelWidth), max(0, width - labelGap * 2))
        let side = max(0, (width - labelW - labelGap * 2) / 2)
        let lineY = ((height - lineHeight) / 2).rounded(.towardZero)
        let labelX = side + labelGap
        return (
            NSRect(x: 0, y: lineY, width: side, height: lineHeight),
            NSRect(x: labelX, y: 0, width: labelW, height: height),
            NSRect(x: labelX + labelW + labelGap, y: lineY, width: side, height: lineHeight)
        )
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
        minPaneHeight: CGFloat,
        subGap: CGFloat? = nil
    ) -> (primary: CGFloat, sub: CGFloat?, qa: CGFloat?) {
        var activeCount = 1
        if subNeeded != nil { activeCount += 1 }
        if qaNeeded != nil { activeCount += 1 }

        let primarySubGap: CGFloat = subNeeded == nil ? 0 : (subGap ?? gap)
        let toQAGap: CGFloat = qaNeeded == nil ? 0 : gap
        let totalGaps = primarySubGap + toQAGap
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
