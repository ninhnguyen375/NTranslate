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
        configureChromeIconButton(reviewButton, symbol: "rectangle.stack", action: #selector(openReviewWindow), label: "Review SRS")

        reviewBadgeLabel.font = .systemFont(ofSize: 8, weight: .bold)
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
        inputContextLabel.font = .systemFont(ofSize: 10, weight: .regular)
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
        configurePrimaryButton(askButton, title: "Ask", symbol: "text.bubble", action: #selector(askButtonClicked), accent: false)
        askButton.toolTip = "Ask a follow-up question (⌘K)"
        askButton.setAccessibilityLabel("Ask")
        updateShortcutLabels()
        configureIconButton(speakSourceButton, symbol: "speaker.wave.2", action: #selector(speakInput), label: "Speak source")
        configureIconButton(speakResultButton, symbol: "speaker.wave.2", action: #selector(speakResult), label: "Speak translation")
        configureIconButton(retryButton, symbol: "arrow.clockwise", action: #selector(retryRequest), label: "Retry / Fetch fresh")
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
        sourceCard.addSubview(inputContextLabel)
        sourceCard.addSubview(inputScrollView)
        sourceCard.addSubview(imagePlaceholderLabel)

        resultHeaderBar.addSubview(resultHeaderLabel)
        resultHeaderBar.addSubview(speakResultButton)
        resultHeaderBar.addSubview(retryButton)
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
        chromeHost.addSubview(imagesButton)
        chromeHost.addSubview(proofreadButton)
        chromeHost.addSubview(learnButton)
        chromeHost.addSubview(translateButton)
        chromeHost.addSubview(askButton)

        configureQAInputBar()
        chromeHost.addSubview(qaInputField)
        qaInputField.isHidden = true

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

    /// Refreshes the small shortcut hint drawn inside Learn/Proofread/Ask — call after config
    /// (re)load since the global hotkeys are user-configurable in Settings.
    func updateShortcutLabels() {
        applyShortcutLabel(translateButton, title: "Translate", shortcut: config.hotkey.displayString)
        applyShortcutLabel(learnButton, title: "Learn", shortcut: config.learnHotkey.displayString)
        applyShortcutLabel(proofreadButton, title: "Proofread", shortcut: config.proofreadHotkey.displayString)
        applyShortcutLabel(askButton, title: "Ask", shortcut: "⌘K")
    }

    private func applyShortcutLabel(_ button: NSButton, title: String, shortcut: String) {
        let text = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: ChromeLayout.controlFontSize, weight: .regular),
                .foregroundColor: NSColor.controlTextColor
            ]
        )
        text.append(NSAttributedString(
            string: "  " + shortcut,
            attributes: [
                .font: NSFont.systemFont(ofSize: ChromeLayout.controlFontSize - 2, weight: .regular),
                .foregroundColor: Palette.mutedText
            ]
        ))
        button.attributedTitle = text
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

}