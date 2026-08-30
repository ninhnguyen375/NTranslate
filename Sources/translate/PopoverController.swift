// PopoverController state and app launch. Behaviour lives in the PopoverController+* extensions.
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation
import QuartzCore

@MainActor
final class PopoverController: NSObject, NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate, NSMenuDelegate, @preconcurrency AVAudioPlayerDelegate {
    struct PendingSourceSpeech {
        let identity: SpeechIdentity
        let data: Data
    }

    static let buildVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    /// Split Prism chrome — dual-pane + bottom bar inside Liquid Glass shell.
    enum ChromeLayout {
        static let padding: CGFloat = 14
        /// Bottom inset for footer controls — a bit more air from the popup edge.
        static let paddingBottom: CGFloat = 16
        /// Same height as the action chips so header and footer share one padding rhythm.
        static let headerHeight: CGFloat = 32
        static let statusHeight: CGFloat = 14
        /// Gap between title/header and the split body.
        static let headerGap: CGFloat = 12
        /// Gap between split body and bottom controls.
        static let footerGap: CGFloat = 16
        static let paneHeaderHeight: CGFloat = 30
        static let paneHeaderTopInset: CGFloat = 4
        static let splitMinPaneHeight: CGFloat = 160
        static let splitMinStackedPaneHeight: CGFloat = 120
        /// Vertical gap between stacked panes that do not use a labeled divider (e.g. Q&A).
        static let sectionGap: CGFloat = 10
        /// Labeled hairline between the main action row and the subtranslate pane.
        static let sectionDividerHeight: CGFloat = 20
        /// Empty space above the hairline so it does not sit flush on the main action row.
        static let sectionDividerTopMargin: CGFloat = 14
        static var sectionDividerReserved: CGFloat { sectionDividerTopMargin + sectionDividerHeight }
        static let splitMaxPaneHeight: CGFloat = 720
        /// Per-section cap once a subtranslate pane exists — two panes at `splitMaxPaneHeight` each
        /// overflow the panel.
        static let splitMaxStackedPaneHeight: CGFloat = 520
        static let dividerWidth: CGFloat = 1
        /// Shared height for Learn / Translate.
        static let controlHeight: CGFloat = 32
        static let qaInputHeight: CGFloat = 28
        static let bottomBarHeight: CGFloat = controlHeight
        /// Same height as chrome icon pills so the header row shares one padding rhythm.
        static let languageControlHeight: CGFloat = 32
        static let languageWidth: CGFloat = 132
        /// Language chips use a pill of `height / 2` after layout — never a CSS-style 999.
        static let swapWidth: CGFloat = languageControlHeight
        static let iconButtonSize: CGFloat = 18
        /// Circular glass chip — larger than the glyph so the pill has padding.
        static let chromeIconSize: CGFloat = 32
        static let glassCornerRadius: CGFloat = 22
        static let splitCornerRadius: CGFloat = 16
        /// Source / translation body text.
        static let bodyFontSize: CGFloat = 14
        /// Q&A transcript text — smaller than the main panes to fit more conversation.
        static let qaFontSize: CGFloat = 12
        /// Learn / Translate labels.
        static let controlFontSize: CGFloat = 12
        static let languageFontSize: CGFloat = 12
        static let titleFontSize: CGFloat = 16
    }

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let panel = LiquidGlassWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let textView = SelectableTextView(frame: .zero)
    let textScrollView = NSScrollView(frame: .zero)
    let inputTextView = InputTextView(frame: .zero)
    let inputScrollView = NSScrollView(frame: .zero)
    let inputContextLabel = NSTextField(labelWithString: "")
    let imagePlaceholderLabel = NSTextField(labelWithString: "[Image from clipboard]")
    /// Official Liquid Glass container — merges nearby glass views.
    let glassContainer = NSGlassEffectContainerView(frame: .zero)
    let shellGlass = NSGlassEffectView(frame: .zero)
    let chromeHost = ThemedView(frame: .zero)
    let splitHost = NSView(frame: .zero)
    let splitDivider = NSView(frame: .zero)
    let sourceCard = NSView(frame: .zero)
    let sourceHeaderBar = NSView(frame: .zero)
    let sourceHeaderLabel = NSTextField(labelWithString: "Source")
    let resultCard = NSView(frame: .zero)
    let resultHeaderBar = NSView(frame: .zero)
    let resultHeaderLabel = NSTextField(labelWithString: "Translation")
    let sourceLanguageButton = NSButton(frame: .zero)
    let targetLanguageButton = NSButton(frame: .zero)
    var sourceLanguageSelection = ""
    var targetLanguageSelection = ""
    var resolvedSourceLanguage: String?
    var sourceLanguageOptions: [String] = []
    var targetLanguageOptions: [String] = []
    let swapLanguagesButton = NSButton(frame: .zero)
    let historyButton = NSButton(frame: .zero)
    let reviewButton = NSButton(frame: .zero)
    let reviewBadgeLabel: NSTextField = {
        let field = NSTextField(frame: .zero)
        let cell = VerticallyCenteredTextFieldCell(textCell: "")
        cell.horizontalInset = 0
        field.cell = cell
        field.isEditable = false
        field.isSelectable = false
        field.isBezeled = false
        return field
    }()
    let updateButton = NSButton(frame: .zero)
    /// Hover-only indicator listing the recent translations sent as context with the next Translate.
    let pinButton = NSButton(frame: .zero)
    let closeButton = NSButton(frame: .zero)
    let mainActionRow = ActionRowSection()
    var translateButton: NSButton { mainActionRow.translateButton }
    var learnButton: NSButton { mainActionRow.learnButton }
    var imagesButton: NSButton { mainActionRow.imagesButton }
    var proofreadButton: NSButton { mainActionRow.proofreadButton }
    var askButton: NSButton { mainActionRow.askButton }
    let copyButton = NSButton(frame: .zero)
    let saveWordButton = NSButton(frame: .zero)
    let titleLabel = NSTextField(labelWithString: "Translate")
    let statusLabel = NSTextField(labelWithString: "")
    let speakSourceButton = NSButton(frame: .zero)
    let speakSourceSlowButton = NSButton(frame: .zero)
    let speakResultButton = NSButton(frame: .zero)
    let speakResultSlowButton = NSButton(frame: .zero)
    let retryButton = NSButton(frame: .zero)
    var splitDividerGradient: CAGradientLayer?
    var translator: Translator?
    var registeredHotKeys: [EventHotKeyRef] = []
    var hotKeyEventHandlerRef: EventHandlerRef?
    var ocrPollTimer: Timer?
    var config = AppConfig.load()
    var apiKey = ""
    var settingsWindowController: SettingsWindowController?
    var audioPlayer: AVAudioPlayer?
    var speechState = SpeechPlaybackState()
    var activeSpeechRate: Float = 1.0
    var speechCache: [SpeechIdentity: Data] = [:]
    var prefetchGeneration = 0
    var prefetchingSpeech: Set<SpeechIdentity> = []
    var pendingSourceSpeech: [Int: PendingSourceSpeech] = [:]
    var pendingImage: Data?
    var historyStore: TranslationHistoryStore = TranslationHistoryStore(config: AppConfig.load())
    lazy var historyWindowController: HistoryWindowController = {
        let controller = HistoryWindowController(store: historyStore) { [weak self] record in
            guard let self else { return }
            self.historyWindowController.close()
            self.openTranslatePanelShowingSetupStatus()
            self.openHistoryRecord(record)
        }
        return controller
    }()
    lazy var reviewWindowController: ReviewWindowController = {
        let controller = ReviewWindowController(store: historyStore, translator: translator, config: config)
        controller.onReviewsCompleted = { [weak self] in
            self?.updateReviewBadge()
        }
        controller.onOpenTranslate = { [weak self] record in
            guard let self else { return }
            self.openTranslatePanelShowingSetupStatus()
            self.openHistoryRecord(record)
        }
        return controller
    }()
    var currentRecordID: UUID?
    var lastExecutionMode: TranslationMode = .translate
    enum RequestScope {
        case main
        case sub
    }

    var requestGeneration = 0
    var isRequestInFlight = false
    var inFlightScope: RequestScope?
    var lastStreamReflow = Date.distantPast
    var lastStreamedHeightMain: CGFloat = 0
    var lastStreamedHeightSub: CGFloat = 0
    var lastStreamedHeightQA: CGFloat = 0
    var lastStreamedMain = ""
    var lastStreamedSub = ""
    /// Last style passed to `setResultText`. Callers set this explicitly for errors; do not re-infer
    /// from result text prefixes (a real translation can start with "The request…").
    var lastResultStyle: PopoverFeedback.ResultStyle = .normal
    var pendingRelease: ReleaseInfo?
    var didShowSubtranslateHint = false
    let setupOpenSettingsButton = NSButton(title: "Open Settings", target: nil, action: nil)
    let setupGrantAccessButton = NSButton(title: "Grant Accessibility", target: nil, action: nil)
    let inPaneRetryButton = NSButton(title: "Retry", target: nil, action: nil)
    var keyMonitor: Any?
    var globalMouseMonitor: Any?
    var localMouseMonitor: Any?
    var previousApp: NSRunningApplication?
    var restoresPreviousAppOnClose = false
    var activatesAppOnShow = false
    var isPastingResult = false
    var recentTargets: [String] = []
    static let lastTargetLangKey = "local.ninh.ntranslate.lastTargetLang"
    var showMousePoint: NSPoint = .zero
    var userMovedWindow = false
    var isProgrammaticFrameChange = false
    var isPinned = false
    var statusClearWorkItem: DispatchWorkItem?
    var copyFlashWorkItem: DispatchWorkItem?
    /// At most one secondary pane (see `PopoverIntegrationPolicy.usesSubtranslate`).
    var subSection: SubtranslateSection?
    var subGeneration = 0
    var qaSection: QAPaneSection?
    var qaGeneration = 0
    let qaInputField: NSTextField
    let selectionFloatingBar = FloatingBarEffectView(frame: .zero)
    let floatingTranslateButton = PointerButton(frame: .zero)
    let floatingLearnButton = PointerButton(frame: .zero)
    let floatingSpeakButton = PointerButton(frame: .zero)
    let floatingCopyButton = PointerButton(frame: .zero)
    let floatingQuickButton = PointerButton(frame: .zero)
    var currentFloatingSelectedText: String?
    var currentFloatingIsResult: Bool = false
    /// True while the floating selection bar is attached to a subtranslate pane rather than the main one.
    var currentFloatingIsSub: Bool = false
    /// Inline translation shown inside the floating selection bar.
    let floatingResultLabel = NSTextField(labelWithString: "")
    /// Phrase the inline floating result belongs to; a new selection clears the result.
    var floatingResultForText: String?
    /// Bumped on every floating request so stale responses are dropped.
    var floatingRequestGeneration: Int = 0
    /// Whether the Q&A input/answer currently applies to the subtranslate pane instead of the main one.
    var qaTargetsSub: Bool = false
    var refreshTimer: Timer?

    override init() {
        let field = NSTextField(frame: .zero)
        field.cell = VerticallyCenteredTextFieldCell(textCell: "")
        self.qaInputField = field
        super.init()
    }

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
        LiquidGlassChrome.configure(window: panel)
        panel.ignoresMouseEvents = false
        // Dock on this machine owns a full-display window at layer 20. Anything at
        // `.floating` (3) is occluded; `.statusBar` (25) sits above it. Do not mark
        // the panel `.transient` — an accessory app is rarely "active", and transient
        // windows hide on deactivate.
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        buildPopover()
        buildMenu()
        installHotKeyEventHandler()
        do {
            try AppConfig.migrateLegacyAPIKey()
        } catch {
            setResultText("Error: Could not migrate API key to Keychain: \(error.localizedDescription)", style: .error)
        }
        reloadConfig()
        updateReviewBadge()
        performUpdateCheck(silent: true)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.historyStore.refresh()
                // Touching the lazy controller would build a window the user never opened.
                if self.historyWindowController.window?.isVisible == true {
                    self.historyWindowController.reloadHistory()
                }
                self.updateReviewBadge()
            }
        }
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
            if flags == [.command, .shift], event.keyCode == UInt16(kVK_ANSI_P) {
                self.runProofread()
                return nil
            }
            if flags == .command, event.keyCode == UInt16(kVK_ANSI_K) {
                self.askButtonClicked()
                return nil
            }
            if flags == .command, event.keyCode == UInt16(kVK_ANSI_L) {
                self.runLearn()
                return nil
            }
            if flags == .command, event.keyCode == UInt16(kVK_ANSI_P) {
                self.runProofread()
                return nil
            }
            if flags == .command, event.keyCode == UInt16(kVK_ANSI_I) {
                self.runImages()
                return nil
            }
            return event
        }
    }

    func applyTheme() {
        let appearance = config.theme.nsAppearance
        NSApp.appearance = appearance
        panel.appearance = appearance
        settingsWindowController?.window?.appearance = appearance
        historyWindowController.window?.appearance = appearance
        reviewWindowController.window?.appearance = appearance
    }
}