import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation

extension NSAttributedString {
    static func plainDisplay(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }
}

/// Borderless windows don't become key by default; override so the input text view can accept typing.
final class TranslatePanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PopoverController: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate, NSMenuDelegate {
    private enum SpeechKind {
        case source
        case result
    }

    private struct PrefetchedSpeech {
        let text: String
        let model: String
        let data: Data
    }

    private static let buildVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    /// Fixed source field height — scrolls like the result area, but stays shorter.
    private enum ChromeLayout {
        static let padding: CGFloat = 8
        static let headerHeight: CGFloat = 18
        static let statusHeight: CGFloat = 14
        static let languageHeight: CGFloat = 26
        static let sourceBodyHeight: CGFloat = 56
        static let sourceFooterHeight: CGFloat = 28
        static let resultHeaderHeight: CGFloat = 26
        static let sectionGap: CGFloat = 6
        static let languageGap: CGFloat = 6
        static let primaryButtonHeight: CGFloat = 22
        static let iconButtonSize: CGFloat = 20
        static let minResultBodyHeight: CGFloat = 140
        static let maxResultBodyHeight: CGFloat = 500
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = TranslatePanelWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    private let textView = NSTextView(frame: .zero)
    private let textScrollView = NSScrollView(frame: .zero)
    private let inputTextView = NSTextView(frame: .zero)
    private let inputScrollView = NSScrollView(frame: .zero)
    private let sourceCard = NSView(frame: .zero)
    private let sourceFooter = NSView(frame: .zero)
    private let resultCard = NSView(frame: .zero)
    private let resultHeaderBar = NSView(frame: .zero)
    private let resultHeaderLabel = NSTextField(labelWithString: "Translation")
    private let sourceLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let swapLanguagesButton = NSButton(frame: .zero)
    private let pinButton = NSButton(frame: .zero)
    private let closeButton = NSButton(frame: .zero)
    private let translateButton = NSButton(frame: .zero)
    private let learnButton = NSButton(frame: .zero)
    private let copyButton = NSButton(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "Translate")
    private let statusLabel = NSTextField(labelWithString: "")
    private let speakSourceButton = NSButton(frame: .zero)
    private let speakResultButton = NSButton(frame: .zero)
    private var translator: Translator?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandlerRef: EventHandlerRef?
    private var config = AppConfig.load()
    private var audioPlayer: AVAudioPlayer?
    private var isSpeakingSource = false
    private var isSpeakingResult = false
    private var requestGeneration = 0
    private var isRequestInFlight = false
    private var keyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var restoresPreviousAppOnClose = false
    private var activatesAppOnShow = false
    private var isPastingResult = false
    private var prefetchedSpeech: [SpeechKind: PrefetchedSpeech] = [:]
    private var recentTargets: [String] = []
    private static let lastTargetLangKey = "local.ninh.ntranslate.lastTargetLang"
    private var showMousePoint: NSPoint = .zero
    private var userMovedWindow = false
    private var isProgrammaticFrameChange = false
    private var isPinned = false
    private var statusClearWorkItem: DispatchWorkItem?
    private var copyFlashWorkItem: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(systemSymbolName: "translate", accessibilityDescription: "NTranslate") {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "T"
        }
        statusItem.button?.action = #selector(manualToggle)
        statusItem.button?.target = self
        CrashRecovery.presentCrashAlertIfNeeded()
        requestAccessibilityPermissionIfNeeded()
        panel.isOpaque = false
        panel.ignoresMouseEvents = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        buildPopover()
        buildMenu()
        installHotKeyEventHandler()
        reloadConfig()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.restoresPreviousAppOnClose = true
                self.closePanel()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command, event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                self.runTranslate()
                return nil
            }
            if flags == [.command, .shift], event.keyCode == UInt16(kVK_ANSI_C) {
                self.copyResult()
                return nil
            }
            if flags == [.command, .shift], event.keyCode == UInt16(kVK_ANSI_L) {
                self.runLearn()
                return nil
            }
            return event
        }
    }


    private func buildPopover() {
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        let L = ChromeLayout.self
        let contentWidth = width - L.padding * 2
        let sourceCardHeight = L.sourceBodyHeight + L.sourceFooterHeight
        let languageY = height - L.padding - L.headerHeight - L.statusHeight - L.languageGap - L.languageHeight
        let sourceCardY = languageY - L.sectionGap - sourceCardHeight
        let resultY = L.padding
        let resultHeight = max(L.resultHeaderHeight + L.minResultBodyHeight, sourceCardY - L.sectionGap - resultY)

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 14
        root.layer?.backgroundColor = NSColor.white.cgColor
        root.appearance = NSAppearance(named: .aqua)
        panel.appearance = NSAppearance(named: .aqua)

        let titleText = NSMutableAttributedString(
            string: "NTranslate",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: NSColor.labelColor]
        )
        titleText.append(NSAttributedString(
            string: "  v\(Self.buildVersion)",
            attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        titleLabel.attributedStringValue = titleText
        titleLabel.frame = NSRect(x: L.padding, y: height - L.padding - L.headerHeight, width: 200, height: L.headerHeight)

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        statusLabel.frame = NSRect(
            x: L.padding,
            y: height - L.padding - L.headerHeight - L.statusHeight,
            width: contentWidth - 50,
            height: L.statusHeight
        )

        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePopover)
        closeButton.frame = NSRect(x: width - L.padding - 18, y: height - L.padding - L.headerHeight + 1, width: 18, height: 18)

        pinButton.title = ""
        pinButton.imagePosition = .imageOnly
        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.frame = NSRect(x: width - L.padding - 18 - 22, y: height - L.padding - L.headerHeight + 1, width: 18, height: 18)
        updatePinButton()

        configureLanguageControls()
        let languageDropdownWidth = (contentWidth - 38 - 12) / 2
        sourceLanguagePopup.frame = NSRect(x: L.padding, y: languageY, width: languageDropdownWidth, height: L.languageHeight)
        swapLanguagesButton.frame = NSRect(x: sourceLanguagePopup.frame.maxX + 6, y: languageY, width: 38, height: L.languageHeight)
        targetLanguagePopup.frame = NSRect(x: swapLanguagesButton.frame.maxX + 6, y: languageY, width: languageDropdownWidth, height: L.languageHeight)

        // Source card: text + footer actions (Translate / Learn / Speak)
        styleCard(sourceCard, fill: NSColor(calibratedWhite: 0.98, alpha: 1))
        sourceCard.frame = NSRect(x: L.padding, y: sourceCardY, width: contentWidth, height: sourceCardHeight)

        inputTextView.isEditable = true
        inputTextView.isSelectable = true
        inputTextView.delegate = self
        inputTextView.font = .systemFont(ofSize: 13)
        inputTextView.drawsBackground = false
        inputTextView.textColor = .labelColor
        inputTextView.textContainerInset = NSSize(width: 6, height: 6)
        inputTextView.minSize = NSSize(width: 0, height: L.sourceBodyHeight)
        inputTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.autoresizingMask = [.width]
        inputTextView.textContainer?.widthTracksTextView = true

        inputScrollView.borderType = .noBorder
        inputScrollView.drawsBackground = false
        inputScrollView.hasVerticalScroller = true
        inputScrollView.hasHorizontalScroller = false
        inputScrollView.autohidesScrollers = true
        inputScrollView.documentView = inputTextView

        sourceFooter.wantsLayer = true
        sourceFooter.layer?.backgroundColor = NSColor(calibratedWhite: 0.953, alpha: 1).cgColor

        configurePrimaryButton(translateButton, title: "Translate", symbol: "arrow.right.circle", action: #selector(runTranslate), accent: true)
        configurePrimaryButton(learnButton, title: "Learn", symbol: "brain.head.profile", action: #selector(runLearn), accent: false)
        configureIconButton(speakSourceButton, symbol: "speaker.wave.2", action: #selector(speakInput), label: "Speak source")
        configureIconButton(speakResultButton, symbol: "speaker.wave.2", action: #selector(speakResult), label: "Speak translation")
        configureIconButton(copyButton, symbol: "doc.on.doc", action: #selector(copyResult), label: "Copy")

        updateSpeakButtons()
        updateBusyState()
        languageSelectionChanged()

        sourceCard.addSubview(inputScrollView)
        sourceFooter.addSubview(translateButton)
        sourceFooter.addSubview(learnButton)
        sourceFooter.addSubview(speakSourceButton)
        sourceCard.addSubview(sourceFooter)

        // Result card: header chrome (Speak / Copy) + body
        styleCard(resultCard, fill: NSColor(calibratedWhite: 0.97, alpha: 1))
        resultCard.frame = NSRect(x: L.padding, y: resultY, width: contentWidth, height: resultHeight)

        resultHeaderBar.wantsLayer = true
        resultHeaderBar.layer?.backgroundColor = NSColor(calibratedWhite: 0.933, alpha: 1).cgColor

        resultHeaderLabel.stringValue = "Translation"
        resultHeaderLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        resultHeaderLabel.textColor = .secondaryLabelColor
        resultHeaderLabel.isBezeled = false
        resultHeaderLabel.drawsBackground = false
        resultHeaderLabel.isEditable = false

        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.minSize = NSSize(width: 0, height: max(0, resultHeight - L.resultHeaderHeight))
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        textScrollView.borderType = .noBorder
        textScrollView.drawsBackground = false
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.documentView = textView

        resultHeaderBar.addSubview(resultHeaderLabel)
        resultHeaderBar.addSubview(speakResultButton)
        resultHeaderBar.addSubview(copyButton)
        resultCard.addSubview(resultHeaderBar)
        resultCard.addSubview(textScrollView)

        layoutInlineChrome(width: width, height: height)

        root.addSubview(titleLabel)
        root.addSubview(statusLabel)
        root.addSubview(pinButton)
        root.addSubview(closeButton)
        root.addSubview(sourceLanguagePopup)
        root.addSubview(swapLanguagesButton)
        root.addSubview(targetLanguagePopup)
        root.addSubview(sourceCard)
        root.addSubview(resultCard)
        panel.contentView = root
        panel.setFrame(NSRect(origin: panel.frame.origin, size: root.frame.size), display: false)
    }

    private func styleCard(_ view: NSView, fill: NSColor) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        view.layer?.backgroundColor = fill.cgColor
    }

    private func configurePrimaryButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        action: Selector,
        accent: Bool
    ) {
        button.title = title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        if accent {
            button.bezelColor = .controlAccentColor
        } else {
            button.bezelColor = nil
        }
    }

    private func configureIconButton(_ button: NSButton, symbol: String, action: Selector, label: String) {
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
        button.contentTintColor = .secondaryLabelColor
    }

    private func resetCopyButtonAppearance() {
        copyButton.title = ""
        copyButton.attributedTitle = NSAttributedString(string: "")
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = .secondaryLabelColor
    }

    private func reflowLayout() {
        guard panel.contentView != nil else { return }
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        layoutInlineChrome(width: width, height: height)
        applyPanelFrame(size: NSSize(width: width, height: height))
    }

    private func layoutInlineChrome(width: CGFloat, height: CGFloat) {
        guard let root = panel.contentView else { return }
        let L = ChromeLayout.self
        let contentWidth = width - L.padding * 2
        let sourceCardHeight = L.sourceBodyHeight + L.sourceFooterHeight
        let languageY = height - L.padding - L.headerHeight - L.statusHeight - L.languageGap - L.languageHeight
        let sourceCardY = languageY - L.sectionGap - sourceCardHeight
        let resultY = L.padding
        let resultHeight = max(L.resultHeaderHeight + L.minResultBodyHeight, sourceCardY - L.sectionGap - resultY)
        let resultBodyHeight = max(0, resultHeight - L.resultHeaderHeight)

        root.frame = NSRect(x: 0, y: 0, width: width, height: height)
        titleLabel.frame = NSRect(x: L.padding, y: height - L.padding - L.headerHeight, width: 200, height: L.headerHeight)
        statusLabel.frame = NSRect(
            x: L.padding,
            y: height - L.padding - L.headerHeight - L.statusHeight,
            width: contentWidth - 50,
            height: L.statusHeight
        )
        closeButton.frame = NSRect(x: width - L.padding - 18, y: height - L.padding - L.headerHeight + 1, width: 18, height: 18)
        pinButton.frame = NSRect(x: width - L.padding - 18 - 22, y: height - L.padding - L.headerHeight + 1, width: 18, height: 18)

        let languageDropdownWidth = (contentWidth - 38 - 12) / 2
        sourceLanguagePopup.frame = NSRect(x: L.padding, y: languageY, width: languageDropdownWidth, height: L.languageHeight)
        swapLanguagesButton.frame = NSRect(x: sourceLanguagePopup.frame.maxX + 6, y: languageY, width: 38, height: L.languageHeight)
        targetLanguagePopup.frame = NSRect(x: swapLanguagesButton.frame.maxX + 6, y: languageY, width: languageDropdownWidth, height: L.languageHeight)

        sourceCard.frame = NSRect(x: L.padding, y: sourceCardY, width: contentWidth, height: sourceCardHeight)
        inputScrollView.frame = NSRect(x: 0, y: L.sourceFooterHeight, width: contentWidth, height: L.sourceBodyHeight)
        inputScrollView.hasVerticalScroller = true
        inputTextView.minSize = NSSize(width: 0, height: L.sourceBodyHeight)
        sourceFooter.frame = NSRect(x: 0, y: 0, width: contentWidth, height: L.sourceFooterHeight)

        translateButton.sizeToFit()
        learnButton.sizeToFit()
        let btnH = L.primaryButtonHeight
        let btnY = (L.sourceFooterHeight - btnH) / 2
        let translateW = max(78, translateButton.frame.width)
        let learnW = max(62, learnButton.frame.width)
        translateButton.frame = NSRect(x: 4, y: btnY, width: translateW, height: btnH)
        learnButton.frame = NSRect(x: translateButton.frame.maxX + 4, y: btnY, width: learnW, height: btnH)
        let icon = L.iconButtonSize
        let iconY = (L.sourceFooterHeight - icon) / 2
        speakSourceButton.frame = NSRect(x: contentWidth - 4 - icon, y: iconY, width: icon, height: icon)

        resultCard.frame = NSRect(x: L.padding, y: resultY, width: contentWidth, height: resultHeight)
        // Header sits at top of card (AppKit y=0 is bottom)
        resultHeaderBar.frame = NSRect(x: 0, y: resultBodyHeight, width: contentWidth, height: L.resultHeaderHeight)
        resultHeaderLabel.sizeToFit()
        let labelH = max(12, resultHeaderLabel.fittingSize.height)
        let labelY = ((L.resultHeaderHeight - labelH) / 2).rounded(.towardZero)
        resultHeaderLabel.frame = NSRect(x: 8, y: labelY, width: max(120, resultHeaderLabel.fittingSize.width), height: labelH)
        let headerIconY = (L.resultHeaderHeight - icon) / 2
        copyButton.frame = NSRect(x: contentWidth - 6 - icon, y: headerIconY, width: icon, height: icon)
        speakResultButton.frame = NSRect(x: copyButton.frame.minX - 4 - icon, y: headerIconY, width: icon, height: icon)
        textScrollView.frame = NSRect(x: 0, y: 0, width: contentWidth, height: resultBodyHeight)
        textView.minSize = NSSize(width: 0, height: resultBodyHeight)
    }

    /// Resizes/repositions the panel around `size`. While the panel hasn't been dragged by the
    /// user, it stays anchored to `showMousePoint` (recomputed each time, so growth/shrinkage never
    /// straddles the cursor). Once dragged, resizes keep the panel's top-left corner fixed instead.
    private func applyPanelFrame(size: NSSize) {
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

    private func currentScreenFrame() -> NSRect? {
        (NSScreen.screens.first { $0.frame.contains(showMousePoint) } ?? NSScreen.main)?.visibleFrame
    }

    /// Places the panel beside `mouse` (below, above, right, then left, in that preference order),
    /// falling back to a clamped on-screen position. The cursor point is never inside the resulting
    /// rect, so the panel never lands centered on top of it.
    private func computePopupOrigin(size: NSSize, mouse: NSPoint, screenFrame: NSRect) -> NSPoint {
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

    private func clamp(_ value: CGFloat, minV: CGFloat, maxV: CGFloat) -> CGFloat {
        guard maxV >= minV else { return minV }
        return min(max(value, minV), maxV)
    }

    private func setResultText(_ value: String, style: PopoverFeedback.ResultStyle? = nil) {
        let resolved = style ?? PopoverFeedback.resultStyle(for: value)
        let color: NSColor
        switch resolved {
        case .normal:
            color = .labelColor
        case .loading:
            color = .secondaryLabelColor
        case .error:
            color = .systemRed
        }
        textView.textStorage?.setAttributedString(.plainDisplay(value, font: .systemFont(ofSize: 13), color: color))
    }

    private func setStatus(_ message: String, autoClearAfter: TimeInterval = 4) {
        statusClearWorkItem?.cancel()
        statusLabel.stringValue = message
        statusLabel.isHidden = message.isEmpty
        if !message.isEmpty {
            let work = DispatchWorkItem { [weak self] in
                self?.statusLabel.stringValue = ""
                self?.statusLabel.isHidden = true
            }
            statusClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + autoClearAfter, execute: work)
        }
    }

    private func clearStatus() {
        statusClearWorkItem?.cancel()
        statusClearWorkItem = nil
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
    }

    private func beginRequest() -> Int {
        requestGeneration += 1
        isRequestInFlight = true
        updateBusyState()
        return requestGeneration
    }

    private func finishRequest(generation: Int) {
        guard generation == requestGeneration else { return }
        isRequestInFlight = false
        updateBusyState()
    }

    private func updateBusyState() {
        translateButton.isEnabled = !isRequestInFlight
        learnButton.isEnabled = !isRequestInFlight
        swapLanguagesButton.isEnabled = !isRequestInFlight
        updateSpeakButtons()
        updateCopyButtonEnabled()
    }

    private func updateCopyButtonEnabled() {
        copyButton.isEnabled = PopoverFeedback.isCopyableResult(textView.string)
    }

    private func preferredPopoverHeight() -> CGFloat {
        let width = CGFloat(config.ui.width)
        let L = ChromeLayout.self
        let contentWidth = width - L.padding * 2
        let sourceCardHeight = L.sourceBodyHeight + L.sourceFooterHeight
        let measuredBody = measuredTextHeight(textView.attributedString(), width: contentWidth - 14) + 16
        let resultBody = min(max(L.minResultBodyHeight, measuredBody), L.maxResultBodyHeight)
        let resultCardHeight = L.resultHeaderHeight + resultBody
        return L.padding
            + L.headerHeight
            + L.statusHeight
            + L.languageGap
            + L.languageHeight
            + L.sectionGap
            + sourceCardHeight
            + L.sectionGap
            + resultCardHeight
            + L.padding
    }

    private func maxPopoverHeight() -> CGFloat {
        CGFloat(config.ui.height) + 300
    }

    private func currentPopoverHeight() -> CGFloat {
        let baseHeight = CGFloat(config.ui.height)
        return min(max(baseHeight, preferredPopoverHeight()), maxPopoverHeight())
    }

    private func measuredTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        PopoverLayoutMath.measuredTextHeight(text, width: width)
    }

    private func selectedSourceLanguage() -> String {
        sourceLanguagePopup.selectedItem?.title ?? config.resolvedSourceLang
    }

    private func selectedTargetLanguage() -> String {
        targetLanguagePopup.selectedItem?.title ?? config.resolvedTargetLang
    }

    private func resolvedLanguagePair(for text: String) -> (source: String, target: String) {
        let pair = LanguageDetector.resolvedPair(
            selectedSource: selectedSourceLanguage(),
            selectedTarget: selectedTargetLanguage(),
            text: text,
            recentTargets: recentTargets,
            languages: config.languages,
            targetLanguages: config.targetLanguages,
            nativeLang: config.resolvedNativeLang
        )
        recentTargets.removeAll { $0 == pair.target }
        recentTargets.insert(pair.target, at: 0)
        return pair
    }

    private func configureLanguageControls() {
        sourceLanguagePopup.removeAllItems()
        sourceLanguagePopup.addItems(withTitles: config.languages)
        sourceLanguagePopup.selectItem(withTitle: LanguageDetector.normalizeSource(config.resolvedSourceLang, languages: config.languages))
        sourceLanguagePopup.target = self
        sourceLanguagePopup.action = #selector(languageSelectionChanged)

        let savedTarget = UserDefaults.standard.string(forKey: Self.lastTargetLangKey) ?? config.resolvedTargetLang
        let normalizedTarget = LanguageDetector.normalizeTarget(
            savedTarget,
            targetLanguages: config.targetLanguages,
            fallback: config.resolvedNativeLang
        )
        targetLanguagePopup.removeAllItems()
        targetLanguagePopup.addItems(withTitles: config.targetLanguages)
        targetLanguagePopup.selectItem(withTitle: normalizedTarget)
        recentTargets = [normalizedTarget]
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(languageSelectionChanged)

        swapLanguagesButton.title = "⇄"
        swapLanguagesButton.bezelStyle = .rounded
        swapLanguagesButton.target = self
        swapLanguagesButton.action = #selector(swapLanguages)
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === inputTextView else { return }
        updateSpeakButtons()
    }

    @objc private func languageSelectionChanged() {
        let text = inputTextView.string
        // User manually picked a target that matches the auto-detected source language —
        // that's a request for grammar-check mode, so pin the source dropdown to match
        // instead of letting auto-detect's target override snap it back.
        if selectedSourceLanguage() == "Auto detect" {
            let detected = LanguageDetector.detectedLanguage(text)
            if selectedTargetLanguage() == detected {
                sourceLanguagePopup.selectItem(withTitle: detected)
            }
        }
        let pair = resolvedLanguagePair(for: text)
        if selectedSourceLanguage() != pair.source {
            sourceLanguagePopup.selectItem(withTitle: pair.source)
        }
        if selectedTargetLanguage() != pair.target {
            targetLanguagePopup.selectItem(withTitle: pair.target)
        }
        UserDefaults.standard.set(pair.target, forKey: Self.lastTargetLangKey)
        if !inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runTranslate()
        }
    }

    @objc private func swapLanguages() {
        let source = LanguageDetector.normalizeSource(selectedSourceLanguage(), languages: config.languages)
        let target = LanguageDetector.normalizeTarget(
            selectedTargetLanguage(),
            targetLanguages: config.targetLanguages,
            fallback: config.resolvedNativeLang
        )
        sourceLanguagePopup.selectItem(withTitle: target)
        let swappedTarget = source == LanguageDetector.autoDetect ? config.resolvedNativeLang : source
        targetLanguagePopup.selectItem(withTitle: LanguageDetector.normalizeTarget(
            swappedTarget,
            targetLanguages: config.targetLanguages,
            fallback: config.resolvedNativeLang
        ))
        languageSelectionChanged()
    }

    private func updateSpeakButtons() {
        speakSourceButton.title = ""
        speakSourceButton.image = NSImage(
            systemSymbolName: isSpeakingSource ? "hourglass" : "speaker.wave.2",
            accessibilityDescription: "Speak source"
        )
        speakSourceButton.imagePosition = .imageOnly
        let hasSourceText = !inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        speakSourceButton.isEnabled = hasSourceText && !isSpeakingSource

        speakResultButton.title = ""
        speakResultButton.image = NSImage(
            systemSymbolName: isSpeakingResult ? "hourglass" : "speaker.wave.2",
            accessibilityDescription: "Speak translation"
        )
        speakResultButton.imagePosition = .imageOnly
        speakResultButton.isEnabled = PopoverFeedback.isCopyableResult(textView.string) && !isSpeakingResult
    }

    private func setSpeaking(_ value: Bool, for kind: SpeechKind) {
        switch kind {
        case .source:
            isSpeakingSource = value
        case .result:
            isSpeakingResult = value
        }
        updateSpeakButtons()
    }

    private func sourceSpeechModel(for text: String) -> String {
        if LanguageDetector.looksVietnamese(text) {
            return config.speechSourceModelVietnamese
        }
        return SpeechModelResolver.model(for: LanguageDetector.detectedLanguage(text), config: config)
    }

    private func buildMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit NTranslate", action: #selector(quitApp), keyEquivalent: "q")
        appMenu.items.forEach { $0.target = self }

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu

        let statusMenu = NSMenu()
        let versionItem = NSMenuItem(title: "NTranslate v\(Self.appVersionString())", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        statusMenu.addItem(versionItem)
        statusMenu.addItem(NSMenuItem.separator())
        let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access", action: #selector(requestAccessibilityPermissionMenu), keyEquivalent: "")
        accessibilityItem.tag = Self.accessibilityMenuItemTag
        statusMenu.addItem(accessibilityItem)
        statusMenu.addItem(withTitle: "Open Config File", action: #selector(openConfigFileMenu), keyEquivalent: "")
        statusMenu.addItem(withTitle: "Reload Config", action: #selector(reloadConfigMenu), keyEquivalent: "r")
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        statusMenu.items.forEach { $0.target = self }
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private static let accessibilityMenuItemTag = 9001

    func menuWillOpen(_ menu: NSMenu) {
        if let item = menu.item(withTag: Self.accessibilityMenuItemTag) {
            item.isHidden = AXIsProcessTrusted()
        }
    }

    @objc private func requestAccessibilityPermissionMenu() {
        requestAccessibilityPermissionIfNeeded(forcePrompt: true)
    }

    @objc private func reloadConfigMenu() {
        reloadConfig(showSuccess: true)
    }

    @objc private func openConfigFileMenu() {
        NSWorkspace.shared.open(URL(fileURLWithPath: AppConfig.configPath))
    }

    private static func appVersionString() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    private func hotKeyModifiers() -> UInt32 {
        var flags: UInt32 = 0
        if config.hotkey.option { flags |= UInt32(optionKey) }
        if config.hotkey.command { flags |= UInt32(cmdKey) }
        if config.hotkey.control { flags |= UInt32(controlKey) }
        if config.hotkey.shift { flags |= UInt32(shiftKey) }
        return flags
    }

    private func installHotKeyEventHandler() {
        guard hotKeyEventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
                let controller = Unmanaged<PopoverController>.fromOpaque(userData).takeUnretainedValue()
                controller.perform(#selector(PopoverController.hotKeyPressed), on: .main, with: nil, waitUntilDone: false)
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyEventHandlerRef)
    }

    private func registerHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let hotKeyID = EventHotKeyID(signature: OSType(0x54524E53), id: 1)
        let status = RegisterEventHotKey(HotkeyKeyCode.code(for: config.hotkey.key), hotKeyModifiers(), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            setResultText("Failed to register hotkey")
            return
        }
    }

    @objc private func hotKeyPressed() {
        translateAtCursor()
    }

    @objc private func manualToggle() {
        guard NSApp.currentEvent?.type == .leftMouseUp else { return }
        if panel.isVisible {
            restoresPreviousAppOnClose = true
            closePanel()
        } else if let button = statusItem.button, let buttonWindow = button.window {
            let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            showMousePoint = NSPoint(x: buttonFrameOnScreen.midX, y: buttonFrameOnScreen.minY)
            reflowLayout()
            presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyEventHandlerRef { RemoveEventHandler(hotKeyEventHandlerRef) }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        CrashRecovery.markCleanShutdown()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func reloadConfig() {
        reloadConfig(showSuccess: false)
    }

    private func reloadConfig(showSuccess: Bool) {
        let outcome = AppConfig.loadOutcome()
        config = outcome.config
        reflowLayout()
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            translator = nil
            if let message = outcome.message {
                setResultText("Config load error: \(message)")
            } else {
                setResultText("Config load error: apiKey is empty")
            }
            return
        }
        translator = Translator(config: config, apiKey: apiKey)
        configureLanguageControls()
        registerHotKey()
        assert(URL(string: config.apiBaseURL) != nil)
        assert(URL(string: config.speechURL) != nil)
        if let message = outcome.message {
            setResultText("Config load error: \(message)")
        } else if showSuccess {
            setResultText("Reloaded config from \(AppConfig.configPath)")
        }
    }

    private func requestAccessibilityPermissionIfNeeded(forcePrompt: Bool = false) {
        let alreadyTrusted = AXIsProcessTrusted()
        NSLog("[NTranslate] Accessibility trusted=\(alreadyTrusted) forcePrompt=\(forcePrompt) bundle=\(Bundle.main.bundleIdentifier ?? "nil") path=\(Bundle.main.bundleURL.path)")
        guard !alreadyTrusted || forcePrompt else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            setResultText("Grant Accessibility access in System Settings > Privacy & Security > Accessibility, then reopen or retry.")
        }
    }

    private func restorePreviousAppFocus() {
        guard restoresPreviousAppOnClose else { return }
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }

    private func installOutsideClickMonitor() {
        removeOutsideClickMonitor()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let click = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                guard let self, self.panel.isVisible, !self.isPinned else { return }
                guard !PopoverLayoutMath.clickIsInsidePanel(click: click, panelFrame: self.panel.frame) else { return }
                self.restoresPreviousAppOnClose = false
                self.closePanel()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.panel.isVisible, !self.isPinned else { return event }
            guard !PopoverLayoutMath.clickIsInsidePanel(click: NSEvent.mouseLocation, panelFrame: self.panel.frame) else { return event }
            self.restoresPreviousAppOnClose = false
            self.closePanel()
            return event
        }
    }

    private func removeOutsideClickMonitor() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    /// Shows the panel (or re-focuses it if already open) using the frame `reflowLayout` already
    /// computed against `showMousePoint`.
    private func presentPanel(activatesApp: Bool, restoresPreviousAppOnCloseValue: Bool) {
        let wasVisible = panel.isVisible
        if !wasVisible {
            userMovedWindow = false
            isPinned = false
            updatePinButton()
        }
        restoresPreviousAppOnClose = restoresPreviousAppOnCloseValue
        activatesAppOnShow = activatesApp
        panel.makeKeyAndOrderFront(nil)
        if activatesApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !wasVisible {
            installOutsideClickMonitor()
        }
        focusInputTextView()
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        requestGeneration += 1
        isRequestInFlight = false
        isSpeakingSource = false
        isSpeakingResult = false
        clearStatus()
        copyFlashWorkItem?.cancel()
        copyFlashWorkItem = nil
        resetCopyButtonAppearance()
        updateBusyState()
        panel.orderOut(nil)
        audioPlayer?.stop()
        audioPlayer = nil
        removeOutsideClickMonitor()
        restorePreviousAppFocus()
        previousApp = nil
        restoresPreviousAppOnClose = false
        activatesAppOnShow = false
    }

    func windowDidMove(_ notification: Notification) {
        guard (notification.object as? NSWindow) === panel, !isProgrammaticFrameChange else { return }
        userMovedWindow = true
        if !isPinned {
            isPinned = true
            updatePinButton()
        }
    }

    @objc private func togglePin() {
        isPinned.toggle()
        updatePinButton()
    }

    private func updatePinButton() {
        pinButton.image = NSImage(systemSymbolName: isPinned ? "pin.fill" : "pin", accessibilityDescription: "Pin")
        pinButton.contentTintColor = isPinned ? .controlAccentColor : nil
    }

    private func focusInputTextView() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeKey()
            self.panel.makeFirstResponder(self.inputTextView)
        }
    }

    private func updateLanguageSelection(for text: String) {
        let pair = resolvedLanguagePair(for: text)
        sourceLanguagePopup.selectItem(withTitle: pair.source)
        targetLanguagePopup.selectItem(withTitle: pair.target)
    }

    private func showEmptySelectionPanel() {
        if !panel.isVisible {
            showMousePoint = NSEvent.mouseLocation
        }
        inputTextView.string = ""
        setResultText(PopoverFeedback.emptySelectionGuidance)
        clearStatus()
        prefetchedSpeech.removeAll()
        reflowLayout()
        updateBusyState()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
    }

    func translateAtCursor() {
        if !AXIsProcessTrusted() {
            requestAccessibilityPermissionIfNeeded(forcePrompt: true)
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        guard let resolved = SelectionReader.resolveTranslatableTextWithDiagnostics(simulateCopy: config.ui.simulateCopy) else {
            showEmptySelectionPanel()
            return
        }
        let trimmed = resolved.text
        if trimmed.count > config.maxTranslateLength {
            if !panel.isVisible {
                showMousePoint = NSEvent.mouseLocation
            }
            inputTextView.string = trimmed
            setResultText(PopoverFeedback.textTooLong)
            if resolved.accessibilityError != nil {
                setStatus(PopoverFeedback.accessibilityFallbackNote(source: resolved.source))
            } else {
                clearStatus()
            }
            reflowLayout()
            updateBusyState()
            presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
            return
        }
        inputTextView.string = trimmed
        if !panel.isVisible {
            showMousePoint = NSEvent.mouseLocation
        }
        if resolved.accessibilityError != nil {
            setStatus(PopoverFeedback.accessibilityFallbackNote(source: resolved.source))
        } else {
            clearStatus()
        }
        let generation = beginRequest()
        setResultText(PopoverFeedback.translating)
        reflowLayout()
        updateLanguageSelection(for: trimmed)
        prefetchedSpeech.removeAll()
        prefetchSpeech(trimmed, model: sourceSpeechModel(for: trimmed), kind: .source)
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        performTranslate(generation: generation)
    }

    @objc func runTranslate() {
        performTranslate(generation: nil)
    }

    private func performTranslate(generation existingGeneration: Int?) {
        guard let translator else {
            if let existingGeneration {
                finishRequest(generation: existingGeneration)
            }
            return
        }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            setResultText(PopoverFeedback.emptyInputHint)
            reflowLayout()
            updateBusyState()
            return
        }
        guard text.count <= config.maxTranslateLength else {
            setResultText(PopoverFeedback.textTooLong)
            reflowLayout()
            updateBusyState()
            return
        }
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        let generation = existingGeneration ?? beginRequest()
        if existingGeneration == nil {
            setResultText(PopoverFeedback.translating)
            reflowLayout()
        }
        translator.translate(text, sourceLang: pair.source, targetLang: pair.target) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.finishRequest(generation: generation) }
                guard !PopoverFeedback.isStale(resultGeneration: generation, currentGeneration: self.requestGeneration) else { return }
                switch result {
                case let .success(value):
                    self.setResultText(value)
                    self.reflowLayout()
                    self.textView.scrollToBeginningOfDocument(nil)
                    self.updateBusyState()
                    self.prefetchSpeech(value, model: SpeechModelResolver.model(for: pair.target, config: self.config), kind: .result)
                    if self.config.ui.autoCopy {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                        self.flashCopied()
                    }
                case let .failure(error):
                    self.setResultText("Error: \(error.localizedDescription)")
                    self.reflowLayout()
                    self.textView.scrollToBeginningOfDocument(nil)
                    self.updateBusyState()
                }
            }
        }
    }

    @objc func runLearn() {
        guard let translator else { return }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            setResultText(PopoverFeedback.emptyInputHint)
            reflowLayout()
            updateBusyState()
            return
        }
        guard text.count <= config.maxTranslateLength else {
            setResultText(PopoverFeedback.textTooLong)
            reflowLayout()
            updateBusyState()
            return
        }
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        let generation = beginRequest()
        setResultText(PopoverFeedback.learning)
        reflowLayout()
        translator.learn(text, sourceLang: pair.source, targetLang: pair.target) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.finishRequest(generation: generation) }
                guard !PopoverFeedback.isStale(resultGeneration: generation, currentGeneration: self.requestGeneration) else { return }
                switch result {
                case let .success(value):
                    self.setResultText(value)
                    self.reflowLayout()
                    self.textView.scrollToBeginningOfDocument(nil)
                    self.updateBusyState()
                case let .failure(error):
                    self.setResultText("Error: \(error.localizedDescription)")
                    self.reflowLayout()
                    self.textView.scrollToBeginningOfDocument(nil)
                    self.updateBusyState()
                }
            }
        }
    }

    private func playAudio(data: Data) {
        do {
            audioPlayer = try AVAudioPlayer(data: data)
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
        } catch {
            setStatus("Speak failed: \(error.localizedDescription)")
        }
    }

    private func prefetchSpeech(_ text: String, model: String, kind: SpeechKind) {
        guard let translator else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !speechModel.isEmpty else { return }
        if let cached = prefetchedSpeech[kind], cached.text == trimmed, cached.model == speechModel { return }
        let generation = requestGeneration
        setSpeaking(true, for: kind)
        translator.speak(trimmed, model: speechModel) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.setSpeaking(false, for: kind) }
                guard !PopoverFeedback.isStale(resultGeneration: generation, currentGeneration: self.requestGeneration) else { return }
                guard case let .success(audioData) = result else { return }
                self.prefetchedSpeech[kind] = PrefetchedSpeech(text: trimmed, model: speechModel, data: audioData)
            }
        }
    }

    private func playSpeech(_ text: String, model: String, kind: SpeechKind) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !speechModel.isEmpty else {
            setStatus("Speak failed: Empty speech model")
            return
        }
        if let cached = prefetchedSpeech[kind], cached.text == trimmed, cached.model == speechModel {
            playAudio(data: cached.data)
            return
        }
        guard let translator else { return }
        let generation = requestGeneration
        setSpeaking(true, for: kind)
        translator.speak(trimmed, model: speechModel) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.setSpeaking(false, for: kind) }
                guard !PopoverFeedback.isStale(resultGeneration: generation, currentGeneration: self.requestGeneration) else { return }
                switch result {
                case let .success(audioData):
                    self.prefetchedSpeech[kind] = PrefetchedSpeech(text: trimmed, model: speechModel, data: audioData)
                    self.playAudio(data: audioData)
                case let .failure(error):
                    self.setStatus("Speak failed: \(error.localizedDescription)")
                }
            }
        }
    }

    @objc func speakInput() {
        playSpeech(inputTextView.string, model: sourceSpeechModel(for: inputTextView.string), kind: .source)
    }

    @objc func speakResult() {
        let target = resolvedLanguagePair(for: inputTextView.string).target
        playSpeech(textView.string, model: SpeechModelResolver.model(for: target, config: config), kind: .result)
    }

    @objc func copyResult() {
        guard let value = copyValue() else { return }
        guard writePasteboard(value) else {
            setStatus("Copy failed")
            return
        }
        flashCopied()
    }

    private func flashCopied() {
        copyFlashWorkItem?.cancel()
        copyButton.title = ""
        copyButton.attributedTitle = NSAttributedString(string: "")
        copyButton.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Copied")
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = .systemGreen
        let work = DispatchWorkItem { [weak self] in
            self?.resetCopyButtonAppearance()
        }
        copyFlashWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func copyValue() -> String? {
        let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PopoverFeedback.isCopyableResult(value) else { return nil }
        return value
    }

    private func postCommandV() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func writePasteboard(_ value: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(value, forType: .string)
    }

    private func pasteResultToPreviousApp() {
        guard !isPastingResult else { return }
        guard let value = copyValue(), writePasteboard(value) else {
            closePanel()
            return
        }
        isPastingResult = true
        let app = previousApp
        restoresPreviousAppOnClose = false
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            app?.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.postCommandV()
                self.isPastingResult = false
            }
        }
    }

    @objc private func closePopover() {
        restoresPreviousAppOnClose = true
        closePanel()
    }
}
