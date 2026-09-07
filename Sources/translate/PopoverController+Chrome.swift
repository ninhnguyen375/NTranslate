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
        // AppKit pushes the new appearance down the tree one view at a time, so a repaint
        // started from this callback still resolves subviews against the OLD appearance —
        // that is what left part of the popup on the previous theme until a restart.
        // One runloop hop later every subview reports the new appearance.
        chromeHost.onAppearanceChange = { [weak self] in
            DispatchQueue.main.async { self?.reflowLayout() }
        }

        let titleCell = VerticallyCenteredTextFieldCell(textCell: "NTranslate")
        titleCell.horizontalInset = 0
        titleLabel.cell = titleCell
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.isBezeled = false
        titleLabel.stringValue = "NTranslate"
        titleLabel.font = .systemFont(ofSize: ChromeLayout.titleFontSize, weight: .bold)
        titleLabel.textColor = Palette.titleText
        titleLabel.drawsBackground = false
        titleLabel.alignment = .left
        titleLabel.toolTip = "NTranslate v\(Self.buildVersion)"

        let statusCell = VerticallyCenteredTextFieldCell(textCell: "")
        statusCell.horizontalInset = 0
        statusCell.centersMultiline = true
        statusCell.wraps = true
        statusCell.isScrollable = false
        statusLabel.cell = statusCell
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.isBezeled = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = Palette.mutedText
        statusLabel.alignment = .left
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        statusLabel.drawsBackground = false

        configureChromeIconButton(closeButton, symbol: "xmark", action: #selector(closePopover), label: "Close")
        configureChromeIconButton(pinButton, symbol: "pin", action: #selector(togglePin), label: "Pin")
        configureChromeIconButton(historyButton, symbol: "clock.arrow.circlepath", action: #selector(openTranslationHistory), label: "Translation History")
        configureChromeIconButton(reviewButton, symbol: "rectangle.stack", action: #selector(openReviewWindow), label: "Spaced Repetition")

        reviewBadgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        reviewBadgeLabel.textColor = .white
        reviewBadgeLabel.backgroundColor = .clear
        reviewBadgeLabel.drawsBackground = false
        reviewBadgeLabel.alignment = .center
        reviewBadgeLabel.wantsLayer = true
        reviewBadgeLabel.layer?.backgroundColor = NSColor.systemRed.cgColor
        reviewBadgeLabel.layer?.cornerRadius = 6.5
        reviewBadgeLabel.layer?.masksToBounds = true
        reviewBadgeLabel.isHidden = true

        configureChromeIconButton(updateButton, symbol: "arrow.triangle.2.circlepath", action: #selector(checkForUpdatesClicked), label: "Check for Updates")
        updateButton.isHidden = true
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
        // ponytail: plain text only, so pasted rich text keeps our palette instead of the source colour
        inputTextView.isRichText = false
        inputTextView.importsGraphics = false
        inputTextView.delegate = self
        inputTextView.onResignFirstResponder = { [weak self] in
            self?.hideFloatingSelectionBar()
        }
        inputTextView.onImagePasted = { [weak self] imageData in
            self?.setPendingImage(imageData)
            self?.inputTextView.string = ""
        }
        inputTextView.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
        inputTextView.drawsBackground = false
        inputTextView.textColor = Palette.bodyText
        inputTextView.insertionPointColor = .controlAccentColor
        inputTextView.focusRingType = .default
        inputTextView.textContainerInset = NSSize(width: 12, height: 10)
        inputTextView.minSize = NSSize(width: 0, height: 40)
        inputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.autoresizingMask = [.width]
        inputTextView.textContainer?.widthTracksTextView = true

        inputScrollView.borderType = .noBorder
        inputScrollView.drawsBackground = false
        inputScrollView.focusRingType = .default
        inputScrollView.hasVerticalScroller = true
        inputScrollView.hasHorizontalScroller = false
        inputScrollView.autohidesScrollers = true
        inputScrollView.scrollerStyle = .overlay
        inputScrollView.documentView = inputTextView
        inputContextLabel.font = .systemFont(ofSize: 11, weight: .regular)
        inputContextLabel.textColor = Palette.placeholderText
        inputContextLabel.lineBreakMode = .byTruncatingTail
        inputContextLabel.maximumNumberOfLines = 1
        inputContextLabel.isHidden = true
        imagePlaceholderLabel.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
        imagePlaceholderLabel.textColor = Palette.placeholderText
        imagePlaceholderLabel.isHidden = true
        imagePlaceholderLabel.setAccessibilityLabel("Image from clipboard")

        textView.isEditable = false
        textView.isSelectable = true
        textView.delegate = self
        textView.onResignFirstResponder = { [weak self] in
            self?.hideFloatingSelectionBar()
        }
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
        textView.textColor = Palette.bodyText
        textView.focusRingType = .default
        textView.textContainerInset = NSSize(width: 12, height: 10)
        textView.minSize = NSSize(width: 0, height: 40)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        textScrollView.borderType = .noBorder
        textScrollView.drawsBackground = false
        textScrollView.focusRingType = .default
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.scrollerStyle = .overlay
        textScrollView.documentView = textView

        configureActionRow(mainActionRow, isSub: false)
        updateShortcutLabels()
        configureIconButton(speakSourceButton, symbol: "speaker.wave.2", action: #selector(speakInput), label: "Speak source")
        configureIconButton(speakSourceSlowButton, symbol: "tortoise", action: #selector(speakInputSlow), label: "Speak source slowly")
        configureIconButton(speakResultButton, symbol: "speaker.wave.2", action: #selector(speakResult), label: "Speak translation")
        configureIconButton(speakResultSlowButton, symbol: "tortoise", action: #selector(speakResultSlow), label: "Speak translation slowly")
        configureIconButton(retryButton, symbol: "arrow.clockwise", action: #selector(retryRequest), label: "Retry / Fetch fresh")
        configureIconButton(copyButton, symbol: "doc.on.doc", action: #selector(copyResult), label: "Copy")
        configureIconButton(saveWordButton, symbol: "bookmark", action: #selector(toggleSaveWord), label: "Save Word")
        configureSetupActionButton(setupOpenSettingsButton, title: "Open Settings", action: #selector(openSettingsMenu))
        configureSetupActionButton(setupGrantAccessButton, title: "Grant Accessibility", action: #selector(requestAccessibilityPermissionMenu))
        configureSetupActionButton(inPaneRetryButton, title: "Retry", action: #selector(retryRequest))
        setupOpenSettingsButton.isHidden = true
        setupGrantAccessButton.isHidden = true
        inPaneRetryButton.isHidden = true

        updateSpeakButtons()
        updateSaveWordButton()
        updateBusyState()
        languageSelectionChanged()

        sourceHeaderBar.addSubview(sourceHeaderLabel)
        sourceHeaderBar.addSubview(speakSourceButton)
        sourceHeaderBar.addSubview(speakSourceSlowButton)
        sourceCard.addSubview(sourceHeaderBar)
        sourceCard.addSubview(inputContextLabel)
        sourceCard.addSubview(inputScrollView)
        sourceCard.addSubview(imagePlaceholderLabel)

        resultHeaderBar.addSubview(resultHeaderLabel)
        resultHeaderBar.addSubview(speakResultButton)
        resultHeaderBar.addSubview(speakResultSlowButton)
        resultHeaderBar.addSubview(retryButton)
        resultHeaderBar.addSubview(copyButton)
        resultHeaderBar.addSubview(saveWordButton)
        resultCard.addSubview(resultHeaderBar)
        resultCard.addSubview(textScrollView)
        resultCard.addSubview(setupOpenSettingsButton)
        resultCard.addSubview(setupGrantAccessButton)
        resultCard.addSubview(inPaneRetryButton)

        splitHost.addSubview(sourceCard)
        splitHost.addSubview(splitDivider)
        splitHost.addSubview(resultCard)

        chromeHost.addSubview(titleLabel)
        chromeHost.addSubview(updateButton)
        chromeHost.addSubview(reviewButton)
        chromeHost.addSubview(reviewBadgeLabel)
        chromeHost.addSubview(historyButton)
        chromeHost.addSubview(pinButton)
        chromeHost.addSubview(closeButton)
        chromeHost.addSubview(splitHost)
        chromeHost.addSubview(sourceLanguageButton)
        chromeHost.addSubview(swapLanguagesButton)
        chromeHost.addSubview(targetLanguageButton)
        // After the language controls so setStatus is not painted underneath them.
        chromeHost.addSubview(statusLabel)
        mainActionRow.addToSuperview(chromeHost)

        configureQAInputBar()
        chromeHost.addSubview(qaInputField)
        qaInputField.isHidden = true

        configureFloatingToolbar()
        chromeHost.addSubview(selectionFloatingBar)

        let containerHost = NSView(frame: glassContainer.bounds)
        containerHost.autoresizingMask = [.width, .height]
        LiquidGlassChrome.clipToShell(containerHost)
        containerHost.addSubview(shellGlass)
        glassContainer.contentView = containerHost

        layoutSplitPrism(width: width, height: height)
        // Glass stays the window contentView so NSGlassEffectView can sample the
        // desktop. chromeHost is embedded as the glass contentView (Apple's
        // guaranteed z-order). Controls always live there — never reparent them
        // out of the glass or the shell disappears.
        LiquidGlassChrome.clipToShell(chromeHost)
        panel.contentView = glassContainer
        LiquidGlassChrome.applyWindowShape(panel)
        panel.setFrame(NSRect(origin: panel.frame.origin, size: NSSize(width: width, height: height)), display: false)
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
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        splitHost.layer?.borderWidth = 1
        splitHost.layer?.borderColor = Palette.cg(Palette.hairline, in: splitHost)
        let fill = reduceTransparency ? Palette.opaquePaneFill : Palette.paneFill
        splitHost.layer?.backgroundColor = Palette.cg(fill, in: splitHost)
        // Never hide shellGlass: chromeHost is its contentView.
        // Window backing stays clear so the rectangular frame cannot paint a black
        // box around the rounded clip. Opaque fill lives on chromeHost (already clipped).
        panel.backgroundColor = .clear
        if reduceTransparency {
            chromeHost.layer?.backgroundColor = Palette.cg(Palette.opaquePaneFill, in: chromeHost)
        } else {
            chromeHost.layer?.backgroundColor = Palette.cg(Palette.chromeFill, in: chromeHost)
        }
        splitDividerGradient?.colors = Self.dividerGradientColors(in: splitDivider)
    }

    /// Capsule: radius is half the shorter side after the frame is set.
    /// A CSS-style 999 on a zero/small frame clips the control to nothing.
    func applyControlCornerRadius(_ view: NSView) {
        let width = max(view.bounds.width, view.frame.width)
        let height = max(view.bounds.height, view.frame.height)
        guard width > 2, height > 2 else { return }
        view.wantsLayer = true
        view.layer?.cornerRadius = min(width, height) / 2
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    func glassSymbol(_ name: String, accessibility: String?, accent: Bool) -> NSImage? {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: accessibility)
        let tint: NSColor = accent ? .white : Palette.chromeIconTint
        let config = NSImage.SymbolConfiguration(paletteColors: [tint])
            .applying(NSImage.SymbolConfiguration(pointSize: 12, weight: .medium))
        return base?.withSymbolConfiguration(config)
    }

    func applyActionChipLabel(_ button: NSButton, title: String, symbol: String, accent: Bool) {
        if let chip = button as? ActionChipButton {
            chip.chipSymbol = symbol
        }
        let font = NSFont.systemFont(ofSize: ChromeLayout.controlFontSize, weight: .medium)
        let color: NSColor = accent ? .white : Palette.actionChipLabel
        button.image = nil
        button.imagePosition = .noImage
        button.alignment = .center
        // The icon is baked into a bitmap, so a dynamic tint has to be resolved against the
        // button's own appearance — otherwise it keeps the light color after a switch to dark.
        var icon: NSImage?
        button.effectiveAppearance.performAsCurrentDrawingAppearance {
            icon = PopoverLayoutMath.chipIconImage(
                symbol: symbol,
                tint: color,
                pointSize: 12,
                weight: .semibold
            )
        }
        button.attributedTitle = PopoverLayoutMath.actionChipAttributedTitle(
            title: title,
            icon: icon,
            font: font,
            color: color
        )
        button.setAccessibilityLabel(title)
        button.contentTintColor = color
    }

    func applyAccentButtonTitle(_ button: NSButton, title: String, symbol: String? = nil) {
        let resolved = symbol
            ?? (button as? ActionChipButton)?.chipSymbol
            ?? "arrow.right.circle"
        applyActionChipLabel(button, title: title, symbol: resolved, accent: true)
        applyActionChipSize(button, title: title)
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
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = Palette.paneLabel
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
    }

    func paneLanguageCode(_ language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == LanguageDetector.autoDetect || trimmed.caseInsensitiveCompare("Auto detect") == .orderedSame {
            return "AUTO"
        }
        if let code = Self.iso6391Codes[trimmed] { return code }
        let folded = Self.iso6391Codes.first { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }?.value
        return folded ?? "??"
    }

    /// ISO 639-1 pane badges. Unknown names stay "??" — never a blind prefix(2) ("Portuguese" is PT, not PO).
    static let iso6391Codes: [String: String] = [
        "English": "EN",
        "Vietnamese": "VI",
        "Chinese": "ZH",
        "Chinese (Simplified)": "ZH",
        "Chinese (Traditional)": "ZH",
        "Japanese": "JA",
        "Korean": "KO",
        "French": "FR",
        "German": "DE",
        "Spanish": "ES",
        "Portuguese": "PT",
        "Portuguese (Brazil)": "PT",
        "Italian": "IT",
        "Russian": "RU",
        "Arabic": "AR",
        "Hindi": "HI",
        "Thai": "TH",
        "Indonesian": "ID",
        "Malay": "MS",
        "Dutch": "NL",
        "Polish": "PL",
        "Turkish": "TR",
        "Swedish": "SV",
        "Norwegian": "NO",
        "Danish": "DA",
        "Finnish": "FI",
        "Greek": "EL",
        "Hebrew": "HE",
        "Czech": "CS",
        "Romanian": "RO",
        "Hungarian": "HU",
        "Ukrainian": "UK",
        "Bengali": "BN",
        "Tamil": "TA",
        "Telugu": "TE",
        "Urdu": "UR",
        "Persian": "FA",
        "Tagalog": "TL",
        "Filipino": "TL",
        "Khmer": "KM",
        "Lao": "LO",
        "Burmese": "MY",
        "Nepali": "NE",
        "Sinhala": "SI",
        "Slovak": "SK",
        "Bulgarian": "BG",
        "Croatian": "HR",
        "Serbian": "SR",
        "Catalan": "CA",
        "Welsh": "CY",
        "Irish": "GA",
        "Swahili": "SW",
    ]

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

    /// Wires one action row. The subtranslate row runs the same five actions against the sub pane.
    func configureActionRow(_ row: ActionRowSection, isSub: Bool) {
        configurePrimaryButton(
            row.translateButton, title: "Translate", symbol: "arrow.right.circle",
            action: isSub ? #selector(runSubTranslate) : #selector(runTranslate), accent: true
        )
        configurePrimaryButton(
            row.learnButton, title: "Learn", symbol: "brain.head.profile",
            action: isSub ? #selector(runSubLearn) : #selector(runLearn), accent: false
        )
        row.learnButton.setAccessibilityLabel("Learn")
        configurePrimaryButton(
            row.imagesButton, title: "Images", symbol: "photo",
            action: isSub ? #selector(runSubImages) : #selector(runImages), accent: false
        )
        row.imagesButton.setAccessibilityLabel("Images")
        configurePrimaryButton(
            row.proofreadButton, title: "Proofread", symbol: "text.badge.checkmark",
            action: isSub ? #selector(runSubProofread) : #selector(runProofread), accent: false
        )
        row.proofreadButton.setAccessibilityLabel("Proofread")
        configurePrimaryButton(
            row.askButton, title: "Ask", symbol: "text.bubble",
            action: isSub ? #selector(askSubClicked) : #selector(askButtonClicked), accent: false
        )
        row.askButton.setAccessibilityLabel("Ask")
        applyShortcutLabels(to: row)
    }

    func configurePrimaryButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        action: Selector?,
        accent: Bool
    ) {
        applyActionChipLabel(button, title: title, symbol: symbol, accent: accent)
        button.target = action == nil ? nil : self
        button.action = action
        // Same system bezel as the chrome icon buttons above: it owns the capsule, the
        // light/dark fill and the hover state, so the chips match the rest of the popup.
        button.bezelStyle = .glass
        button.isBordered = true
        button.focusRingType = .none
        button.refusesFirstResponder = true
        button.controlSize = .regular
        button.font = .systemFont(ofSize: ChromeLayout.controlFontSize, weight: .medium)
        button.lineBreakMode = .byClipping
        applyActionChipSize(button, title: title)
    }

    /// Pins each action chip to its own fixed size — independent of the window and `fittingSize`.
    func applyActionChipSize(_ button: NSButton, title: String) {
        let size = NSSize(
            width: actionChipWidth(forTitle: title),
            height: ChromeLayout.bottomBarHeight
        )
        if let chip = button as? ActionChipButton {
            chip.lockedSize = size
        }
        button.setFrameSize(size)
        applyActionChipChrome(button)
    }

    func isActionChipAccent(_ button: NSButton) -> Bool {
        isActionChipAccentTitle(PopoverLayoutMath.visibleActionChipTitle(of: button))
    }

    func isActionChipAccentTitle(_ title: String) -> Bool {
        title == "Translate" || title == "Stop"
    }

    /// Only the accent chip keeps a capsule; the rest are plain text, so they drop the bezel padding.
    func actionChipWidth(forTitle title: String) -> CGFloat {
        let base = PopoverLayoutMath.ActionChip.width(forTitle: title)
        return isActionChipAccentTitle(title) ? base : base - 2 * PopoverLayoutMath.actionButtonPadX
    }

    /// The `.glass` bezel draws the chip fill and hover; the accent tint and the capsule
    /// mask (the bezel squares off at this width) are ours.
    func applyActionChipChrome(_ button: NSButton) {
        let accent = isActionChipAccent(button)
        button.isBordered = accent
        button.bezelColor = accent ? .controlAccentColor : nil
        button.layer?.backgroundColor = nil
        button.layer?.borderWidth = 0
        if accent {
            applyControlCornerRadius(button)
        } else {
            button.layer?.cornerRadius = 0
            button.layer?.masksToBounds = false
        }
        // Repaints the baked icon for the current appearance (reflow runs on light/dark switch).
        if let chip = button as? ActionChipButton, !chip.chipSymbol.isEmpty {
            applyActionChipLabel(
                chip,
                title: PopoverLayoutMath.visibleActionChipTitle(of: chip),
                symbol: chip.chipSymbol,
                accent: isActionChipAccent(chip)
            )
        }
    }

    /// Refreshes action-row tooltips after config reload. Titles stay a single verb.
    func updateShortcutLabels() {
        applyShortcutLabels(to: mainActionRow)
        if let subRow = subSection?.actionRow {
            applyShortcutLabels(to: subRow)
        }
    }

    func applyShortcutLabels(to row: ActionRowSection) {
        let isSub = row === subSection?.actionRow
        applyActionTooltip(
            row.translateButton,
            title: "Translate",
            help: "Translate the selection (⌘↩ · \(config.hotkey.displayString))"
        )
        applyActionTooltip(
            row.learnButton,
            title: "Learn",
            help: "Explain the word or sentence (⌘L · \(config.learnHotkey.displayString))"
        )
        applyActionTooltip(
            row.proofreadButton,
            title: "Proofread",
            help: "Check grammar in the source language (⌘P · \(config.proofreadHotkey.displayString))"
        )
        applyActionTooltip(
            row.askButton,
            title: "Ask",
            help: isSub
                ? "Ask a follow-up question about the sub-translation, with the main pane as context (⌘K)"
                : "Ask a follow-up question (⌘K)"
        )
        applyActionTooltip(
            row.imagesButton,
            title: "Images",
            help: isSub
                ? "Search images for the sub-translation (⌘I)"
                : "Search images in the browser (⌘I)"
        )
    }

    func applyActionTooltip(_ button: NSButton, title: String, help: String) {
        if let chip = button as? ActionChipButton, !chip.chipSymbol.isEmpty {
            applyActionChipLabel(
                chip,
                title: title,
                symbol: chip.chipSymbol,
                accent: title == "Translate" || title == "Stop"
            )
        } else if isActionChipAccent(button) {
            applyAccentButtonTitle(button, title: title)
        } else {
            button.title = title
        }
        button.toolTip = help
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(help)
    }

    func configureChromeIconButton(_ button: NSButton, symbol: String, action: Selector, label: String) {
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(symbolConfig)
        button.imagePosition = .imageOnly
        button.isBordered = true
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.target = self
        button.action = action
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.contentTintColor = Palette.chromeIconTint
    }

    func configureSetupActionButton(_ button: NSButton, title: String, action: Selector) {
        button.title = title
        button.bezelStyle = .flexiblePush
        button.controlSize = .regular
        button.font = .systemFont(ofSize: ChromeLayout.controlFontSize, weight: .medium)
        button.target = self
        button.action = action
        button.toolTip = title
        button.setAccessibilityLabel(title)
        applyControlCornerRadius(button)
    }

    /// Shared metrics for the speak / copy / save glyphs so they line up with each other.
    var paneIconSymbolConfiguration: NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
    }

    func configureIconButton(_ button: NSButton, symbol: String, action: Selector, label: String) {
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        // One symbol configuration for every pane icon: unconfigured symbol images keep their own
        // natural canvas, so speaker and tortoise ended up on different centres in the same row.
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(paneIconSymbolConfiguration)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
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
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")?
            .withSymbolConfiguration(paneIconSymbolConfiguration)
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = Palette.iconTint
    }

}