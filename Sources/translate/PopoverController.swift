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
    /// Panel density. Compact trims chrome so more translated text fits at the same panel height.
    enum ChromeDensity: String {
        case normal
        case compact

        /// Compact drops the Source/Result strip — the header already names both languages.
        var hidesPaneHeader: Bool { self == .compact }
        /// Compact puts the Q&A field on the action row instead of a row of its own.
        var mergesQAIntoActionRow: Bool { self == .compact }
    }

    /// Split Prism chrome — dual-pane + bottom bar inside Liquid Glass shell.
    @MainActor
    enum ChromeLayout {
        /// Set from `AppConfig.ui.density`; every measurement below reads it.
        static var density: ChromeDensity = .normal

        static var padding: CGFloat { density == .compact ? 10 : 14 }
        /// Bottom inset for footer controls — a bit more air from the popup edge.
        static var paddingBottom: CGFloat { density == .compact ? 10 : 16 }
        /// Same height as the action chips so header and footer share one padding rhythm.
        static var headerHeight: CGFloat { density == .compact ? 28 : 32 }
        static let statusHeight: CGFloat = 14
        /// Gap between title/header and the split body.
        static var headerGap: CGFloat { density == .compact ? 8 : 12 }
        /// Gap between split body and bottom controls.
        static var footerGap: CGFloat { density == .compact ? 10 : 16 }
        /// Zero in compact — the pane icons float over the body instead of sitting in a strip.
        static var paneHeaderHeight: CGFloat { density.hidesPaneHeader ? 0 : 30 }
        static var paneHeaderTopInset: CGFloat { density == .compact ? 2 : 4 }
        /// Vertical breathing room added around measured body text.
        static var textInset: CGFloat { density == .compact ? 12 : 20 }
        /// Horizontal inset the body text loses to pane padding.
        static var textSideInset: CGFloat { density == .compact ? 20 : 24 }
        static let splitMinPaneHeight: CGFloat = 160
        static let splitMinStackedPaneHeight: CGFloat = 120
        /// Vertical gap between stacked panes that do not use a labeled divider (e.g. Q&A).
        static var sectionGap: CGFloat { density == .compact ? 6 : 10 }
        /// Labeled hairline between the main action row and the subtranslate pane.
        static var sectionDividerHeight: CGFloat { density == .compact ? 16 : 20 }
        /// Empty space above the hairline so it does not sit flush on the main action row.
        static var sectionDividerTopMargin: CGFloat { density == .compact ? 8 : 14 }
        static var sectionDividerReserved: CGFloat { sectionDividerTopMargin + sectionDividerHeight }
        static let splitMaxPaneHeight: CGFloat = 720
        /// Per-section cap once a subtranslate pane exists — two panes at `splitMaxPaneHeight` each
        /// overflow the panel.
        static let splitMaxStackedPaneHeight: CGFloat = 520
        static let dividerWidth: CGFloat = 1
        /// Shared height for Learn / Translate.
        static var controlHeight: CGFloat { density == .compact ? 28 : 32 }
        static var qaInputHeight: CGFloat { density == .compact ? 26 : 28 }
        static var bottomBarHeight: CGFloat { controlHeight }
        /// Same height as chrome icon pills so the header row shares one padding rhythm.
        static var languageControlHeight: CGFloat { headerHeight }
        static let languageWidth: CGFloat = 76
        /// Language chips use a pill of `height / 2` after layout — never a CSS-style 999.
        static var swapWidth: CGFloat { languageControlHeight }
        static let iconButtonSize: CGFloat = 18
        /// Circular glass chip — larger than the glyph so the pill has padding.
        static var chromeIconSize: CGFloat { headerHeight }
        static let glassCornerRadius: CGFloat = 22
        static let splitCornerRadius: CGFloat = 16
        /// Source / translation body text.
        static var bodyFontSize: CGFloat { TextZoom.size(TextZoom.baseBodySize) }
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
    let learnBadgeView = LearnBadgeView()
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
    let copyButton = PointerButton(frame: .zero)
    let saveWordButton = PointerButton(frame: .zero)
    let titleLabel = NSTextField(labelWithString: "Translate")
    let statusLabel = NSTextField(labelWithString: "")
    let speakSourceButton = PointerButton(frame: .zero)
    let speakSourceSlowButton = PointerButton(frame: .zero)
    let speakResultButton = PointerButton(frame: .zero)
    let speakResultSlowButton = PointerButton(frame: .zero)
    let retryButton = PointerButton(frame: .zero)
    var splitDividerGradient: CAGradientLayer?
    var translator: Translator?
    var registeredHotKeys: [EventHotKeyRef] = []
    var hotKeyEventHandlerRef: EventHandlerRef?
    var ocrPollTimer: Timer?
    var config = AppConfig.default {
        didSet { applyDensity() }
    }
    var apiKey = ""
    /// Empty means the speech endpoint reuses `apiKey`.
    var speechAPIKey = ""
    var settingsWindowController: SettingsWindowController?
    var audioPlayer: AVAudioPlayer?
    var speechState = SpeechPlaybackState()
    var activeSpeechRate: Float = 1.0
    var speechCache: [SpeechIdentity: Data] = [:]
    var speechTrim: [SpeechIdentity: SpeechTrim.Bounds] = [:]
    var prefetchGeneration = 0
    var prefetchingSpeech: Set<SpeechIdentity> = []
    var pendingSourceSpeech: [Int: PendingSourceSpeech] = [:]
    var pendingImage: Data?
    var historyStore: TranslationHistoryStore!
    var _historyWindowController: HistoryWindowController?
    var historyWindowController: HistoryWindowController {
        if let existing = _historyWindowController { return existing }
        let controller = makeHistoryWindowController()
        controller.window?.appearance = config.theme.nsAppearance
        _historyWindowController = controller
        return controller
    }
    var _reviewWindowController: ReviewWindowController?
    var reviewWindowController: ReviewWindowController {
        if let existing = _reviewWindowController { return existing }
        let controller = ReviewWindowController(store: historyStore, translator: translator, config: config)
        controller.onReviewsCompleted = { [weak self] in
            self?.updateReviewBadge()
        }
        controller.onOpenTranslate = { [weak self] record in
            guard let self else { return }
            self.openTranslatePanelShowingSetupStatus()
            self.openHistoryRecord(record)
        }
        controller.onLearnSentence = { [weak self] sentence in
            guard let self else { return }
            self.openTranslatePanelShowingSetupStatus()
            self.learn(sentence)
        }
        controller.onTranslateSentence = { [weak self] sentence in
            guard let self else { return }
            self.openTranslatePanelShowingSetupStatus()
            self.translate(sentence)
        }
        controller.window?.appearance = config.theme.nsAppearance
        _reviewWindowController = controller
        return controller
    }
    var currentRecordID: UUID?
    var lastExecutionMode: TranslationMode = .translate
    enum RequestScope {
        case main
        case sub
    }

    var requestGeneration = 0
    var isRequestInFlight = false
    // One handle per pane: the three run concurrently and each cancels only its own request.
    var mainRequest: RequestHandle?
    var subRequest: RequestHandle?
    var qaRequest: RequestHandle?
    /// Set once an image request has streamed its transcription into the input pane; the pane is no
    /// longer in image mode, but the in-flight image response still belongs to it.
    var imageStreamAdoptedSource = false
    var lastStreamReflowMain = Date.distantPast
    var lastStreamReflowSub = Date.distantPast
    var lastStreamReflowQA = Date.distantPast
    var lastStreamedHeightMain: CGFloat = 0
    var lastStreamedHeightSub: CGFloat = 0
    var lastStreamedHeightQA: CGFloat = 0
    var lastStreamedMain = ""
    var lastStreamedSub = ""
    /// Last style passed to `setResultText`. Callers set this explicitly for errors; do not re-infer
    /// from result text prefixes (a real translation can start with "The request…").
    var lastResultStyle: PopoverFeedback.ResultStyle = .normal
    /// Kết quả gốc chưa bị gỡ dòng "Mức dùng:", để lưu history vẫn còn badge.
    var lastResultRaw = ""
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

    /// Pushes the stored density into `ChromeLayout` — the only writer of that value.
    func applyDensity() {
        ChromeLayout.density = ChromeDensity(rawValue: config.ui.density) ?? .normal
    }

    func makeHistoryWindowController() -> HistoryWindowController {
        HistoryWindowController(store: historyStore) { [weak self] record in
            guard let self else { return }
            self.openTranslatePanelShowingSetupStatus()
            self.openHistoryRecord(record)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try AppConfig.migrateLegacyAPIKey()
        } catch {
            setResultText("Error: Could not migrate API key to Keychain: \(error.localizedDescription)", style: .error)
        }
        installHotKeyEventHandler()
        reloadConfig()
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
        updateReviewBadge()
        performUpdateCheck(silent: true)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self?.historyStore.prunePendingIfNeeded()
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.historyStore.refresh()
                if self._historyWindowController?.window?.isVisible == true {
                    self._historyWindowController?.reloadHistory()
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
            if let delta = TextZoom.delta(for: event) {
                self.applyTextZoom(delta)
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
        _historyWindowController?.window?.appearance = appearance
        _reviewWindowController?.window?.appearance = appearance
    }
}
