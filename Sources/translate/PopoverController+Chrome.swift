// Popup construction, styling, and geometry: view hierarchy, split-prism layout, and panel framing.
import AppKit
import QuartzCore

extension PopoverController {
    func buildPopover() {
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        let L = ChromeLayout.self

        LiquidGlassChrome.configure(window: panel)
        glassContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
        shellGlass.frame = glassContainer.bounds
        LiquidGlassChrome.configure(container: glassContainer, shell: shellGlass, host: chromeHost)
        chromeHost.frame = shellGlass.bounds
        chromeHost.autoresizingMask = [.width, .height]
        chromeHost.onAppearanceChange = { [weak self] in self?.reflowLayout() }

        titleLabel.stringValue = "NTranslate"
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = Palette.titleText
        titleLabel.drawsBackground = false
        titleLabel.toolTip = "NTranslate v\(Self.buildVersion)"

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = Palette.mutedText
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        statusLabel.drawsBackground = false

        configureChromeIconButton(closeButton, symbol: "xmark", action: #selector(closePopover), label: "Close")
        configureChromeIconButton(pinButton, symbol: "pin", action: #selector(togglePin), label: "Pin")
        configureChromeIconButton(historyButton, symbol: "clock.arrow.circlepath", action: #selector(openTranslationHistory), label: "Translation History")
        configureChromeIconButton(updateButton, symbol: "arrow.triangle.2.circlepath", action: #selector(checkForUpdatesClicked), label: "Check for Updates")
        configureChromeIconButton(contextButton, symbol: "text.quote", action: #selector(showContextTooltip), label: "Translation context")
        contextButton.isHidden = true
        updatePinButton()

        configureLanguageControls()

        // Split prism sits inside shell glass content (glass shouldn't nest/sample glass).
        splitHost.wantsLayer = true
        splitHost.layer?.cornerRadius = L.splitCornerRadius
        splitHost.layer?.cornerCurve = .continuous
        splitHost.layer?.masksToBounds = true
        applySplitHostChrome()

        stylePane(sourceCard)
        stylePane(resultCard)
        configurePaneHeaderLabel(sourceHeaderLabel, title: "EN")
        configurePaneHeaderLabel(resultHeaderLabel, title: "VI")
        stylePaneHeaderBar(sourceHeaderBar)
        stylePaneHeaderBar(resultHeaderBar)
        installSplitDividerGradient()

        inputTextView.isEditable = true
        inputTextView.isSelectable = true
        inputTextView.delegate = self
        inputTextView.onImagePasted = { [weak self] imageData in
            self?.setPendingImage(imageData)
            self?.inputTextView.string = ""
        }
        inputTextView.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
        inputTextView.drawsBackground = false
        inputTextView.textColor = Palette.bodyText
        inputTextView.insertionPointColor = .controlAccentColor
        inputTextView.focusRingType = .none
        inputTextView.textContainerInset = NSSize(width: 12, height: 10)
        inputTextView.minSize = NSSize(width: 0, height: 40)
        inputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.autoresizingMask = [.width]
        inputTextView.textContainer?.widthTracksTextView = true

        inputScrollView.borderType = .noBorder
        inputScrollView.drawsBackground = false
        inputScrollView.focusRingType = .none
        inputScrollView.hasVerticalScroller = true
        inputScrollView.hasHorizontalScroller = false
        inputScrollView.autohidesScrollers = true
        inputScrollView.scrollerStyle = .overlay
        inputScrollView.documentView = inputTextView
        imagePlaceholderLabel.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
        imagePlaceholderLabel.textColor = Palette.placeholderText
        imagePlaceholderLabel.isHidden = true
        imagePlaceholderLabel.setAccessibilityLabel("Image from clipboard")

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
        textView.textColor = Palette.bodyText
        textView.focusRingType = .none
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.minSize = NSSize(width: 0, height: 40)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        textScrollView.borderType = .noBorder
        textScrollView.drawsBackground = false
        textScrollView.focusRingType = .none
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.scrollerStyle = .overlay
        textScrollView.documentView = textView

        configurePrimaryButton(translateButton, title: "Translate", symbol: "arrow.right.circle", action: #selector(runTranslate), accent: true)
        configurePrimaryButton(learnButton, title: "Learn", symbol: "brain.head.profile", action: #selector(runLearn), accent: false)
        learnButton.toolTip = "Learn"
        learnButton.setAccessibilityLabel("Learn")
        configurePrimaryButton(imagesButton, title: "Images", symbol: "photo", action: #selector(runImages), accent: false)
        imagesButton.toolTip = "Search Images"
        imagesButton.setAccessibilityLabel("Search Images")
        configurePrimaryButton(proofreadButton, title: "Proofread", symbol: "text.badge.checkmark", action: #selector(runProofread), accent: false)
        proofreadButton.toolTip = "Proofread"
        proofreadButton.setAccessibilityLabel("Proofread")
        configureIconButton(speakSourceButton, symbol: "speaker.wave.2", action: #selector(speakInput), label: "Speak source")
        configureIconButton(speakResultButton, symbol: "speaker.wave.2", action: #selector(speakResult), label: "Speak translation")
        configureIconButton(copyButton, symbol: "doc.on.doc", action: #selector(copyResult), label: "Copy")
        configureIconButton(saveWordButton, symbol: "bookmark", action: #selector(toggleSaveWord), label: "Save Word")

        updateSpeakButtons()
        updateSaveWordButton()
        updateBusyState()
        languageSelectionChanged()

        sourceHeaderBar.addSubview(sourceHeaderLabel)
        sourceHeaderBar.addSubview(speechRatePopUp)
        sourceHeaderBar.addSubview(speakSourceButton)
        sourceCard.addSubview(sourceHeaderBar)
        sourceCard.addSubview(inputScrollView)
        sourceCard.addSubview(imagePlaceholderLabel)

        resultHeaderBar.addSubview(resultHeaderLabel)
        resultHeaderBar.addSubview(speakResultButton)
        resultHeaderBar.addSubview(copyButton)
        resultHeaderBar.addSubview(saveWordButton)
        resultCard.addSubview(resultHeaderBar)
        resultCard.addSubview(textScrollView)

        splitHost.addSubview(sourceCard)
        splitHost.addSubview(splitDivider)
        splitHost.addSubview(resultCard)

        chromeHost.addSubview(titleLabel)
        chromeHost.addSubview(statusLabel)
        chromeHost.addSubview(contextButton)
        chromeHost.addSubview(historyButton)
        chromeHost.addSubview(pinButton)
        chromeHost.addSubview(closeButton)
        chromeHost.addSubview(splitHost)
        chromeHost.addSubview(sourceLanguageButton)
        chromeHost.addSubview(swapLanguagesButton)
        chromeHost.addSubview(targetLanguageButton)
        chromeHost.addSubview(imagesButton)
        chromeHost.addSubview(proofreadButton)
        chromeHost.addSubview(learnButton)
        chromeHost.addSubview(translateButton)

        configureQAInputBar()
        chromeHost.addSubview(qaInputField)

        configureFloatingToolbar()
        chromeHost.addSubview(selectionFloatingBar)

        let containerHost = NSView(frame: glassContainer.bounds)
        containerHost.autoresizingMask = [.width, .height]
        containerHost.addSubview(shellGlass)
        glassContainer.contentView = containerHost

        layoutSplitPrism(width: width, height: height)
        panel.contentView = glassContainer
        panel.setFrame(NSRect(origin: panel.frame.origin, size: glassContainer.frame.size), display: false)
    }

    func installSplitDividerGradient() {
        splitDividerGradient?.removeFromSuperlayer()
        splitDividerGradient = installDividerGradient(on: splitDivider)
    }

    @discardableResult
    func installDividerGradient(on divider: NSView) -> CAGradientLayer {
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.clear.cgColor
        divider.layer?.masksToBounds = true
        let gradient = CAGradientLayer()
        gradient.colors = Self.dividerGradientColors(in: divider)
        gradient.locations = [0, 0.18, 0.5, 0.82, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        divider.layer?.addSublayer(gradient)
        return gradient
    }

    static func dividerGradientColors(in view: NSView) -> [CGColor] {
        [
            Palette.cg(Palette.dividerSheenClear, in: view),
            Palette.cg(Palette.dividerSheen, in: view),
            Palette.cg(Palette.hairline, in: view),
            Palette.cg(Palette.dividerSheen, in: view),
            Palette.cg(Palette.dividerSheenClear, in: view)
        ]
    }

    func applySplitHostChrome() {
        splitHost.layer?.borderWidth = 1
        splitHost.layer?.borderColor = Palette.cg(Palette.hairline, in: splitHost)
        splitHost.layer?.backgroundColor = Palette.cg(Palette.paneFill, in: splitHost)
        splitDividerGradient?.colors = Self.dividerGradientColors(in: splitDivider)
    }

    func applyControlCornerRadius(_ view: NSView, radius: CGFloat? = nil) {
        let resolved = radius ?? ChromeLayout.controlCornerRadius
        view.wantsLayer = true
        view.layer?.cornerRadius = resolved
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    func stylePane(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func stylePaneHeaderBar(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    func configurePaneHeaderLabel(_ label: NSTextField, title: String) {
        label.stringValue = title
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.textColor = Palette.paneLabel
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
    }

    func paneLanguageCode(_ language: String) -> String {
        switch language {
        case "Auto detect": return "AUTO"
        case "English": return "EN"
        case "Vietnamese": return "VI"
        case "Chinese", "Chinese (Simplified)", "Chinese (Traditional)": return "ZH"
        case "Japanese": return "JA"
        case "Korean": return "KO"
        case "French": return "FR"
        case "German": return "DE"
        case "Spanish": return "ES"
        default:
            let letters = language.uppercased().filter(\.isLetter)
            return String(letters.prefix(2))
        }
    }

    func updatePaneLanguageLabels() {
        let sourceTitle = selectedSourceLanguage()
        let targetTitle = selectedTargetLanguage()
        if sourceTitle == LanguageDetector.autoDetect {
            let trimmed = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            sourceHeaderLabel.stringValue = trimmed.isEmpty
                ? "AUTO"
                : paneLanguageCode(effectiveSourceLanguage(for: trimmed))
        } else {
            sourceHeaderLabel.stringValue = paneLanguageCode(sourceTitle)
        }
        resultHeaderLabel.stringValue = paneLanguageCode(targetTitle)
    }

    func configurePrimaryButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        action: Selector,
        accent: Bool
    ) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title.isEmpty ? nil : title)
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeading
        button.imageHugsTitle = true
        button.target = self
        button.action = action
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.font = .systemFont(ofSize: ChromeLayout.controlFontSize, weight: .regular)
        if accent {
            button.bezelColor = .controlAccentColor
        } else {
            button.bezelColor = nil
        }
        applyControlCornerRadius(button)
    }

    func configureChromeIconButton(_ button: NSButton, symbol: String, action: Selector, label: String) {
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.contentTintColor = Palette.chromeIconTint
        applyControlCornerRadius(button, radius: ChromeLayout.chromeIconSize / 2)
    }

    func configureIconButton(_ button: NSButton, symbol: String, action: Selector, label: String) {
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .inline
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.contentTintColor = Palette.iconTint
    }

    func resetCopyButtonAppearance() {
        copyButton.title = ""
        copyButton.attributedTitle = NSAttributedString(string: "")
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = Palette.iconTint
    }

    func reflowLayout() {
        guard panel.contentView != nil else { return }
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        layoutSplitPrism(width: width, height: height)
        applyPanelFrame(size: NSSize(width: width, height: height))
    }

    func layoutSplitPrism(width: CGFloat, height: CGFloat) {
        let L = ChromeLayout.self
        let contentWidth = width - L.padding * 2
        let panes = PopoverLayoutMath.splitPaneWidth(contentWidth: contentWidth, divider: L.dividerWidth)
        let statusH = statusLabel.isHidden ? 0 : L.statusHeight

        let headerY = height - L.padding - L.headerHeight
        let statusY = headerY - statusH
        let bottomY = L.paddingBottom
        let qaH = L.qaInputHeight
        let qaY = bottomY + L.bottomBarHeight + 8
        let splitY = qaY + qaH + L.footerGap
        // Pin body under the header so extra panel height grows the pane — never a dead gap.
        let splitTop = (statusH > 0 ? statusY : headerY) - L.headerGap
        // The panel height is already the clamped truth; the split gets exactly what's left over.
        // Measuring again here and taking the larger value is what pushed panes past the chrome.
        let totalSplitHeight = max(0, splitTop - splitY)
        let heights = PopoverLayoutMath.multiStackedSectionHeights(
            available: totalSplitHeight,
            primaryNeeded: measuredPrimaryPaneHeight(paneWidth: panes.left),
            subNeeded: subSection.map { measuredSubPaneHeight($0, paneWidth: panes.left) },
            qaNeeded: qaSection.map { measuredQAPaneHeight($0, paneWidth: contentWidth) },
            gap: L.sectionGap,
            minPaneHeight: stackedMinPaneHeight
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
        titleLabel.frame = NSRect(x: L.padding + 2, y: headerY, width: 160, height: L.headerHeight)
        statusLabel.frame = NSRect(x: L.padding, y: statusY, width: contentWidth - 50, height: statusH)
        closeButton.frame = NSRect(
            x: width - L.padding - chromeIcon,
            y: headerY + (L.headerHeight - chromeIcon) / 2,
            width: chromeIcon,
            height: chromeIcon
        )
        pinButton.frame = NSRect(
            x: closeButton.frame.minX - 6 - chromeIcon,
            y: closeButton.frame.minY,
            width: chromeIcon,
            height: chromeIcon
        )
        historyButton.frame = NSRect(
            x: pinButton.frame.minX - 6 - chromeIcon,
            y: closeButton.frame.minY,
            width: chromeIcon,
            height: chromeIcon
        )
        updateButton.frame = NSRect(
            x: historyButton.frame.minX - 6 - chromeIcon,
            y: closeButton.frame.minY,
            width: chromeIcon,
            height: chromeIcon
        )
        contextButton.frame = NSRect(
            x: updateButton.frame.minX - 6 - chromeIcon,
            y: closeButton.frame.minY,
            width: chromeIcon,
            height: chromeIcon
        )
        applyControlCornerRadius(closeButton, radius: chromeIcon / 2)
        applyControlCornerRadius(pinButton, radius: chromeIcon / 2)
        applyControlCornerRadius(historyButton, radius: chromeIcon / 2)
        applyControlCornerRadius(updateButton, radius: chromeIcon / 2)
        applyControlCornerRadius(contextButton, radius: chromeIcon / 2)

        // Stacked order from top to bottom:
        // Main split pane (highest y) -> Subtranslate (middle y) -> QA pane (lowest y, just above splitY)
        var currentY = splitY
        if let qa = qaSection, let qaH = heights.qa {
            layoutQASection(qa, x: L.padding, y: currentY, width: contentWidth, height: qaH)
            currentY += qaH + L.sectionGap
        }
        if let sub = subSection, let subH = heights.sub {
            layoutSubSection(sub, x: L.padding, y: currentY, width: contentWidth, height: subH, panes: panes)
            currentY += subH + L.sectionGap
        }

        splitHost.frame = NSRect(x: L.padding, y: currentY, width: contentWidth, height: splitHeight)

        sourceCard.frame = NSRect(x: 0, y: 0, width: panes.left, height: splitHeight)
        splitDivider.frame = NSRect(x: panes.left, y: 14, width: max(1, L.dividerWidth), height: max(0, splitHeight - 28))
        splitDividerGradient?.frame = splitDivider.bounds
        splitHost.addSubview(splitDivider, positioned: .above, relativeTo: nil)
        resultCard.frame = NSRect(x: panes.left + L.dividerWidth, y: 0, width: panes.right, height: splitHeight)

        layoutPaneChrome(
            headerBar: sourceHeaderBar,
            headerLabel: sourceHeaderLabel,
            scrollView: inputScrollView,
            textView: inputTextView,
            trailingIcons: [speakSourceButton],
            paneWidth: panes.left,
            bodyHeight: bodyHeight
        )
        layoutPaneChrome(
            headerBar: resultHeaderBar,
            headerLabel: resultHeaderLabel,
            scrollView: textScrollView,
            textView: textView,
            trailingIcons: [speakResultButton, copyButton, saveWordButton],
            paneWidth: panes.right,
            bodyHeight: bodyHeight
        )

        // Bottom bar: Images | Proofread | Learn | Translate | spacer | EN | swap | VI
        translateButton.sizeToFit()
        learnButton.sizeToFit()
        imagesButton.sizeToFit()
        proofreadButton.sizeToFit()
        let btnH = L.controlHeight
        let btnY = bottomY
        let translateW = max(92, translateButton.frame.width)
        let learnW = max(72, learnButton.frame.width)
        let imagesW = max(72, imagesButton.frame.width)
        let proofreadW = max(88, proofreadButton.frame.width)
        imagesButton.frame = NSRect(
            x: L.padding,
            y: btnY,
            width: imagesW,
            height: btnH
        )
        proofreadButton.frame = NSRect(
            x: imagesButton.frame.maxX + 5,
            y: btnY,
            width: proofreadW,
            height: btnH
        )
        learnButton.frame = NSRect(
            x: proofreadButton.frame.maxX + 5,
            y: btnY,
            width: learnW,
            height: btnH
        )
        translateButton.frame = NSRect(
            x: learnButton.frame.maxX + 5,
            y: btnY,
            width: translateW,
            height: btnH
        )
        applyControlCornerRadius(translateButton)
        applyControlCornerRadius(learnButton)
        applyControlCornerRadius(imagesButton)
        applyControlCornerRadius(proofreadButton)

        let langH = L.languageControlHeight
        let langY = btnY + (btnH - langH) / 2
        let swapSize = L.swapWidth
        let trailingX = width - L.padding
        let availableLangWidth = max(140, trailingX - (translateButton.frame.maxX + 12))
        let dropdownWidth = min(L.languageWidth, max(75, (availableLangWidth - swapSize - 10) / 2))

        targetLanguageButton.frame = NSRect(
            x: trailingX - dropdownWidth,
            y: langY,
            width: dropdownWidth,
            height: langH
        )
        swapLanguagesButton.frame = NSRect(
            x: targetLanguageButton.frame.minX - 5 - swapSize,
            y: langY,
            width: swapSize,
            height: langH
        )
        sourceLanguageButton.frame = NSRect(
            x: swapLanguagesButton.frame.minX - 5 - dropdownWidth,
            y: langY,
            width: dropdownWidth,
            height: langH
        )
        applyControlCornerRadius(sourceLanguageButton, radius: L.languageCornerRadius)
        applyControlCornerRadius(targetLanguageButton, radius: L.languageCornerRadius)
        applyControlCornerRadius(swapLanguagesButton, radius: L.languageCornerRadius)
        styleLanguageButtonTitle(sourceLanguageButton, language: sourceLanguageSelection)
        styleLanguageButtonTitle(targetLanguageButton, language: targetLanguageSelection)

        qaInputField.frame = NSRect(
            x: L.padding,
            y: qaY,
            width: contentWidth,
            height: qaH
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
        headerBar.frame = NSRect(x: 0, y: bodyHeight, width: paneWidth, height: L.paneHeaderHeight)
        headerLabel.sizeToFit()
        let labelH = max(11, headerLabel.fittingSize.height)
        // Shift content down slightly so the speak/copy row has a little top padding.
        let labelY = max(0, ((L.paneHeaderHeight - labelH) / 2 - topInset).rounded(.towardZero))
        headerLabel.frame = NSRect(
            x: 12,
            y: labelY,
            width: max(28, min(headerLabel.fittingSize.width + 2, paneWidth - 52)),
            height: labelH
        )
        let headerIconY = max(0, (L.paneHeaderHeight - icon) / 2 - topInset)
        var iconX = paneWidth - 10 - icon
        for button in trailingIcons.reversed() {
            button.frame = NSRect(x: iconX, y: headerIconY, width: icon, height: icon)
            iconX -= icon + 4
        }
        if headerBar === sourceHeaderBar {
            speechRatePopUp.sizeToFit()
            speechRatePopUp.frame = NSRect(x: iconX - speechRatePopUp.frame.width, y: headerIconY + (icon - speechRatePopUp.frame.height) / 2, width: speechRatePopUp.frame.width, height: speechRatePopUp.frame.height)
        }
        scrollView.frame = NSRect(x: 0, y: 0, width: paneWidth, height: bodyHeight)
        scrollView.hasVerticalScroller = true
        textView.minSize = NSSize(width: 0, height: bodyHeight)
        if textView === inputTextView {
            imagePlaceholderLabel.frame = NSRect(x: 12, y: 10, width: max(0, paneWidth - 24), height: 22)
        }
    }

    /// Height the split body wants before the panel clamp — the sum of both sections plus the gap.
    func currentSplitPaneHeight(paneWidth: CGFloat) -> CGFloat {
        let primary = measuredPrimaryPaneHeight(paneWidth: paneWidth)
        var total = primary
        if let sub = subSection {
            total += ChromeLayout.sectionGap + measuredSubPaneHeight(sub, paneWidth: paneWidth)
        }
        if let qa = qaSection {
            total += ChromeLayout.sectionGap + measuredQAPaneHeight(qa, paneWidth: paneWidth * 2 + ChromeLayout.dividerWidth)
        }
        return total
    }

    func measuredPrimaryPaneHeight(paneWidth: CGFloat) -> CGFloat {
        paneHeight(
            source: inputTextView.attributedString(),
            result: textView.attributedString(),
            paneWidth: paneWidth
        )
    }

    func measuredSubPaneHeight(_ section: SubtranslateSection, paneWidth: CGFloat) -> CGFloat {
        paneHeight(
            source: section.sourceTextView.attributedString(),
            result: section.resultTextView.attributedString(),
            paneWidth: paneWidth
        )
    }

    func measuredQAPaneHeight(_ section: QAPaneSection, paneWidth: CGFloat) -> CGFloat {
        let L = ChromeLayout.self
        let measureWidth = max(80, paneWidth - 24)
        let measured = measuredTextHeight(section.textView.attributedString(), width: measureWidth) + 20
        let needed = L.paneHeaderHeight + measured
        return min(max(stackedMinPaneHeight, needed), maxSectionHeight)
    }

    func paneHeight(source: NSAttributedString, result: NSAttributedString, paneWidth: CGFloat) -> CGFloat {
        let L = ChromeLayout.self
        let measureWidth = max(80, paneWidth - 24)
        return PopoverLayoutMath.splitPaneHeight(
            sourceMeasured: measuredTextHeight(source, width: measureWidth) + 20,
            resultMeasured: measuredTextHeight(result, width: measureWidth) + 20,
            paneHeaderHeight: L.paneHeaderHeight,
            minPaneHeight: stackedMinPaneHeight,
            maxPaneHeight: maxSectionHeight
        )
    }

    /// Height ceiling for one pane — halved-ish once the subtranslate pane shares the panel.
    var maxSectionHeight: CGFloat {
        (subSection == nil && qaSection == nil) ? ChromeLayout.splitMaxPaneHeight : ChromeLayout.splitMaxStackedPaneHeight
    }

    /// Floor for one pane. Two panes at the single-pane floor don't fit a short panel, so stacking
    /// lowers it rather than letting the pair overflow.
    var stackedMinPaneHeight: CGFloat {
        (subSection == nil && qaSection == nil) ? ChromeLayout.splitMinPaneHeight : ChromeLayout.splitMinStackedPaneHeight
    }

    /// Resizes/repositions the panel around `size`. While the panel hasn't been dragged by the
    /// user, it stays anchored to `showMousePoint` (recomputed each time, so growth/shrinkage never
    /// straddles the cursor). Once dragged, resizes keep the panel's top-left corner fixed instead.
    func applyPanelFrame(size: NSSize) {
        guard let screenFrame = currentScreenFrame() else {
            isProgrammaticFrameChange = true
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: panel.isVisible)
            isProgrammaticFrameChange = false
            return
        }
        let newFrame: NSRect
        if userMovedWindow || panel.isVisible {
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
    func preferredPopoverHeight() -> CGFloat {
        let width = CGFloat(config.ui.width)
        let L = ChromeLayout.self
        let contentWidth = width - L.padding * 2
        let panes = PopoverLayoutMath.splitPaneWidth(contentWidth: contentWidth, divider: L.dividerWidth)
        let splitHeight = currentSplitPaneHeight(paneWidth: panes.left)
        let statusH = statusLabel.isHidden ? 0 : L.statusHeight
        return PopoverLayoutMath.splitPrismHeight(
            padding: L.padding,
            paddingBottom: L.paddingBottom,
            headerHeight: L.headerHeight,
            statusHeight: statusH,
            headerGap: L.headerGap,
            splitPaneHeight: splitHeight,
            qaInputHeight: L.qaInputHeight,
            footerGap: L.footerGap,
            bottomBarHeight: L.bottomBarHeight
        )
    }

    func maxPopoverHeight() -> CGFloat {
        // A second pane needs its own room on top of the single-pane budget, but never more than
        // the screen can show.
        var stackedAllowance: CGFloat = 0
        if subSection != nil { stackedAllowance += ChromeLayout.splitMaxStackedPaneHeight + ChromeLayout.sectionGap }
        if qaSection != nil { stackedAllowance += ChromeLayout.splitMaxStackedPaneHeight + ChromeLayout.sectionGap }
        let base = CGFloat(config.ui.height) + 300 + stackedAllowance
        guard let screen = currentScreenFrame() else { return base }
        return min(base, screen.height - 40)
    }

    func currentPopoverHeight() -> CGFloat {
        // Hug content — don't force config.ui.height as a floor (that left empty chrome).
        min(max(preferredPopoverHeight(), 220), maxPopoverHeight())
    }

    func measuredTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        PopoverLayoutMath.measuredTextHeight(text, width: width)
    }

}