import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation

extension NSAttributedString {
    static func plainDisplay(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
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
    private let sourceLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let swapLanguagesButton = NSButton(frame: .zero)
    private let pinButton = NSButton(frame: .zero)
    private let closeButton = NSButton(frame: .zero)
    private let translateButton = NSButton(frame: .zero)
    private let learnButton = NSButton(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "Translate")
    private let speakSourceButton = NSButton(frame: .zero)
    private let speakResultButton = NSButton(frame: .zero)
    private var translator: Translator?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandlerRef: EventHandlerRef?
    private var config = AppConfig.load()
    private var audioPlayer: AVAudioPlayer?
    private var isSpeakingSource = false
    private var isSpeakingResult = false
    private var keyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var restoresPreviousAppOnClose = false
    private var activatesAppOnShow = false
    private var isPastingResult = false
    private var prefetchedSpeech: [SpeechKind: PrefetchedSpeech] = [:]
    private var recentTargets: [String] = []
    private var showMousePoint: NSPoint = .zero
    private var userMovedWindow = false
    private var isProgrammaticFrameChange = false
    private var isPinned = false

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
            return event
        }
    }


    private func buildPopover() {
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        let padding: CGFloat = 14
        let headerHeight: CGFloat = 18
        let languageHeight: CGFloat = 28
        let minInputHeight: CGFloat = 30
        let maxInputHeight: CGFloat = 74
        let buttonHeight: CGFloat = 30
        let buttonGap: CGFloat = 8
        let buttonTitles = ["Translate", "Learn", speakSourceButtonTitle(), speakResultButtonTitle()]
        let buttonFonts = [translateButton, learnButton, speakSourceButton, speakResultButton].map {
            ($0.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).withSize(NSFont.systemFontSize)
        }
        let buttonAreaHeight = actionButtonsHeight(height: buttonHeight, gap: buttonGap, width: width - padding * 2, titles: buttonTitles, fonts: buttonFonts)
        let languageY = height - padding - headerHeight - 10 - languageHeight
        let inputHeight = inputHeight(for: inputTextView.string, minHeight: minInputHeight, maxHeight: maxInputHeight, width: width - padding * 2)
        let inputY = languageY - 10 - inputHeight
        let buttonY = inputY - 12 - buttonHeight
        let resultY = padding
        let resultHeight = max(120, buttonY - 12 - resultY - (buttonAreaHeight - buttonHeight))

        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let titleText = NSMutableAttributedString(
            string: "NTranslate",
            attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.labelColor]
        )
        titleText.append(NSAttributedString(
            string: "  v\(Self.buildVersion)",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        ))
        titleLabel.attributedStringValue = titleText
        titleLabel.frame = NSRect(x: padding, y: height - padding - headerHeight, width: 200, height: headerHeight)

        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePopover)
        closeButton.frame = NSRect(x: width - padding - 18, y: height - padding - headerHeight + 1, width: 18, height: 18)

        pinButton.title = ""
        pinButton.imagePosition = .imageOnly
        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        pinButton.frame = NSRect(x: width - padding - 18 - 22, y: height - padding - headerHeight + 1, width: 18, height: 18)
        updatePinButton()

        configureLanguageControls()
        let languageDropdownWidth = (width - padding * 2 - 38 - 16) / 2
        sourceLanguagePopup.frame = NSRect(x: padding, y: languageY, width: languageDropdownWidth, height: languageHeight)
        swapLanguagesButton.frame = NSRect(x: sourceLanguagePopup.frame.maxX + 8, y: languageY, width: 38, height: languageHeight)
        targetLanguagePopup.frame = NSRect(x: swapLanguagesButton.frame.maxX + 8, y: languageY, width: languageDropdownWidth, height: languageHeight)

        let inputFrame = NSRect(x: padding, y: inputY, width: width - padding * 2, height: inputHeight)

        inputTextView.isEditable = true
        inputTextView.isSelectable = true
        inputTextView.delegate = self
        inputTextView.font = .systemFont(ofSize: 13)
        inputTextView.drawsBackground = true
        inputTextView.backgroundColor = .textBackgroundColor
        inputTextView.textColor = .labelColor
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.textContainerInset = NSSize(width: 4, height: 4)
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.textContainer?.containerSize = NSSize(width: inputFrame.width - 20, height: .greatestFiniteMagnitude)
        inputTextView.frame = NSRect(x: 0, y: 0, width: inputFrame.width, height: inputHeight)

        inputScrollView.frame = inputFrame
        inputScrollView.borderType = .bezelBorder
        inputScrollView.drawsBackground = true
        inputScrollView.backgroundColor = .textBackgroundColor
        inputScrollView.hasVerticalScroller = inputHeight >= maxInputHeight
        inputScrollView.hasHorizontalScroller = false
        inputScrollView.autohidesScrollers = true
        inputScrollView.documentView = inputTextView

        translateButton.title = "Translate"
        translateButton.image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: "Translate")
        translateButton.imagePosition = .imageLeading
        translateButton.target = self
        translateButton.action = #selector(runTranslate)
        translateButton.bezelStyle = .rounded
        translateButton.controlSize = .large

        learnButton.title = "Learn"
        learnButton.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Learn")
        learnButton.imagePosition = .imageLeading
        learnButton.target = self
        learnButton.action = #selector(runLearn)
        learnButton.bezelStyle = .rounded
        learnButton.controlSize = .large

        speakSourceButton.target = self
        speakSourceButton.action = #selector(speakInput)
        speakSourceButton.bezelStyle = .rounded
        speakSourceButton.controlSize = .large

        speakResultButton.target = self
        speakResultButton.action = #selector(speakResult)
        speakResultButton.bezelStyle = .rounded
        speakResultButton.controlSize = .large

        updateSpeakButtons()
        layoutActionButtons(y: buttonY, height: buttonHeight, gap: buttonGap, width: width - padding * 2, titles: buttonTitles, fonts: buttonFonts)
        languageSelectionChanged()

        let resultCard = NSView(frame: NSRect(x: padding, y: resultY, width: width - padding * 2, height: resultHeight))
        resultCard.wantsLayer = true
        resultCard.layer?.cornerRadius = 12
        resultCard.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.minSize = NSSize(width: 0, height: resultHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        textScrollView.frame = NSRect(x: 1, y: 1, width: resultCard.frame.width - 2, height: resultCard.frame.height - 2)
        textScrollView.borderType = .noBorder
        textScrollView.drawsBackground = false
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.documentView = textView
        resultCard.addSubview(textScrollView)

        root.addSubview(titleLabel)
        root.addSubview(pinButton)
        root.addSubview(closeButton)
        root.addSubview(sourceLanguagePopup)
        root.addSubview(swapLanguagesButton)
        root.addSubview(targetLanguagePopup)
        root.addSubview(inputScrollView)
        root.addSubview(translateButton)
        root.addSubview(learnButton)
        root.addSubview(speakSourceButton)
        root.addSubview(speakResultButton)
        root.addSubview(resultCard)
        panel.contentView = root
        panel.setFrame(NSRect(origin: panel.frame.origin, size: root.frame.size), display: false)
    }

    private func reflowLayout() {
        guard let root = panel.contentView else { return }
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        let padding: CGFloat = 14
        let headerHeight: CGFloat = 18
        let languageHeight: CGFloat = 28
        let minInputHeight: CGFloat = 30
        let maxInputHeight: CGFloat = 74
        let buttonHeight: CGFloat = 30
        let buttonGap: CGFloat = 8
        let buttonTitles = ["Translate", "Learn", speakSourceButtonTitle(), speakResultButtonTitle()]
        let buttonFonts = [translateButton, learnButton, speakSourceButton, speakResultButton].map {
            ($0.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).withSize(NSFont.systemFontSize)
        }
        let buttonAreaHeight = actionButtonsHeight(height: buttonHeight, gap: buttonGap, width: width - padding * 2, titles: buttonTitles, fonts: buttonFonts)
        let languageY = height - padding - headerHeight - 10 - languageHeight
        let inputHeight = inputHeight(for: inputTextView.string, minHeight: minInputHeight, maxHeight: maxInputHeight, width: width - padding * 2)
        let inputY = languageY - 10 - inputHeight
        let buttonY = inputY - 12 - buttonHeight
        let resultY = padding
        let resultHeight = max(120, buttonY - 12 - resultY - (buttonAreaHeight - buttonHeight))
        let inputFrame = NSRect(x: padding, y: inputY, width: width - padding * 2, height: inputHeight)

        root.frame = NSRect(x: 0, y: 0, width: width, height: height)
        titleLabel.frame = NSRect(x: padding, y: height - padding - headerHeight, width: 200, height: headerHeight)
        closeButton.frame = NSRect(x: width - padding - 18, y: height - padding - headerHeight + 1, width: 18, height: 18)
        pinButton.frame = NSRect(x: width - padding - 18 - 22, y: height - padding - headerHeight + 1, width: 18, height: 18)
        let languageDropdownWidth = (width - padding * 2 - 38 - 16) / 2
        sourceLanguagePopup.frame = NSRect(x: padding, y: languageY, width: languageDropdownWidth, height: languageHeight)
        swapLanguagesButton.frame = NSRect(x: sourceLanguagePopup.frame.maxX + 8, y: languageY, width: 38, height: languageHeight)
        targetLanguagePopup.frame = NSRect(x: swapLanguagesButton.frame.maxX + 8, y: languageY, width: languageDropdownWidth, height: languageHeight)
        inputScrollView.frame = inputFrame
        inputScrollView.hasVerticalScroller = inputHeight >= maxInputHeight
        inputTextView.textContainer?.containerSize = NSSize(width: inputFrame.width - 20, height: .greatestFiniteMagnitude)
        inputTextView.frame = NSRect(x: 0, y: 0, width: inputFrame.width, height: inputHeight)
        layoutActionButtons(y: buttonY, height: buttonHeight, gap: buttonGap, width: width - padding * 2, titles: buttonTitles, fonts: buttonFonts)
        if let resultCard = textScrollView.superview {
            resultCard.frame = NSRect(x: padding, y: resultY, width: width - padding * 2, height: resultHeight)
            textScrollView.frame = NSRect(x: 1, y: 1, width: resultCard.frame.width - 2, height: resultCard.frame.height - 2)
        }
        applyPanelFrame(size: root.frame.size)
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

    private func setResultText(_ value: String) {
        textView.textStorage?.setAttributedString(.plainDisplay(value, font: .systemFont(ofSize: 13)))
    }

    private func inputHeight(for text: String, minHeight: CGFloat, maxHeight: CGFloat, width: CGFloat) -> CGFloat {
        PopoverLayoutMath.inputHeight(
            text: text,
            font: inputTextView.font ?? .systemFont(ofSize: 13),
            inset: inputTextView.textContainerInset,
            lineFragmentPadding: inputTextView.textContainer?.lineFragmentPadding ?? 5,
            minHeight: minHeight,
            maxHeight: maxHeight,
            width: width
        )
    }

    private func preferredPopoverHeight() -> CGFloat {
        let width = CGFloat(config.ui.width)
        let padding: CGFloat = 14
        let headerHeight: CGFloat = 18
        let languageHeight: CGFloat = 28
        let minInputHeight: CGFloat = 30
        let maxInputHeight: CGFloat = 74
        let buttonHeight: CGFloat = 30
        let minResultHeight: CGFloat = 160
        let maxResultHeight: CGFloat = 520
        let inputHeight = inputHeight(for: inputTextView.string, minHeight: minInputHeight, maxHeight: maxInputHeight, width: width - padding * 2)
        let resultHeight = min(max(minResultHeight, measuredTextHeight(textView.attributedString(), width: width - padding * 2 - 18) + 24), maxResultHeight)
        return padding + headerHeight + 10 + languageHeight + 10 + inputHeight + 12 + buttonHeight + 12 + resultHeight + padding
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
        let pair = LanguageDetector.resolvedPair(selectedSource: selectedSourceLanguage(), selectedTarget: selectedTargetLanguage(), text: text, recentTargets: recentTargets)
        recentTargets.removeAll { $0 == pair.target }
        recentTargets.insert(pair.target, at: 0)
        return pair
    }

    private func configureLanguageControls() {
        sourceLanguagePopup.removeAllItems()
        sourceLanguagePopup.addItems(withTitles: LanguageDetector.supportedLanguages)
        sourceLanguagePopup.selectItem(withTitle: LanguageDetector.normalizeSource(config.resolvedSourceLang))
        sourceLanguagePopup.target = self
        sourceLanguagePopup.action = #selector(languageSelectionChanged)

        targetLanguagePopup.removeAllItems()
        targetLanguagePopup.addItems(withTitles: LanguageDetector.targetLanguages)
        targetLanguagePopup.selectItem(withTitle: LanguageDetector.normalizeTarget(config.resolvedTargetLang))
        recentTargets = [LanguageDetector.normalizeTarget(config.resolvedTargetLang)]
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(languageSelectionChanged)

        swapLanguagesButton.title = "⇄"
        swapLanguagesButton.bezelStyle = .rounded
        swapLanguagesButton.target = self
        swapLanguagesButton.action = #selector(swapLanguages)
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === inputTextView else { return }
        reflowLayout()
    }

    @objc private func languageSelectionChanged() {
        let pair = resolvedLanguagePair(for: inputTextView.string)
        if selectedSourceLanguage() != pair.source {
            sourceLanguagePopup.selectItem(withTitle: pair.source)
        }
        if selectedTargetLanguage() != pair.target {
            targetLanguagePopup.selectItem(withTitle: pair.target)
        }
        if !inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runTranslate()
        }
    }

    @objc private func swapLanguages() {
        let source = LanguageDetector.normalizeSource(selectedSourceLanguage())
        let target = LanguageDetector.normalizeTarget(selectedTargetLanguage())
        sourceLanguagePopup.selectItem(withTitle: target)
        targetLanguagePopup.selectItem(withTitle: source == "Auto detect" ? "Vietnamese" : source)
        languageSelectionChanged()
    }

    private func updateSpeakButtons() {
        speakSourceButton.title = speakSourceButtonTitle()
        speakSourceButton.image = NSImage(systemSymbolName: isSpeakingSource ? "hourglass" : "speaker.wave.2", accessibilityDescription: "Speak source")
        speakSourceButton.imagePosition = .imageLeading
        speakSourceButton.isEnabled = !isSpeakingSource

        speakResultButton.title = speakResultButtonTitle()
        speakResultButton.image = NSImage(systemSymbolName: isSpeakingResult ? "hourglass" : "speaker.wave.2", accessibilityDescription: "Speak translation")
        speakResultButton.imagePosition = .imageLeading
        speakResultButton.isEnabled = !isSpeakingResult
    }

    private func speakSourceButtonTitle() -> String {
        isSpeakingSource ? "Loading" : "Src"
    }

    private func speakResultButtonTitle() -> String {
        isSpeakingResult ? "Loading" : "Trans"
    }

    private func actionButtonRows(width: CGFloat, titles: [String], fonts: [NSFont]) -> [[Int]] {
        let symbolPadding: CGFloat = 30
        let horizontalPadding: CGFloat = 18
        let minWidth: CGFloat = 62
        let naturalWidths = zip(titles, fonts).map { title, font in
            max(minWidth, ceil((title as NSString).size(withAttributes: [.font: font]).width) + symbolPadding + horizontalPadding)
        }

        var rows: [[Int]] = [[]]
        var currentRowWidth: CGFloat = 0
        for (index, naturalWidth) in naturalWidths.enumerated() {
            let neededWidth = rows[rows.count - 1].isEmpty ? naturalWidth : currentRowWidth + 8 + naturalWidth
            if neededWidth > width, !rows[rows.count - 1].isEmpty {
                rows.append([index])
                currentRowWidth = naturalWidth
            } else {
                rows[rows.count - 1].append(index)
                currentRowWidth = rows[rows.count - 1].count == 1 ? naturalWidth : currentRowWidth + 8 + naturalWidth
            }
        }
        return rows
    }

    private func actionButtonsHeight(height: CGFloat, gap: CGFloat, width: CGFloat, titles: [String], fonts: [NSFont]) -> CGFloat {
        let rowGap: CGFloat = 8
        let rows = actionButtonRows(width: width, titles: titles, fonts: fonts)
        return CGFloat(rows.count) * height + CGFloat(max(0, rows.count - 1)) * rowGap
    }

    private func layoutActionButtons(y: CGFloat, height: CGFloat, gap: CGFloat, width: CGFloat, titles: [String], fonts: [NSFont]) {
        let buttons = [translateButton, learnButton, speakSourceButton, speakResultButton]
        let symbolPadding: CGFloat = 30
        let horizontalPadding: CGFloat = 18
        let minWidth: CGFloat = 62
        let rowGap: CGFloat = 8
        let rowWidth = width
        let naturalWidths = zip(titles, fonts).map { title, font in
            max(minWidth, ceil((title as NSString).size(withAttributes: [.font: font]).width) + symbolPadding + horizontalPadding)
        }

        let rows = actionButtonRows(width: rowWidth, titles: titles, fonts: fonts)

        for (rowIndex, row) in rows.enumerated() {
            let rowNaturalWidths = row.map { naturalWidths[$0] }
            let availableWidth = max(0, rowWidth - gap * CGFloat(max(0, row.count - 1)))
            let totalNaturalWidth = rowNaturalWidths.reduce(0, +)
            let scale = totalNaturalWidth > 0 ? min(1, availableWidth / totalNaturalWidth) : 1
            let rowY = y - CGFloat(rowIndex) * (height + rowGap)
            var x: CGFloat = 14
            for index in row {
                let buttonWidth = max(minWidth, floor(naturalWidths[index] * scale))
                buttons[index].frame = NSRect(x: x, y: rowY, width: buttonWidth, height: height)
                x += buttonWidth + gap
            }
        }
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

    private func showSelectionFallbackAlert(accessibilityError: String, source: TranslatableTextSource) {
        let alert = NSAlert()
        alert.messageText = "Selection read failed"
        alert.informativeText = "\(accessibilityError)\n\nFallback source: \(source == .simulatedCopy ? "simulated copy" : "clipboard")"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static let maxTranslateLength = 5000

    func translateAtCursor() {
        if !AXIsProcessTrusted() {
            requestAccessibilityPermissionIfNeeded(forcePrompt: true)
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        guard let resolved = SelectionReader.resolveTranslatableTextWithDiagnostics(simulateCopy: config.ui.simulateCopy) else { return }
        if let accessibilityError = resolved.accessibilityError {
            showSelectionFallbackAlert(accessibilityError: accessibilityError, source: resolved.source)
        }
        let trimmed = resolved.text
        if trimmed.count > Self.maxTranslateLength {
            inputTextView.string = "Text is too long to translate."
            setResultText("")
            if !panel.isVisible {
                showMousePoint = NSEvent.mouseLocation
            }
            reflowLayout()
            presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
            return
        }
        inputTextView.string = trimmed
        if !panel.isVisible {
            showMousePoint = NSEvent.mouseLocation
        }
        setResultText("Translating...")
        reflowLayout()
        updateLanguageSelection(for: trimmed)
        prefetchedSpeech.removeAll()
        prefetchSpeech(trimmed, model: sourceSpeechModel(for: trimmed), kind: .source)
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        runTranslate()
    }

    @objc func runTranslate() {
        guard let translator else { return }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= Self.maxTranslateLength else {
            setResultText("")
            inputTextView.string = "Text is too long to translate."
            reflowLayout()
            return
        }
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        setResultText("Translating...")
        translator.translate(text, sourceLang: pair.source, targetLang: pair.target) { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(value):
                    self?.setResultText(value)
                    self?.reflowLayout()
                    self?.textView.scrollToBeginningOfDocument(nil)
                    if let self {
                        self.prefetchSpeech(value, model: SpeechModelResolver.model(for: pair.target, config: self.config), kind: .result)
                    }
                    if self?.config.ui.autoCopy == true {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }
                case let .failure(error):
                    self?.setResultText("Error: \(error.localizedDescription)")
                    self?.reflowLayout()
                    self?.textView.scrollToBeginningOfDocument(nil)
                }
            }
        }
    }

    @objc func runLearn() {
        guard let translator else { return }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        setResultText("Learning...")
        translator.learn(text, sourceLang: pair.source, targetLang: pair.target) { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(value):
                    self?.setResultText(value)
                    self?.reflowLayout()
                    self?.textView.scrollToBeginningOfDocument(nil)
                case let .failure(error):
                    self?.setResultText("Error: \(error.localizedDescription)")
                    self?.reflowLayout()
                    self?.textView.scrollToBeginningOfDocument(nil)
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
            setResultText("Error: \(error.localizedDescription)")
        }
    }

    private func prefetchSpeech(_ text: String, model: String, kind: SpeechKind) {
        guard let translator else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !speechModel.isEmpty else { return }
        if let cached = prefetchedSpeech[kind], cached.text == trimmed, cached.model == speechModel { return }
        setSpeaking(true, for: kind)
        translator.speak(trimmed, model: speechModel) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.setSpeaking(false, for: kind) }
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
            setResultText("Error: Empty speech model")
            return
        }
        if let cached = prefetchedSpeech[kind], cached.text == trimmed, cached.model == speechModel {
            playAudio(data: cached.data)
            return
        }
        guard let translator else { return }
        setSpeaking(true, for: kind)
        translator.speak(trimmed, model: speechModel) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.setSpeaking(false, for: kind) }
                switch result {
                case let .success(audioData):
                    self.prefetchedSpeech[kind] = PrefetchedSpeech(text: trimmed, model: speechModel, data: audioData)
                    self.playAudio(data: audioData)
                case let .failure(error):
                    self.setResultText("Error: \(error.localizedDescription)")
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

    private func copyValue() -> String? {
        let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "Translating..." else { return nil }
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
