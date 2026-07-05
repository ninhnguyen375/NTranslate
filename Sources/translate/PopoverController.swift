import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation

extension NSAttributedString {
    static func plainDisplay(_ text: String, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }
}

@MainActor
final class PopoverController: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSPopoverDelegate {
    private enum SpeechKind {
        case source
        case result
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private let textView = NSTextView(frame: .zero)
    private let textScrollView = NSScrollView(frame: .zero)
    private let inputTextView = NSTextView(frame: .zero)
    private let inputScrollView = NSScrollView(frame: .zero)
    private let sourceLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let targetLanguagePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let swapLanguagesButton = NSButton(frame: .zero)
    private let closeButton = NSButton(frame: .zero)
    private let translateButton = NSButton(frame: .zero)
    private let learnButton = NSButton(frame: .zero)
    private let speakSourceButton = NSButton(frame: .zero)
    private let speakResultButton = NSButton(frame: .zero)
    private let anchorWindow = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
        styleMask: .borderless,
        backing: .buffered,
        defer: false
    )
    private var translator: Translator?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandlerRef: EventHandlerRef?
    private var config = AppConfig.load()
    private var audioPlayer: AVAudioPlayer?
    private var isSpeakingSource = false
    private var isSpeakingResult = false
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var restoresPreviousAppOnClose = false
    private var activatesAppOnShow = false
    private var isPastingResult = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.title = "T"
        statusItem.button?.action = #selector(manualToggle)
        statusItem.button?.target = self
        requestAccessibilityPermissionIfNeeded()
        anchorWindow.isOpaque = false
        anchorWindow.backgroundColor = .clear
        anchorWindow.hasShadow = false
        anchorWindow.ignoresMouseEvents = true
        anchorWindow.level = .statusBar
        anchorWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        anchorWindow.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        buildPopover()
        buildMenu()
        installHotKeyEventHandler()
        reloadConfig()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            if event.keyCode == UInt16(kVK_Escape) {
                self.restoresPreviousAppOnClose = true
                self.popover.performClose(nil)
                return nil
            }
            return event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return }
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in
                    self.restoresPreviousAppOnClose = true
                    self.popover.performClose(nil)
                }
            }
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

        let vc = NSViewController()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Translate")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: padding, y: height - padding - headerHeight, width: 200, height: headerHeight)

        closeButton.title = ""
        closeButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closePopover)
        closeButton.frame = NSRect(x: width - padding - 18, y: height - padding - headerHeight + 1, width: 18, height: 18)

        configureLanguageControls()
        sourceLanguagePopup.frame = NSRect(x: padding, y: languageY, width: 150, height: languageHeight)
        swapLanguagesButton.frame = NSRect(x: sourceLanguagePopup.frame.maxX + 8, y: languageY, width: 38, height: languageHeight)
        targetLanguagePopup.frame = NSRect(x: swapLanguagesButton.frame.maxX + 8, y: languageY, width: 150, height: languageHeight)

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

        root.addSubview(title)
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
        vc.view = root
        popover.contentViewController = vc
        popover.delegate = self
        popover.behavior = .applicationDefined
    }

    private func reflowLayout() {
        guard let root = popover.contentViewController?.view else { return }
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
        closeButton.frame = NSRect(x: width - padding - 18, y: height - padding - headerHeight + 1, width: 18, height: 18)
        sourceLanguagePopup.frame = NSRect(x: padding, y: languageY, width: 150, height: languageHeight)
        swapLanguagesButton.frame = NSRect(x: sourceLanguagePopup.frame.maxX + 8, y: languageY, width: 38, height: languageHeight)
        targetLanguagePopup.frame = NSRect(x: swapLanguagesButton.frame.maxX + 8, y: languageY, width: 150, height: languageHeight)
        inputScrollView.frame = inputFrame
        inputScrollView.hasVerticalScroller = inputHeight >= maxInputHeight
        inputTextView.textContainer?.containerSize = NSSize(width: inputFrame.width - 20, height: .greatestFiniteMagnitude)
        inputTextView.frame = NSRect(x: 0, y: 0, width: inputFrame.width, height: inputHeight)
        layoutActionButtons(y: buttonY, height: buttonHeight, gap: buttonGap, width: width - padding * 2, titles: buttonTitles, fonts: buttonFonts)
        if let resultCard = textScrollView.superview {
            resultCard.frame = NSRect(x: padding, y: resultY, width: width - padding * 2, height: resultHeight)
            textScrollView.frame = NSRect(x: 1, y: 1, width: resultCard.frame.width - 2, height: resultCard.frame.height - 2)
        }
        popover.contentSize = root.frame.size
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

    private func currentPopoverHeight() -> CGFloat {
        let baseHeight = CGFloat(config.ui.height)
        return min(max(baseHeight, preferredPopoverHeight()), baseHeight + 300)
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
        LanguageDetector.resolvedPair(selectedSource: selectedSourceLanguage(), selectedTarget: selectedTargetLanguage(), text: text)
    }

    private func configureLanguageControls() {
        sourceLanguagePopup.removeAllItems()
        sourceLanguagePopup.addItems(withTitles: LanguageDetector.supportedLanguages)
        sourceLanguagePopup.selectItem(withTitle: LanguageDetector.normalizeSource(config.resolvedSourceLang))
        sourceLanguagePopup.target = self
        sourceLanguagePopup.action = #selector(languageSelectionChanged)

        targetLanguagePopup.removeAllItems()
        targetLanguagePopup.addItems(withTitles: LanguageDetector.supportedLanguages.filter { $0 != "Auto detect" })
        targetLanguagePopup.selectItem(withTitle: LanguageDetector.normalizeTarget(config.resolvedTargetLang))
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
        if LanguageDetector.looksChinese(text) {
            return config.speechSourceModelChinese
        }
        if LanguageDetector.looksVietnamese(text) {
            return config.speechSourceModelVietnamese
        }
        return config.speechSourceModel
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
        statusMenu.addItem(withTitle: "Grant Accessibility Access", action: #selector(requestAccessibilityPermissionMenu), keyEquivalent: "")
        statusMenu.addItem(withTitle: "Reload Config", action: #selector(reloadConfigMenu), keyEquivalent: "r")
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        statusMenu.items.forEach { $0.target = self }
        statusItem.menu = statusMenu
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func requestAccessibilityPermissionMenu() {
        requestAccessibilityPermissionIfNeeded(forcePrompt: true)
    }

    @objc private func reloadConfigMenu() {
        reloadConfig(showSuccess: true)
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
                Task { @MainActor in controller.translateAtCursor() }
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

    @objc private func manualToggle() {
        guard NSApp.currentEvent?.type == .leftMouseUp else { return }
        if popover.isShown {
            restoresPreviousAppOnClose = true
            popover.performClose(nil)
        } else if let button = statusItem.button {
            activatesAppOnShow = true
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
            focusInputTextView()
        }
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
        do {
            translator = try Translator(config: config, apiKey: APIKeychain.load(service: config.keychainService))
            registerHotKey()
            assert(URL(string: config.apiBaseURL) != nil)
            assert(URL(string: config.speechURL) != nil)
            if let message = outcome.message {
                setResultText("Config load error: \(message)")
            } else if showSuccess {
                setResultText("Reloaded config from \(AppConfig.configPath)")
            }
        } catch {
            setResultText("Config load error: \(error.localizedDescription)")
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

    private func moveAnchorWindowToMouse() {
        let mouse = NSEvent.mouseLocation
        anchorWindow.setFrame(NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1), display: false)
        anchorWindow.orderFrontRegardless()
    }

    private func restorePreviousAppFocus() {
        guard restoresPreviousAppOnClose else { return }
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }

    private func installOutsideClickMonitor() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                self.restoresPreviousAppOnClose = true
                self.popover.performClose(nil)
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        globalMouseMonitor = nil
    }

    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitor()
        restorePreviousAppFocus()
        previousApp = nil
        restoresPreviousAppOnClose = false
        activatesAppOnShow = false
    }

    func popoverDidShow(_ notification: Notification) {
        installOutsideClickMonitor()
        if activatesAppOnShow {
            NSApp.activate(ignoringOtherApps: true)
        }
        focusInputTextView()
    }

    private func focusInputTextView() {
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  let window = self.popover.contentViewController?.view.window
            else { return }
            window.makeKey()
            window.makeFirstResponder(self.inputTextView)
        }
    }

    private func updateLanguageSelection(for text: String) {
        let pair = resolvedLanguagePair(for: text)
        sourceLanguagePopup.selectItem(withTitle: pair.source)
        targetLanguagePopup.selectItem(withTitle: pair.target)
    }

    func translateAtCursor() {
        if !AXIsProcessTrusted() {
            requestAccessibilityPermissionIfNeeded(forcePrompt: true)
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        let text = SelectionReader.snapshotText() ?? NSPasteboard.general.string(forType: .string) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputTextView.string = trimmed
        reflowLayout()
        updateLanguageSelection(for: trimmed)
        setResultText("Translating...")
        moveAnchorWindowToMouse()
        if !popover.isShown, let contentView = anchorWindow.contentView {
            restoresPreviousAppOnClose = false
            activatesAppOnShow = false
            popover.show(relativeTo: contentView.bounds, of: contentView, preferredEdge: .maxY)
        }
        focusInputTextView()
        runTranslate()
    }

    @objc func runTranslate() {
        guard let translator else { return }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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

    private func playSpeech(_ text: String, model: String, kind: SpeechKind) {
        guard let translator else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let speechModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !speechModel.isEmpty else {
            setResultText("Error: Empty speech model")
            return
        }
        setSpeaking(true, for: kind)
        translator.speak(trimmed, model: speechModel) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.setSpeaking(false, for: kind) }
                switch result {
                case let .success(fileURL):
                    do {
                        self.audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                        self.audioPlayer?.prepareToPlay()
                        self.audioPlayer?.play()
                    } catch {
                        self.setResultText("Error: \(error.localizedDescription)")
                    }
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
        playSpeech(textView.string, model: config.speechTargetModel, kind: .result)
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
            popover.performClose(nil)
            return
        }
        isPastingResult = true
        let app = previousApp
        restoresPreviousAppOnClose = false
        popover.performClose(nil)
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
        popover.performClose(nil)
    }
}
