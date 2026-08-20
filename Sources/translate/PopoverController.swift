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
        static let headerHeight: CGFloat = 22
        static let statusHeight: CGFloat = 14
        /// Gap between title/header and the split body.
        static let headerGap: CGFloat = 12
        /// Gap between split body and bottom controls.
        static let footerGap: CGFloat = 16
        static let paneHeaderHeight: CGFloat = 30
        static let paneHeaderTopInset: CGFloat = 4
        static let splitMinPaneHeight: CGFloat = 160
        static let splitMinStackedPaneHeight: CGFloat = 120
        /// Vertical gap between the main pane and the subtranslate pane.
        static let sectionGap: CGFloat = 10
        static let splitMaxPaneHeight: CGFloat = 420
        /// Per-section cap once a subtranslate pane exists — two panes at `splitMaxPaneHeight` each
        /// overflow the panel.
        static let splitMaxStackedPaneHeight: CGFloat = 300
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

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let panel = LiquidGlassWindow(
        contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    let textView = NSTextView(frame: .zero)
    let textScrollView = NSScrollView(frame: .zero)
    let inputTextView = InputTextView(frame: .zero)
    let inputScrollView = NSScrollView(frame: .zero)
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
    let updateButton = NSButton(frame: .zero)
    /// Hover-only indicator listing the recent translations sent as context with the next Translate.
    let contextButton = NSButton(frame: .zero)
    let pinButton = NSButton(frame: .zero)
    let closeButton = NSButton(frame: .zero)
    let translateButton = NSButton(frame: .zero)
    let learnButton = NSButton(frame: .zero)
    let imagesButton = NSButton(frame: .zero)
    let proofreadButton = NSButton(frame: .zero)
    let copyButton = NSButton(frame: .zero)
    let saveWordButton = NSButton(frame: .zero)
    let titleLabel = NSTextField(labelWithString: "Translate")
    let statusLabel = NSTextField(labelWithString: "")
    let speakSourceButton = NSButton(frame: .zero)
    let speakResultButton = NSButton(frame: .zero)
    var splitDividerGradient: CAGradientLayer?
    var translator: Translator?
    var registeredHotKeys: [EventHotKeyRef] = []
    var hotKeyEventHandlerRef: EventHandlerRef?
    var config = AppConfig.load()
    var apiKey = ""
    var settingsWindowController: SettingsWindowController?
    var audioPlayer: AVAudioPlayer?
    var speechState = SpeechPlaybackState()
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
    var currentRecordID: UUID?
    var requestGeneration = 0
    var isRequestInFlight = false
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

    var speechRate: Float {
        get { SpeechRatePolicy.resolved(UserDefaults.standard.float(forKey: SpeechRatePolicy.defaultsKey)) }
        set { UserDefaults.standard.set(newValue, forKey: SpeechRatePolicy.defaultsKey) }
    }
    let speechRatePopUp = NSPopUpButton()

    override init() {
        super.init()
        speechRatePopUp.isBordered = false
        speechRatePopUp.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        speechRatePopUp.setAccessibilityLabel("Speech rate")
        for rate in SpeechRatePolicy.options {
            let item = NSMenuItem(title: String(format: "%.1fx", rate), action: #selector(speechRateChanged(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = rate
            speechRatePopUp.menu?.addItem(item)
        }
        speechRatePopUp.selectItem(withTitle: String(format: "%.1fx", speechRate))
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
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        buildPopover()
        buildMenu()
        installHotKeyEventHandler()
        do {
            try AppConfig.migrateLegacyAPIKey()
        } catch {
            setResultText("Error: Could not migrate API key to Keychain: \(error.localizedDescription)")
        }
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
            if flags == [.command, .shift], event.keyCode == UInt16(kVK_ANSI_P) {
                self.runProofread()
                return nil
            }
            return event
        }
    }


}