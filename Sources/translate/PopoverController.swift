import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation
import QuartzCore

extension NSAttributedString {
    static func plainDisplay(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }
}

struct AsyncGeneration {
    private(set) var current = 0

    mutating func advance() -> Int { current += 1; return current }
    mutating func invalidate() { current += 1 }
    func accepts(_ value: Int) -> Bool { value == current }
}

enum PopoverIntegrationPolicy {
    static func sourceControlsEnabled(hasPendingImage: Bool) -> Bool { !hasPendingImage }

    static func shouldPrefetchSource(enabled: Bool, hasPendingImage: Bool, text: String) -> Bool {
        enabled && !hasPendingImage && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func acceptsPrefetch(translationGeneration: Int, currentGeneration: Int) -> Bool {
        translationGeneration == currentGeneration
    }

    static func recordedSpeechIdentity(
        _ identity: SpeechIdentity,
        translationGeneration: Int,
        currentGeneration: Int,
        recordID: UUID?
    ) -> SpeechIdentity? {
        guard identity.kind == .source, acceptsPrefetch(translationGeneration: translationGeneration, currentGeneration: currentGeneration), let recordID else { return nil }
        return SpeechIdentity(kind: .source, text: identity.text, model: identity.model, recordID: recordID)
    }

    static func canAttachAudio(identity: SpeechIdentity, currentRecordID: UUID?) -> Bool {
        identity.recordID != nil && identity.recordID == currentRecordID
    }

    static func canSave(sourceText: String, resultText: String, isRequestInFlight: Bool) -> Bool {
        !isRequestInFlight
            && !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && PopoverFeedback.isCopyableResult(resultText)
    }

    static func imageSearchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "tbm", value: "isch"),
            URLQueryItem(name: "q", value: query)
        ]
        return components.url
    }

    static func resolvedImageSearchURL(queryResult: Result<String, Error>, fallbackText: String) -> URL? {
        switch queryResult {
        case let .success(query):
            return imageSearchURL(query: query) ?? imageSearchURL(query: fallbackText)
        case .failure:
            return imageSearchURL(query: fallbackText)
        }
    }
}

enum SpeechAudioPolicy {
    static func isValid(_ data: Data, validator: (Data) throws -> Void = { _ = try AVAudioPlayer(data: $0) }) -> Bool {
        do { try validator(data); return true } catch { return false }
    }
}

/// Borderless windows don't become key by default; override so the input text view can accept typing.
final class TranslatePanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class InputTextView: NSTextView {
    var onImagePasted: ((Data) -> Void)?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            onImagePasted?(data)
            return
        }
        if let image = NSImage(pasteboard: pb),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            onImagePasted?(png)
            return
        }
        super.paste(sender)
    }
}

@MainActor
final class PopoverController: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate, NSMenuDelegate, @preconcurrency AVAudioPlayerDelegate {
    private struct PendingSourceSpeech {
        let identity: SpeechIdentity
        let data: Data
    }

    private static let buildVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    /// Split Prism chrome — dual-pane + bottom bar inside Liquid Glass shell.
    private enum ChromeLayout {
        static let padding: CGFloat = 14
        /// Bottom inset for footer controls — a bit more air from the popup edge.
        static let paddingBottom: CGFloat = 16
        static let headerHeight: CGFloat = 22
        static let statusHeight: CGFloat = 14
        /// Gap between title/header and the split body.
        static let headerGap: CGFloat = 12
        /// Gap between split body and bottom controls.
        static let footerGap: CGFloat = 16
        static let paneHeaderHeight: CGFloat = 30
        static let paneHeaderTopInset: CGFloat = 4
        static let splitMinPaneHeight: CGFloat = 160
        static let splitMaxPaneHeight: CGFloat = 420
        static let dividerWidth: CGFloat = 1
        /// Shared height for Learn / Translate.
        static let controlHeight: CGFloat = 32
        static let bottomBarHeight: CGFloat = controlHeight
        /// Compact language selects (smaller than primary actions).
        static let languageControlHeight: CGFloat = 26
        static let languageWidth: CGFloat = 118
        static let languageCornerRadius: CGFloat = 12
        static let swapWidth: CGFloat = languageControlHeight
        static let iconButtonSize: CGFloat = 18
        static let chromeIconSize: CGFloat = 24
        static let glassCornerRadius: CGFloat = 22
        static let splitCornerRadius: CGFloat = 16
        /// Matches popup softness on compact controls (pill-ish at control height).
        static let controlCornerRadius: CGFloat = 16
        /// Source / translation body text.
        static let bodyFontSize: CGFloat = 14
        /// Learn / Translate labels.
        static let controlFontSize: CGFloat = 12
        /// Language select labels (compact).
        static let languageFontSize: CGFloat = 10
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
    private let inputTextView = InputTextView(frame: .zero)
    private let inputScrollView = NSScrollView(frame: .zero)
    private let imagePlaceholderLabel = NSTextField(labelWithString: "[Image from clipboard]")
    /// Official Liquid Glass container — merges nearby glass views.
    private let glassContainer = NSGlassEffectContainerView(frame: .zero)
    private let shellGlass = NSGlassEffectView(frame: .zero)
    private let chromeHost = NSView(frame: .zero)
    private let splitHost = NSView(frame: .zero)
    private let splitDivider = NSView(frame: .zero)
    private let sourceCard = NSView(frame: .zero)
    private let sourceHeaderBar = NSView(frame: .zero)
    private let sourceHeaderLabel = NSTextField(labelWithString: "Source")
    private let resultCard = NSView(frame: .zero)
    private let resultHeaderBar = NSView(frame: .zero)
    private let resultHeaderLabel = NSTextField(labelWithString: "Translation")
    private let sourceLanguageButton = NSButton(frame: .zero)
    private let targetLanguageButton = NSButton(frame: .zero)
    private var sourceLanguageSelection = ""
    private var targetLanguageSelection = ""
    private var sourceLanguageOptions: [String] = []
    private var targetLanguageOptions: [String] = []
    private let swapLanguagesButton = NSButton(frame: .zero)
    private let historyButton = NSButton(frame: .zero)
    private let updateButton = NSButton(frame: .zero)
    private let pinButton = NSButton(frame: .zero)
    private let closeButton = NSButton(frame: .zero)
    private let translateButton = NSButton(frame: .zero)
    private let learnButton = NSButton(frame: .zero)
    private let imagesButton = NSButton(frame: .zero)
    private let copyButton = NSButton(frame: .zero)
    private let saveWordButton = NSButton(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "Translate")
    private let statusLabel = NSTextField(labelWithString: "")
    private let speakSourceButton = NSButton(frame: .zero)
    private let speakResultButton = NSButton(frame: .zero)
    private var splitDividerGradient: CAGradientLayer?
    private var translator: Translator?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyEventHandlerRef: EventHandlerRef?
    private var config = AppConfig.load()
    private var audioPlayer: AVAudioPlayer?
    private var speechState = SpeechPlaybackState()
    private var speechCache: [SpeechIdentity: Data] = [:]
    private var prefetchGeneration = 0
    private var prefetchingSpeech: Set<SpeechIdentity> = []
    private var pendingSourceSpeech: [Int: PendingSourceSpeech] = [:]
    private var pendingImage: Data?
    private var historyStore: TranslationHistoryStore = TranslationHistoryStore(config: AppConfig.load())
        private lazy var historyWindowController: HistoryWindowController = {
        let controller = HistoryWindowController(store: historyStore) { [weak self] record in
            guard let self else { return }
            self.historyWindowController.close()
            self.openTranslatePanelShowingSetupStatus()
            self.openHistoryRecord(record)
        }
        return controller
    }()
    private var currentRecordID: UUID?
    private var requestGeneration = 0
    private var isRequestInFlight = false
    private var keyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var restoresPreviousAppOnClose = false
    private var activatesAppOnShow = false
    private var isPastingResult = false
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
        performUpdateCheck(silent: true)
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

        // Always light chrome — white glass, dark text/icons (matches design sample).
        let light = NSAppearance(named: .aqua)
        panel.appearance = light
        glassContainer.appearance = light
        chromeHost.appearance = light

        glassContainer.frame = NSRect(x: 0, y: 0, width: width, height: height)
        glassContainer.spacing = 0
        glassContainer.focusRingType = .none

        shellGlass.frame = glassContainer.bounds
        shellGlass.cornerRadius = L.glassCornerRadius
        shellGlass.style = .regular
        shellGlass.focusRingType = .none
        shellGlass.contentView = chromeHost
        chromeHost.frame = shellGlass.bounds
        chromeHost.autoresizingMask = [.width, .height]
        chromeHost.focusRingType = .none

        titleLabel.stringValue = "NTranslate"
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.textColor = NSColor.black.withAlphaComponent(0.92)
        titleLabel.drawsBackground = false
        titleLabel.toolTip = "NTranslate v\(Self.buildVersion)"

        statusLabel.font = .systemFont(ofSize: 10)
        statusLabel.textColor = NSColor.black.withAlphaComponent(0.45)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        statusLabel.drawsBackground = false

        configureChromeIconButton(closeButton, symbol: "xmark", action: #selector(closePopover), label: "Close")
        configureChromeIconButton(pinButton, symbol: "pin", action: #selector(togglePin), label: "Pin")
        configureChromeIconButton(historyButton, symbol: "clock.arrow.circlepath", action: #selector(openTranslationHistory), label: "Translation History")
        configureChromeIconButton(updateButton, symbol: "arrow.triangle.2.circlepath", action: #selector(checkForUpdatesClicked), label: "Check for Updates")
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
        inputTextView.textColor = NSColor.black.withAlphaComponent(0.88)
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
        imagePlaceholderLabel.textColor = NSColor.black.withAlphaComponent(0.55)
        imagePlaceholderLabel.isHidden = true
        imagePlaceholderLabel.setAccessibilityLabel("Image from clipboard")

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: ChromeLayout.bodyFontSize)
        textView.textColor = NSColor.black.withAlphaComponent(0.88)
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
        configureIconButton(speakSourceButton, symbol: "speaker.wave.2", action: #selector(speakInput), label: "Speak source")
        configureIconButton(speakResultButton, symbol: "speaker.wave.2", action: #selector(speakResult), label: "Speak translation")
        configureIconButton(copyButton, symbol: "doc.on.doc", action: #selector(copyResult), label: "Copy")
        configureIconButton(saveWordButton, symbol: "bookmark", action: #selector(toggleSaveWord), label: "Save Word")

        updateSpeakButtons()
        updateSaveWordButton()
        updateBusyState()
        languageSelectionChanged()

        sourceHeaderBar.addSubview(sourceHeaderLabel)
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
        chromeHost.addSubview(historyButton)
        chromeHost.addSubview(pinButton)
        chromeHost.addSubview(closeButton)
        chromeHost.addSubview(splitHost)
        chromeHost.addSubview(sourceLanguageButton)
        chromeHost.addSubview(swapLanguagesButton)
        chromeHost.addSubview(targetLanguageButton)
        chromeHost.addSubview(imagesButton)
        chromeHost.addSubview(learnButton)
        chromeHost.addSubview(translateButton)

        let containerHost = NSView(frame: glassContainer.bounds)
        containerHost.autoresizingMask = [.width, .height]
        containerHost.addSubview(shellGlass)
        glassContainer.contentView = containerHost

        layoutSplitPrism(width: width, height: height)
        panel.contentView = glassContainer
        panel.setFrame(NSRect(origin: panel.frame.origin, size: glassContainer.frame.size), display: false)
    }

    private func installSplitDividerGradient() {
        splitDivider.wantsLayer = true
        splitDivider.layer?.backgroundColor = NSColor.clear.cgColor
        splitDivider.layer?.masksToBounds = true
        splitDividerGradient?.removeFromSuperlayer()
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor.white.withAlphaComponent(0.0).cgColor,
            NSColor.white.withAlphaComponent(0.7).cgColor,
            NSColor.black.withAlphaComponent(0.06).cgColor,
            NSColor.white.withAlphaComponent(0.7).cgColor,
            NSColor.white.withAlphaComponent(0.0).cgColor
        ]
        gradient.locations = [0, 0.18, 0.5, 0.82, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        splitDivider.layer?.addSublayer(gradient)
        splitDividerGradient = gradient
    }

    private func applySplitHostChrome() {
        splitHost.layer?.borderWidth = 1
        splitHost.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
        splitHost.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.72).cgColor
    }

    private func applyControlCornerRadius(_ view: NSView, radius: CGFloat? = nil) {
        let resolved = radius ?? ChromeLayout.controlCornerRadius
        view.wantsLayer = true
        view.layer?.cornerRadius = resolved
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }

    private func stylePane(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func stylePaneHeaderBar(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func configurePaneHeaderLabel(_ label: NSTextField, title: String) {
        label.stringValue = title
        label.font = .systemFont(ofSize: 9, weight: .bold)
        label.textColor = NSColor.black.withAlphaComponent(0.38)
        label.isBezeled = false
        label.drawsBackground = false
        label.isEditable = false
    }

    private func paneLanguageCode(_ language: String) -> String {
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

    private func updatePaneLanguageLabels() {
        let sourceTitle = selectedSourceLanguage()
        let targetTitle = selectedTargetLanguage()
        if sourceTitle == LanguageDetector.autoDetect {
            let trimmed = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            sourceHeaderLabel.stringValue = trimmed.isEmpty
                ? "AUTO"
                : paneLanguageCode(LanguageDetector.detectedLanguage(trimmed))
        } else {
            sourceHeaderLabel.stringValue = paneLanguageCode(sourceTitle)
        }
        resultHeaderLabel.stringValue = paneLanguageCode(targetTitle)
    }

    private func configurePrimaryButton(
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

    private func configureChromeIconButton(_ button: NSButton, symbol: String, action: Selector, label: String) {
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
        button.contentTintColor = NSColor.black.withAlphaComponent(0.55)
        applyControlCornerRadius(button, radius: ChromeLayout.chromeIconSize / 2)
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
        button.contentTintColor = NSColor.black.withAlphaComponent(0.4)
    }

    private func resetCopyButtonAppearance() {
        copyButton.title = ""
        copyButton.attributedTitle = NSAttributedString(string: "")
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyButton.imagePosition = .imageOnly
        copyButton.contentTintColor = NSColor.black.withAlphaComponent(0.4)
    }

    private func reflowLayout() {
        guard panel.contentView != nil else { return }
        let width = CGFloat(config.ui.width)
        let height = currentPopoverHeight()
        layoutSplitPrism(width: width, height: height)
        applyPanelFrame(size: NSSize(width: width, height: height))
    }

    private func layoutSplitPrism(width: CGFloat, height: CGFloat) {
        let L = ChromeLayout.self
        let contentWidth = width - L.padding * 2
        let panes = PopoverLayoutMath.splitPaneWidth(contentWidth: contentWidth, divider: L.dividerWidth)
        let statusH = statusLabel.isHidden ? 0 : L.statusHeight

        let headerY = height - L.padding - L.headerHeight
        let statusY = headerY - statusH
        let bottomY = L.paddingBottom
        let splitY = bottomY + L.bottomBarHeight + L.footerGap
        // Pin body under the header so extra panel height grows the pane — never a dead gap.
        let splitTop = (statusH > 0 ? statusY : headerY) - L.headerGap
        let availableSplitHeight = max(0, splitTop - splitY)
        let measuredSplitHeight = currentSplitPaneHeight(paneWidth: panes.left)
        let splitHeight = min(
            L.splitMaxPaneHeight,
            max(measuredSplitHeight, availableSplitHeight)
        )
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
        applyControlCornerRadius(closeButton, radius: chromeIcon / 2)
        applyControlCornerRadius(pinButton, radius: chromeIcon / 2)
        applyControlCornerRadius(historyButton, radius: chromeIcon / 2)
        applyControlCornerRadius(updateButton, radius: chromeIcon / 2)

        splitHost.frame = NSRect(x: L.padding, y: splitY, width: contentWidth, height: splitHeight)

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

        // Bottom bar: Images | Learn | Translate | spacer | EN | swap | VI
        translateButton.sizeToFit()
        learnButton.sizeToFit()
        imagesButton.sizeToFit()
        let btnH = L.controlHeight
        let btnY = bottomY
        let translateW = max(92, translateButton.frame.width)
        let learnW = max(72, learnButton.frame.width)
        let imagesW = max(72, imagesButton.frame.width)
        imagesButton.frame = NSRect(
            x: L.padding,
            y: btnY,
            width: imagesW,
            height: btnH
        )
        learnButton.frame = NSRect(
            x: imagesButton.frame.maxX + 5,
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

        let dropdownWidth = L.languageWidth
        let langH = L.languageControlHeight
        let langY = btnY + (btnH - langH) / 2
        let swapSize = L.swapWidth
        targetLanguageButton.frame = NSRect(
            x: width - L.padding - dropdownWidth,
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
    }

    private func layoutPaneChrome(
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
        scrollView.frame = NSRect(x: 0, y: 0, width: paneWidth, height: bodyHeight)
        scrollView.hasVerticalScroller = true
        textView.minSize = NSSize(width: 0, height: bodyHeight)
        if textView === inputTextView {
            imagePlaceholderLabel.frame = NSRect(x: 12, y: 10, width: max(0, paneWidth - 24), height: 22)
        }
    }

    private func currentSplitPaneHeight(paneWidth: CGFloat) -> CGFloat {
        let L = ChromeLayout.self
        let measureWidth = max(80, paneWidth - 24)
        let sourceMeasured = measuredTextHeight(inputTextView.attributedString(), width: measureWidth) + 20
        let resultMeasured = measuredTextHeight(textView.attributedString(), width: measureWidth) + 20
        return PopoverLayoutMath.splitPaneHeight(
            sourceMeasured: sourceMeasured,
            resultMeasured: resultMeasured,
            paneHeaderHeight: L.paneHeaderHeight,
            minPaneHeight: L.splitMinPaneHeight,
            maxPaneHeight: L.splitMaxPaneHeight
        )
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
            color = NSColor.black.withAlphaComponent(0.88)
        case .loading:
            color = NSColor.black.withAlphaComponent(0.4)
        case .error:
            color = .systemRed
        }
        textView.textStorage?.setAttributedString(
            .plainDisplay(value, font: .systemFont(ofSize: ChromeLayout.bodyFontSize), color: color)
        )
    }

    private func setStatus(_ message: String, autoClearAfter: TimeInterval = 4) {
        statusClearWorkItem?.cancel()
        let wasHidden = statusLabel.isHidden
        statusLabel.stringValue = message
        statusLabel.isHidden = message.isEmpty
        if wasHidden != statusLabel.isHidden {
            reflowLayout()
        }
        if !message.isEmpty {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.statusLabel.stringValue = ""
                if !self.statusLabel.isHidden {
                    self.statusLabel.isHidden = true
                    self.reflowLayout()
                }
            }
            statusClearWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + autoClearAfter, execute: work)
        }
    }

    private func clearStatus() {
        statusClearWorkItem?.cancel()
        statusClearWorkItem = nil
        let wasHidden = statusLabel.isHidden
        statusLabel.stringValue = ""
        statusLabel.isHidden = true
        if !wasHidden {
            reflowLayout()
        }
    }

    private func beginRequest() -> Int {
        requestGeneration += 1
        pendingSourceSpeech = pendingSourceSpeech.filter { $0.key >= requestGeneration }
        isRequestInFlight = true
        updateBusyState()
        return requestGeneration
    }

    private func finishRequest(generation: Int) {
        guard generation == requestGeneration else { return }
        isRequestInFlight = false
        updateBusyState()
    }

    private func invalidateTranslationRequest() {
        requestGeneration += 1
        isRequestInFlight = false
        pendingSourceSpeech.removeAll()
        invalidateCurrentRecord()
        updateBusyState()
    }

    private func updateBusyState() {
        translateButton.isEnabled = !isRequestInFlight
        learnButton.isEnabled = !isRequestInFlight && pendingImage == nil
        imagesButton.isEnabled = !isRequestInFlight && pendingImage == nil
        swapLanguagesButton.isEnabled = !isRequestInFlight && pendingImage == nil
        sourceLanguageButton.isEnabled = !isRequestInFlight && PopoverIntegrationPolicy.sourceControlsEnabled(hasPendingImage: pendingImage != nil)
        targetLanguageButton.isEnabled = !isRequestInFlight
        updateSpeakButtons()
        updateCopyButtonEnabled()
        updateSaveWordButton()
    }

    private func updateCopyButtonEnabled() {
        copyButton.isEnabled = PopoverFeedback.isCopyableResult(textView.string)
    }

    private func preferredPopoverHeight() -> CGFloat {
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
            footerGap: L.footerGap,
            bottomBarHeight: L.bottomBarHeight
        )
    }

    private func maxPopoverHeight() -> CGFloat {
        CGFloat(config.ui.height) + 300
    }

    private func currentPopoverHeight() -> CGFloat {
        // Hug content — don't force config.ui.height as a floor (that left empty chrome).
        min(max(preferredPopoverHeight(), 220), maxPopoverHeight())
    }

    private func measuredTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        PopoverLayoutMath.measuredTextHeight(text, width: width)
    }

    private func selectedSourceLanguage() -> String {
        sourceLanguageSelection.isEmpty ? config.resolvedSourceLang : sourceLanguageSelection
    }

    private func selectedTargetLanguage() -> String {
        targetLanguageSelection.isEmpty ? config.resolvedTargetLang : targetLanguageSelection
    }

    private enum LanguageButtonKind: Int {
        case source = 1
        case target = 2
    }

    private func selectLanguage(_ language: String, kind: LanguageButtonKind) {
        switch kind {
        case .source:
            sourceLanguageSelection = language
            styleLanguageButtonTitle(sourceLanguageButton, language: language)
        case .target:
            targetLanguageSelection = language
            styleLanguageButtonTitle(targetLanguageButton, language: language)
        }
    }

    private func languageMenuFont() -> NSFont {
        .systemFont(ofSize: ChromeLayout.languageFontSize, weight: .regular)
    }

    private func configureLanguageButton(_ button: NSButton, kind: LanguageButtonKind) {
        button.bezelStyle = .glass
        button.controlSize = .small
        button.imagePosition = .imageTrailing
        button.imageHugsTitle = true
        button.target = self
        button.action = #selector(showLanguageMenu(_:))
        button.tag = kind.rawValue
        button.font = languageMenuFont()
        button.contentTintColor = NSColor.black.withAlphaComponent(0.75)
        let chevron = NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)
        button.image = NSImage(
            systemSymbolName: "chevron.up.chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(chevron)
        applyControlCornerRadius(button, radius: ChromeLayout.languageCornerRadius)
    }

    private func styleLanguageButtonTitle(_ button: NSButton, language: String) {
        button.title = language
        button.attributedTitle = NSAttributedString(
            string: language,
            attributes: [
                .font: languageMenuFont(),
                .foregroundColor: NSColor.black.withAlphaComponent(0.78)
            ]
        )
        button.toolTip = language
        button.setAccessibilityLabel(language)
    }

    private func populateLanguageButton(
        _ button: NSButton,
        kind: LanguageButtonKind,
        languages: [String],
        selected: String
    ) {
        switch kind {
        case .source: sourceLanguageOptions = languages
        case .target: targetLanguageOptions = languages
        }
        selectLanguage(selected, kind: kind)
        configureLanguageButton(button, kind: kind)
        styleLanguageButtonTitle(button, language: selected)
    }

    @objc private func showLanguageMenu(_ sender: NSButton) {
        guard let kind = LanguageButtonKind(rawValue: sender.tag) else { return }
        let languages = kind == .source ? sourceLanguageOptions : targetLanguageOptions
        let selected = kind == .source ? selectedSourceLanguage() : selectedTargetLanguage()
        let menu = NSMenu()
        let font = languageMenuFont()
        for language in languages {
            let item = NSMenuItem(
                title: language,
                action: #selector(languageMenuItemChosen(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.attributedTitle = NSAttributedString(
                string: language,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.black.withAlphaComponent(0.85)
                ]
            )
            item.representedObject = language
            item.toolTip = language
            item.state = language == selected ? .on : .off
            item.tag = kind.rawValue
            menu.addItem(item)
        }
        let point = NSPoint(x: 0, y: sender.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    @objc private func languageMenuItemChosen(_ sender: NSMenuItem) {
        guard let kind = LanguageButtonKind(rawValue: sender.tag),
              let language = sender.representedObject as? String
        else { return }
        selectLanguage(language, kind: kind)
        languageSelectionChanged()
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
        populateLanguageButton(
            sourceLanguageButton,
            kind: .source,
            languages: config.languages,
            selected: LanguageDetector.normalizeSource(config.resolvedSourceLang, languages: config.languages)
        )

        let savedTarget = UserDefaults.standard.string(forKey: Self.lastTargetLangKey) ?? config.resolvedTargetLang
        let normalizedTarget = LanguageDetector.normalizeTarget(
            savedTarget,
            targetLanguages: config.targetLanguages,
            fallback: config.resolvedNativeLang
        )
        populateLanguageButton(
            targetLanguageButton,
            kind: .target,
            languages: config.targetLanguages,
            selected: normalizedTarget
        )
        recentTargets = [normalizedTarget]

        swapLanguagesButton.title = ""
        let swapSymbol = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        swapLanguagesButton.image = NSImage(
            systemSymbolName: "arrow.left.arrow.right",
            accessibilityDescription: "Swap languages"
        )?.withSymbolConfiguration(swapSymbol)
        swapLanguagesButton.imagePosition = .imageOnly
        swapLanguagesButton.bezelStyle = .glass
        swapLanguagesButton.controlSize = .small
        swapLanguagesButton.target = self
        swapLanguagesButton.action = #selector(swapLanguages)
        swapLanguagesButton.toolTip = "Swap languages"
        swapLanguagesButton.contentTintColor = NSColor.black.withAlphaComponent(0.55)
        applyControlCornerRadius(swapLanguagesButton, radius: ChromeLayout.languageCornerRadius)
        updatePaneLanguageLabels()
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === inputTextView else { return }
        if pendingImage != nil { setPendingImage(nil) }
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        updateSpeakButtons()
        updatePaneLanguageLabels()
        reflowLayout()
    }

    @objc private func languageSelectionChanged() {
        invalidateCurrentRecord()
        invalidateSpeech(stopPlayback: true)
        if pendingImage != nil {
            UserDefaults.standard.set(selectedTargetLanguage(), forKey: Self.lastTargetLangKey)
            updatePaneLanguageLabels()
            runTranslate()
            return
        }
        let text = inputTextView.string
        // User manually picked a target that matches the auto-detected source language —
        // that's a request for grammar-check mode, so pin the source dropdown to match
        // instead of letting auto-detect's target override snap it back.
        if selectedSourceLanguage() == "Auto detect" {
            let detected = LanguageDetector.detectedLanguage(text)
            if selectedTargetLanguage() == detected {
                selectLanguage(detected, kind: .source)
            }
        }
        let pair = resolvedLanguagePair(for: text)
        if selectedSourceLanguage() != pair.source {
            selectLanguage(pair.source, kind: .source)
        }
        if selectedTargetLanguage() != pair.target {
            selectLanguage(pair.target, kind: .target)
        }
        UserDefaults.standard.set(pair.target, forKey: Self.lastTargetLangKey)
        updatePaneLanguageLabels()
        styleLanguageButtonTitle(sourceLanguageButton, language: selectedSourceLanguage())
        styleLanguageButtonTitle(targetLanguageButton, language: selectedTargetLanguage())
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
        selectLanguage(target, kind: .source)
        let swappedTarget = source == LanguageDetector.autoDetect ? config.resolvedNativeLang : source
        selectLanguage(
            LanguageDetector.normalizeTarget(
                swappedTarget,
                targetLanguages: config.targetLanguages,
                fallback: config.resolvedNativeLang
            ),
            kind: .target
        )
        languageSelectionChanged()
    }

    private func updateSpeakButtons() {
        updateSpeechButton(speakSourceButton, identity: sourceSpeechIdentity(), baseLabel: "source")
        updateSpeechButton(speakResultButton, identity: resultSpeechIdentity(), baseLabel: "translation")
    }

    private func updateSpeechButton(_ button: NSButton, identity: SpeechIdentity?, baseLabel: String) {
        let action = identity.map { identity in
            prefetchingSpeech.contains(where: { speechMatches($0, identity) })
                ? SpeechButtonAction.loading
                : speechState.action(for: identity)
        } ?? .play
        let presentation: (symbol: String, verb: String, enabled: Bool)
        switch action {
        case .play: presentation = ("speaker.wave.2", "Play", identity != nil)
        case .loading: presentation = ("hourglass", "Loading", false)
        case .pause: presentation = ("pause.fill", "Pause", true)
        case .resume: presentation = ("play.fill", "Resume", true)
        }
        let label = "\(presentation.verb) \(baseLabel)"
        button.title = ""
        button.image = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.contentTintColor = NSColor.black.withAlphaComponent(0.4)
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.isEnabled = presentation.enabled && !isRequestInFlight
    }

    private func speechMatches(_ lhs: SpeechIdentity, _ rhs: SpeechIdentity) -> Bool {
        lhs.kind == rhs.kind && lhs.text == rhs.text && lhs.model == rhs.model
    }

    private func sourceSpeechIdentity(recordID: UUID? = nil) -> SpeechIdentity? {
        guard pendingImage == nil else { return nil }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return SpeechIdentity(kind: .source, text: text, model: sourceSpeechModel(for: text), recordID: recordID ?? currentRecordID)
    }

    private func resultSpeechIdentity(recordID: UUID? = nil) -> SpeechIdentity? {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard PopoverFeedback.isCopyableResult(text) else { return nil }
        return SpeechIdentity(
            kind: .result,
            text: text,
            model: SpeechModelResolver.model(for: selectedTargetLanguage(), config: config),
            recordID: recordID ?? currentRecordID
        )
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
        statusMenu.addItem(withTitle: "Open Translate Panel", action: #selector(openTranslatePanelMenu), keyEquivalent: "t")
        statusMenu.addItem(withTitle: "Translation History", action: #selector(openTranslationHistory), keyEquivalent: "h")
        statusMenu.addItem(withTitle: "Check for Updates...", action: #selector(checkForUpdatesClicked), keyEquivalent: "u")
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

    @objc private func openTranslatePanelMenu() {
        let outcome = reloadConfig(showSuccess: false)
        openTranslatePanelShowingSetupStatus(loadMessage: outcome.message)
    }

    @objc private func reloadConfigMenu() {
        let outcome = reloadConfig(showSuccess: true)
        let issues = outcome.config.setupIssues(
            loadMessage: outcome.message,
            accessibilityTrusted: AXIsProcessTrusted()
        )
        if !issues.isEmpty {
            openTranslatePanelShowingSetupStatus(loadMessage: outcome.message)
        }
    }

    @objc private func openConfigFileMenu() {
        NSWorkspace.shared.open(URL(fileURLWithPath: AppConfig.configPath))
    }

    @objc private func openTranslationHistory() {
        historyWindowController.showHistory()
    }

    /// Opens the translate panel and shows config/permission errors immediately when present.
    private func openTranslatePanelShowingSetupStatus(loadMessage: String? = nil) {
        if !panel.isVisible {
            if let button = statusItem.button, let buttonWindow = button.window {
                let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                showMousePoint = NSPoint(x: buttonFrameOnScreen.midX, y: buttonFrameOnScreen.minY)
            } else {
                showMousePoint = NSEvent.mouseLocation
            }
        }

        let issues = config.setupIssues(
            loadMessage: loadMessage,
            accessibilityTrusted: AXIsProcessTrusted()
        )

        if issues.isEmpty {
            let current = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty
                || current.hasPrefix("Error:")
                || current.hasPrefix("Config load error:")
                || current.hasPrefix("Created ")
            {
                setResultText(PopoverFeedback.emptySelectionGuidance)
            }
            clearStatus()
        } else {
            setResultText(AppConfig.formatSetupIssues(issues))
            setStatus("Fix the errors above, then Reload Config")
        }

        reflowLayout()
        updateBusyState()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
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
        _ = reloadConfig(showSuccess: false)
    }

    @discardableResult
    private func reloadConfig(showSuccess: Bool) -> AppConfig.LoadOutcome {
        let outcome = AppConfig.loadOutcome()
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        config = outcome.config
        historyStore = TranslationHistoryStore(config: config)
                historyWindowController = HistoryWindowController(store: historyStore) { [weak self] record in
            guard let self else { return }
            self.historyWindowController.close()
            self.openTranslatePanelShowingSetupStatus()
            self.openHistoryRecord(record)
        }
        if let loadError = historyStore.loadError {
            setStatus(loadError, autoClearAfter: 12)
        }
        reflowLayout()
        let apiKey = config.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            translator = nil
            if outcome.didSeedConfig {
                setResultText(
                    "Error: Created \(AppConfig.configPath). Set apiKey (from 9router), then menu → Reload Config."
                )
            } else if let message = outcome.message {
                setResultText("Error: \(message)")
            } else {
                setResultText("Error: apiKey is empty — edit \(AppConfig.configPath)")
            }
            return outcome
        }
        translator = Translator(config: config, apiKey: apiKey)
        configureLanguageControls()
        registerHotKey()
        assert(URL(string: config.apiBaseURL) != nil)
        assert(URL(string: config.apiSpeechURL) != nil)
        if let message = outcome.message {
            setResultText("Error: \(message)")
        } else if outcome.didSeedConfig {
            setResultText("Created config at \(AppConfig.configPath)")
        } else if showSuccess {
            setResultText("Reloaded config from \(AppConfig.configPath)")
        }
        return outcome
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
        invalidateCurrentRecord()
        invalidateSpeech(stopPlayback: true)
        clearStatus()
        copyFlashWorkItem?.cancel()
        copyFlashWorkItem = nil
        resetCopyButtonAppearance()
        updateBusyState()
        panel.orderOut(nil)
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

    @objc private func checkForUpdatesClicked() {
        performUpdateCheck(silent: false)
    }

    private func performUpdateCheck(silent: Bool) {
        Task { [weak self] in
            guard let self else { return }
            do {
                if let release = try await UpdateManager.shared.checkForUpdate() {
                    await MainActor.run {
                        self.showUpdateAlert(release: release)
                    }
                } else if !silent {
                    await MainActor.run {
                        self.showUpToDateAlert()
                    }
                }
            } catch {
                if !silent {
                    await MainActor.run {
                        self.showUpdateErrorAlert(error)
                    }
                }
            }
        }
    }

    private func showUpdateAlert(release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "Update Available: \(release.tag)"
        alert.informativeText = "A new version of NTranslate is available.\n\nRelease Notes:\n\(release.notes)"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update & Restart")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            Task { [weak self] in
                guard let self else { return }
                do {
                    let dmgURL = try await UpdateManager.shared.downloadDMG(from: release.dmgURL)
                    try UpdateManager.shared.installUpdateAndRestart(dmgURL: dmgURL)
                } catch {
                    await MainActor.run {
                        self.showUpdateErrorAlert(error)
                    }
                }
            }
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date!"
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        alert.informativeText = "NTranslate \(currentVersion) is currently the newest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showUpdateErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func updatePinButton() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Pin")
        if isPinned {
            // Match Translate accent glass fill; force white glyph (contentTint alone is unreliable on glass).
            pinButton.bezelColor = .controlAccentColor
            let whiteSymbol = NSImage.SymbolConfiguration(paletteColors: [.white])
                .applying(NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
            pinButton.image = base?.withSymbolConfiguration(whiteSymbol)
            pinButton.contentTintColor = .white
        } else {
            pinButton.bezelColor = nil
            let mutedSymbol = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            pinButton.image = base?.withSymbolConfiguration(mutedSymbol)
            pinButton.contentTintColor = NSColor.black.withAlphaComponent(0.55)
        }
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
        selectLanguage(pair.source, kind: .source)
        selectLanguage(pair.target, kind: .target)
        updatePaneLanguageLabels()
    }

    private func showEmptySelectionPanel(message: String = PopoverFeedback.emptySelectionGuidance) {
        if !panel.isVisible { showMousePoint = NSEvent.mouseLocation }
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        setPendingImage(nil)
        inputTextView.string = ""
        setResultText(message)
        clearStatus()
        reflowLayout()
        updateBusyState()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
    }

    private func setPendingImage(_ data: Data?) {
        pendingImage = data
        imagePlaceholderLabel.isHidden = data == nil
        updateBusyState()
    }

    func translateAtCursor() {
        if !AXIsProcessTrusted() { requestAccessibilityPermissionIfNeeded(forcePrompt: true) }
        previousApp = NSWorkspace.shared.frontmostApplication
        let resolved: TranslatableInputResolution
        do {
            guard let value = try SelectionReader.resolveTranslatableInputWithDiagnostics(simulateCopy: config.ui.simulateCopy) else {
                showEmptySelectionPanel()
                return
            }
            resolved = value
        } catch {
            showEmptySelectionPanel(message: "Error: \(error)")
            return
        }
        if !panel.isVisible { showMousePoint = NSEvent.mouseLocation }
        if resolved.accessibilityError != nil {
            setStatus(PopoverFeedback.accessibilityFallbackNote(source: resolved.source))
        } else {
            clearStatus()
        }
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        switch resolved.input {
        case let .text(text):
            setPendingImage(nil)
            inputTextView.string = text
            guard text.count <= config.maxTranslateLength else {
                setResultText(PopoverFeedback.textTooLong)
                reflowLayout()
                updateBusyState()
                presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
                return
            }
            updateLanguageSelection(for: text)
        case let .image(data):
            inputTextView.string = ""
            setPendingImage(data)
        }
        let generation = beginRequest()
        setResultText(PopoverFeedback.translating)
        reflowLayout()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        performTranslate(generation: generation)
    }

    @objc func runTranslate() {
        invalidateSpeech(stopPlayback: true)
        performTranslate(generation: nil)
    }

    private func performTranslate(generation existingGeneration: Int?) {
        invalidateCurrentRecord()
        let generation = existingGeneration ?? beginRequest()
        guard let translator else {
            finishRequest(generation: generation)
            return
        }
        if existingGeneration == nil {
            setResultText(PopoverFeedback.translating)
            reflowLayout()
        }
        if let image = pendingImage {
            translator.translateImage(image, targetLang: selectedTargetLanguage()) { [weak self] result in
                Task { @MainActor in self?.finishImageTranslation(result, generation: generation) }
            }
            return
        }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            invalidateTranslationRequest()
            setResultText(PopoverFeedback.emptyInputHint)
            reflowLayout()
            updateBusyState()
            return
        }
        guard text.count <= config.maxTranslateLength else {
            invalidateTranslationRequest()
            setResultText(PopoverFeedback.textTooLong)
            reflowLayout()
            updateBusyState()
            return
        }
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        if PopoverIntegrationPolicy.shouldPrefetchSource(
            enabled: config.autoPrefetchSpeech,
            hasPendingImage: pendingImage != nil,
            text: text
        ) {
            prefetchSpeech(sourceSpeechIdentity(recordID: nil), translationGeneration: generation)
        }
        translator.translate(text, sourceLang: pair.source, targetLang: pair.target) { [weak self] result in
            Task { @MainActor in self?.finishTextTranslation(result, generation: generation, source: text, pair: pair) }
        }
    }

    private func finishImageTranslation(_ result: Result<String, Error>, generation: Int) {
        defer { finishRequest(generation: generation) }
        guard generation == requestGeneration, pendingImage != nil else { return }
        invalidateCurrentRecord()
        switch result {
        case let .success(value):
            setResultText(value)
            prefetchSpeech(resultSpeechIdentity(), translationGeneration: nil)
        case let .failure(error):
            setResultText("Error: \(error.localizedDescription)")
        }
        reflowLayout()
        textView.scrollToBeginningOfDocument(nil)
        updateBusyState()
    }

    private func finishTextTranslation(_ result: Result<String, Error>, generation: Int, source: String, pair: (source: String, target: String)) {
        defer { finishRequest(generation: generation) }
        guard generation == requestGeneration, pendingImage == nil else { return }
        switch result {
        case let .success(value):
            let record = TranslationRecord(
                id: UUID(), timestamp: Date(), sourceText: source, resultText: value,
                sourceLanguage: pair.source, targetLanguage: pair.target,
                sourceAudioPath: nil, resultAudioPath: nil, isSaved: false
            )
            setResultText(value)
            do {
                try historyStore.append(record)
                currentRecordID = record.id
                attachPendingSourceSpeech(for: generation, recordID: record.id)
                historyWindowController.reloadHistory()
            } catch {
                currentRecordID = nil
                setStatus("History failed: \(error.localizedDescription)", autoClearAfter: 12)
            }
            prefetchSpeech(resultSpeechIdentity(recordID: currentRecordID), translationGeneration: nil)
            if config.ui.autoCopy {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                flashCopied()
            }
        case let .failure(error):
            invalidateCurrentRecord()
            setResultText("Error: \(error.localizedDescription)")
        }
        reflowLayout()
        textView.scrollToBeginningOfDocument(nil)
        updateBusyState()
    }

    @objc func runImages() {
        guard pendingImage == nil, let translator else { return }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= config.maxTranslateLength else { setStatus(PopoverFeedback.textTooLong); return }
        let generation = beginRequest()
        setStatus("Generating search query...")
        translator.imageSearchQuery(text) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.finishRequest(generation: generation) }
                guard generation == self.requestGeneration else { return }
                if let url = PopoverIntegrationPolicy.resolvedImageSearchURL(queryResult: result, fallbackText: text) {
                    NSWorkspace.shared.open(url)
                }
                switch result {
                case .success:
                    self.setStatus("Opened Google Images")
                case .failure:
                    self.setStatus("Image query failed; searched source text")
                }
                self.updateBusyState()
            }
        }
    }

    @objc func runLearn() {
        guard pendingImage == nil, let translator else { return }
        invalidateCurrentRecord()
        invalidateSpeech(stopPlayback: true)
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { setResultText(PopoverFeedback.emptyInputHint); reflowLayout(); updateBusyState(); return }
        guard text.count <= config.maxTranslateLength else { setResultText(PopoverFeedback.textTooLong); reflowLayout(); updateBusyState(); return }
        let pair = resolvedLanguagePair(for: text)
        updateLanguageSelection(for: text)
        let generation = beginRequest()
        setResultText(PopoverFeedback.learning)
        reflowLayout()
        translator.learn(text, sourceLang: pair.source, targetLang: pair.target) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                defer { self.finishRequest(generation: generation) }
                guard generation == self.requestGeneration else { return }
                switch result {
                case let .success(value): self.setResultText(value)
                case let .failure(error): self.setResultText("Error: \(error.localizedDescription)")
                }
                self.reflowLayout()
                self.textView.scrollToBeginningOfDocument(nil)
                self.updateBusyState()
            }
        }
    }

    private func prefetchSpeech(_ identity: SpeechIdentity?, translationGeneration: Int?) {
        guard config.autoPrefetchSpeech, let identity, let translator else { return }
        if let data = speechCache[identity] {
            acceptPrefetchedSpeech(data, identity: identity, translationGeneration: translationGeneration)
            return
        }
        guard !prefetchingSpeech.contains(identity) else { return }
        let generation = prefetchGeneration
        prefetchingSpeech.insert(identity)
        updateSpeakButtons()
        translator.speak(identity.text, model: identity.model) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                self.prefetchingSpeech.remove(identity)
                self.updateSpeakButtons()
                guard generation == self.prefetchGeneration, case let .success(data) = result,
                      SpeechAudioPolicy.isValid(data)
                else { return }
                self.speechCache[identity] = data
                self.acceptPrefetchedSpeech(data, identity: identity, translationGeneration: translationGeneration)
            }
        }
    }

    private func acceptPrefetchedSpeech(_ data: Data, identity: SpeechIdentity, translationGeneration: Int?) {
        if identity.kind == .source, let translationGeneration {
            if let recordedIdentity = PopoverIntegrationPolicy.recordedSpeechIdentity(
                identity, translationGeneration: translationGeneration,
                currentGeneration: requestGeneration, recordID: currentRecordID
            ) {
                speechCache[recordedIdentity] = data
                attachAudio(data, identity: recordedIdentity)
            } else {
                pendingSourceSpeech[translationGeneration] = PendingSourceSpeech(identity: identity, data: data)
            }
        } else {
            attachAudio(data, identity: identity)
        }
    }

    private func playSpeech(_ identity: SpeechIdentity?) {
        guard let identity,
              !prefetchingSpeech.contains(where: { speechMatches($0, identity) })
        else { return }
        switch speechState.action(for: identity) {
        case .pause:
            audioPlayer?.pause()
            _ = speechState.pause(identity)
            updateSpeakButtons()
        case .resume:
            guard audioPlayer?.play() == true else { resetSpeechPlayback(); return }
            _ = speechState.resume(identity)
            updateSpeakButtons()
        case .loading: break
        case .play:
            stopCurrentSpeech()
            if let data = speechCache[identity] { startPlayback(data, identity: identity) }
            else { loadAndPlaySpeech(identity) }
        }
    }

    private func loadAndPlaySpeech(_ identity: SpeechIdentity) {
        guard let translator else { return }
        let generation = speechState.beginLoading(identity)
        updateSpeakButtons()
        translator.speak(identity.text, model: identity.model) { [weak self] result in
            Task { @MainActor in
                guard let self, self.speechState.accepts(generation: generation, identity: identity) else { return }
                switch result {
                case let .success(data):
                    guard SpeechAudioPolicy.isValid(data),
                          self.startPlayback(data, identity: identity, loadingGeneration: generation)
                    else {
                        _ = self.speechState.finishLoading(generation: generation, identity: identity)
                        self.setStatus("Speak failed: Invalid audio response")
                        self.updateSpeakButtons()
                        return
                    }
                    self.speechCache[identity] = data
                    self.attachAudio(data, identity: identity)
                case let .failure(error):
                    _ = self.speechState.finishLoading(generation: generation, identity: identity)
                    self.setStatus("Speak failed: \(error.localizedDescription)")
                    self.updateSpeakButtons()
                }
            }
        }
    }

    @discardableResult
    private func startPlayback(_ data: Data, identity: SpeechIdentity, loadingGeneration: Int? = nil) -> Bool {
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { throw NSError(domain: "Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio could not be played"]) }
            audioPlayer = player
            if let loadingGeneration {
                guard speechState.markPlaying(generation: loadingGeneration, identity: identity) else { player.stop(); return false }
            } else {
                speechState.beginPlaying(identity)
            }
            updateSpeakButtons()
            return true
        } catch {
            resetSpeechPlayback()
            setStatus("Speak failed: \(error.localizedDescription)")
            return false
        }
    }

    private func stopCurrentSpeech() {
        audioPlayer?.stop()
        audioPlayer = nil
        speechState.reset()
    }

    private func resetSpeechPlayback() {
        audioPlayer = nil
        speechState.reset()
        updateSpeakButtons()
    }

    private func invalidateSpeech(stopPlayback: Bool) {
        prefetchGeneration += 1
        prefetchingSpeech.removeAll()
        pendingSourceSpeech.removeAll()
        speechState.invalidateRequests()
        if stopPlayback { stopCurrentSpeech() }
        updateSpeakButtons()
    }

    private func attachPendingSourceSpeech(for generation: Int, recordID: UUID) {
        guard let pending = pendingSourceSpeech.removeValue(forKey: generation) else { return }
        let identity = SpeechIdentity(kind: .source, text: pending.identity.text, model: pending.identity.model, recordID: recordID)
        speechCache[identity] = pending.data
        attachAudio(pending.data, identity: identity)
    }

    private func attachAudio(_ data: Data, identity: SpeechIdentity) {
        guard PopoverIntegrationPolicy.canAttachAudio(identity: identity, currentRecordID: currentRecordID),
              let recordID = identity.recordID,
              let record = historyStore.records.first(where: { $0.id == recordID }),
              identity.kind == .source ? record.sourceAudioPath == nil : record.resultAudioPath == nil
        else { return }
        do {
            try historyStore.attachAudio(data, kind: identity.kind == .source ? .source : .result, recordID: recordID)
            historyWindowController.reloadHistory()
        } catch {
            setStatus("History audio failed: \(error.localizedDescription)", autoClearAfter: 12)
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === audioPlayer else { return }
        resetSpeechPlayback()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard player === audioPlayer else { return }
        resetSpeechPlayback()
        if let error { setStatus("Speak failed: \(error.localizedDescription)") }
    }

    @objc func speakInput() { playSpeech(sourceSpeechIdentity()) }
    @objc func speakResult() { playSpeech(resultSpeechIdentity()) }

    private func invalidateCurrentRecord() {
        currentRecordID = nil
        updateSaveWordButton()
    }

    private func updateSaveWordButton() {
        let reqInFlight = isRequestInFlight
        let canSave = PopoverIntegrationPolicy.canSave(
            sourceText: inputTextView.string, 
            resultText: textView.string, 
            isRequestInFlight: reqInFlight
        )
        let isSaved = currentRecordID != nil
        
        saveWordButton.isHidden = !canSave
        if !saveWordButton.isHidden {
            saveWordButton.contentTintColor = isSaved ? .controlAccentColor : .secondaryLabelColor
            saveWordButton.image = NSImage(systemSymbolName: isSaved ? "bookmark.fill" : "bookmark", accessibilityDescription: "Save word")
        }
    }

    @objc private func toggleSaveWord() {
        guard let recordID = currentRecordID, let record = historyStore.records.first(where: { $0.id == recordID }) else { return }
        do {
            try historyStore.setSaved(!record.isSaved, recordID: recordID)
            historyWindowController.reloadHistory()
            updateSaveWordButton()
        } catch {
            setStatus("Save Word failed: \(error.localizedDescription)", autoClearAfter: 12)
        }
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
    private func openHistoryRecord(_ record: TranslationRecord) {
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)

        selectLanguage(record.sourceLanguage, kind: .source)
        selectLanguage(record.targetLanguage, kind: .target)

        inputTextView.string = record.sourceText
        setResultText(record.resultText)

        currentRecordID = record.id
        updateSaveWordButton()
        updatePaneLanguageLabels()

        focusInputTextView()
        reflowLayout()
    }
}