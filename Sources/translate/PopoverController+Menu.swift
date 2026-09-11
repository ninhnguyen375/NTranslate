// Status-bar menu, settings, hotkeys, update checks, and panel show/hide lifecycle.
import AppKit
import ApplicationServices
import Carbon.HIToolbox

extension PopoverController {
    func buildMenu() {
        let appMenu = NSMenu(title: "NTranslate")
        appMenu.addItem(withTitle: "About NTranslate", action: #selector(showAboutPanel), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesClicked), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit NTranslate", action: #selector(quitApp), keyEquivalent: "q")
        appMenu.items.forEach { $0.target = self }
        // Hide walks the responder chain to NSApp, so it must not be retargeted at the controller.
        appMenu.addItem(withTitle: "Hide NTranslate", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

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

        let studyItem = NSMenuItem()
        studyItem.submenu = buildStudyMenu()
        mainMenu.addItem(studyItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(closePanelMenu), keyEquivalent: "w")
        windowMenu.items.forEach { $0.target = self }
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        let helpMenu = NSMenu(title: "Help")
        let shortcutsItem = NSMenuItem(title: "Keyboard Shortcuts", action: #selector(showKeyboardShortcuts), keyEquivalent: "?")
        shortcutsItem.target = self
        helpMenu.addItem(shortcutsItem)
        let helpItem = NSMenuItem()
        helpItem.submenu = helpMenu
        mainMenu.addItem(helpItem)
        NSApp.mainMenu = mainMenu

        let statusMenu = NSMenu()
        let versionItem = NSMenuItem(title: "NTranslate v\(Self.appVersionString())", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        statusMenu.addItem(versionItem)
        statusMenu.addItem(NSMenuItem.separator())

        let openPanelItem = NSMenuItem(title: "Open Translate Panel", action: #selector(openTranslatePanelMenu), keyEquivalent: "t")
        openPanelItem.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Open Translate Panel")
        statusMenu.addItem(openPanelItem)

        let reviewItem = NSMenuItem(title: "Spaced Repetition", action: #selector(openReviewWindow), keyEquivalent: "r")
        reviewItem.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Spaced Repetition")
        reviewItem.tag = Self.reviewMenuItemTag
        statusMenu.addItem(reviewItem)

        let historyItem = NSMenuItem(title: "Translation History", action: #selector(openTranslationHistory), keyEquivalent: "h")
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Translation History")
        statusMenu.addItem(historyItem)

        let statsDisabled = NSMenuItem(title: "Saved: 0 · Mastered: 0 · Streak: 0d", action: nil, keyEquivalent: "")
        statsDisabled.isEnabled = false
        statsDisabled.tag = Self.statsMenuItemTag
        statusMenu.addItem(statsDisabled)
        let statsItem = NSMenuItem(title: "Learning Progress…", action: #selector(showLearningStats), keyEquivalent: "")
        statsItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Learning Progress")
        statsItem.tag = Self.statsActionMenuItemTag
        statusMenu.addItem(statsItem)

        let syncPromptsItem = NSMenuItem(title: "Sync All Prompts with App", action: #selector(syncAllPromptsMenu), keyEquivalent: "")
        syncPromptsItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath.doc.on.clipboard", accessibilityDescription: "Sync All Prompts with App")
        syncPromptsItem.tag = Self.syncPromptsMenuItemTag
        syncPromptsItem.isHidden = true
        statusMenu.addItem(syncPromptsItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesClicked), keyEquivalent: "u")
        updateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Check for Updates")
        statusMenu.addItem(updateItem)

        statusMenu.addItem(NSMenuItem.separator())

        let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access", action: #selector(requestAccessibilityPermissionMenu), keyEquivalent: "")
        accessibilityItem.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: "Grant Accessibility Access")
        accessibilityItem.tag = Self.accessibilityMenuItemTag
        statusMenu.addItem(accessibilityItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",")
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
        statusMenu.addItem(settingsItem)

        statusMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        statusMenu.addItem(quitItem)
        statusMenu.items.forEach { $0.target = self }
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    static let accessibilityMenuItemTag = 9001
    static let reviewMenuItemTag = 9002
    static let statsMenuItemTag = 9003
    static let statsActionMenuItemTag = 9005
    static let syncPromptsMenuItemTag = 9004
    static let attentionDotLayerName = "ntranslate.attentionDot"

    func menuWillOpen(_ menu: NSMenu) {
        if let item = menu.item(withTag: Self.accessibilityMenuItemTag) {
            item.isHidden = AXIsProcessTrusted()
        }
        if let item = menu.item(withTag: Self.syncPromptsMenuItemTag) {
            item.isHidden = !config.hasOutOfSyncPrompts
        }
        updateReviewBadge()
    }

    func updateReviewBadge() {
        let stats = historyStore.computeStats()
        // Cards due can exceed the daily limit; show what this session will actually contain.
        let sessionCount = min(stats.dueCount, max(1, config.learning.dailyReviewLimit))
        let reviewTitle = sessionCount > 0 ? "Spaced Repetition (\(sessionCount) cards)" : "Spaced Repetition"
        reviewButton.toolTip = reviewTitle
        reviewButton.setAccessibilityLabel(reviewTitle)
        reviewBadgeLabel.stringValue = "!"
        reviewBadgeLabel.isHidden = sessionCount == 0
        updateStatusBarIcon(reviewCardsDue: sessionCount)
        if let reviewItem = statusItem.menu?.item(withTag: Self.reviewMenuItemTag) {
            reviewItem.title = reviewTitle
            reviewItem.attributedTitle = sessionCount > 0 ? Self.titleWithAttentionDot(reviewTitle) : nil
        }
        if let statsItem = statusItem.menu?.item(withTag: Self.statsMenuItemTag) {
            statsItem.title = "Saved: \(stats.totalSaved) · Mastered: \(stats.totalMastered) · Streak: \(stats.dayStreak)d"
        }
    }

    /// Menu bar has two states only: idle, or a red dot meaning "something wants you".
    /// Which something is spelled out in the tooltip, where there is room for words.
    func updateStatusBarIcon(reviewCardsDue: Int) {
        guard let button = statusItem.button else { return }
        let attention: String?
        if !AXIsProcessTrusted() {
            attention = "Accessibility permission required"
        } else if apiKey.isEmpty {
            attention = "API key is not configured"
        } else if let loadError = historyStore.loadError {
            attention = "History unavailable: \(loadError)"
        } else if reviewCardsDue > 0 {
            attention = "\(reviewCardsDue) review cards due"
        } else {
            attention = nil
        }
        button.toolTip = attention ?? "NTranslate"
        if let icon = NSImage(systemSymbolName: "translate", accessibilityDescription: "NTranslate") {
            icon.isTemplate = true
            button.image = icon
        } else {
            button.title = "T"
        }
        // Baking the dot into the image would force isTemplate = false and break the
        // menu bar's light/dark tinting, so it rides along as a sibling layer instead.
        attentionDotLayer(on: button).isHidden = attention == nil
    }

    /// Menu items cannot carry a badge view, so the dot is a red bullet glyph in the title.
    private static func titleWithAttentionDot(_ title: String) -> NSAttributedString {
        let font = NSFont.menuFont(ofSize: 0)
        let result = NSMutableAttributedString(string: title + "  ", attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ])
        let dotFont = NSFont.systemFont(ofSize: font.pointSize * 0.62)
        // Centre the dot's ink on the text's cap height rather than guessing an offset:
        // the bullet glyph does not sit centred within its own em box.
        let ink = NSAttributedString(string: "\u{25CF}", attributes: [.font: dotFont])
            .boundingRect(with: .zero, options: .usesDeviceMetrics)
        result.append(NSAttributedString(string: "\u{25CF}", attributes: [
            .font: dotFont,
            .foregroundColor: NSColor.systemRed,
            .baselineOffset: font.capHeight / 2 - ink.midY,
        ]))
        return result
    }

    private func attentionDotLayer(on button: NSStatusBarButton) -> CALayer {
        button.wantsLayer = true
        if let existing = button.layer?.sublayers?.first(where: { $0.name == Self.attentionDotLayerName }) {
            return existing
        }
        let diameter: CGFloat = 5
        let dot = CALayer()
        dot.name = Self.attentionDotLayerName
        dot.backgroundColor = NSColor.systemRed.cgColor
        dot.cornerRadius = diameter / 2
        // The status button's backing layer is flipped, so smaller y sits higher.
        dot.frame = NSRect(
            x: button.bounds.midX + 5,
            y: button.bounds.midY - 8,
            width: diameter,
            height: diameter
        )
        dot.autoresizingMask = [.layerMinXMargin, .layerMaxYMargin]
        button.layer?.addSublayer(dot)
        return dot
    }

    @objc func syncAllPromptsMenu() {
        var updated = config
        updated.syncAllPromptsWithDefaults()
        do {
            try saveSettings(config: updated, apiKey: apiKey, speechAPIKey: speechAPIKey)
            setStatus("Synced all prompts with app defaults", autoClearAfter: 6)
        } catch {
            setStatus("Sync prompts failed: \(error.localizedDescription)", autoClearAfter: 10)
        }
    }

    @objc func openReviewWindow() {
        reviewWindowController.translator = translator
        reviewWindowController.config = config
        reviewWindowController.onLearningSettingsChanged = { [weak self] learning in
            self?.applyLearningSettings(learning)
        }
        reviewWindowController.onWindowClosed = { [weak self] in
            self?.demoteAfterStudyWindow()
        }
        reviewWindowController.showReview()
        promoteForStudyWindow()
    }

    /// The Study window is the only screen that changes these, and it changes them one click at a
    /// time, so the whole config is written back the same way Settings does it.
    func applyLearningSettings(_ learning: AppConfig.LearningSettings) {
        guard config.learning != learning else { return }
        config.learning = learning
        do {
            try saveSettings(config: config, apiKey: apiKey, speechAPIKey: speechAPIKey)
        } catch {
            NSLog("[NTranslate] Failed to save learning settings: \(error.localizedDescription)")
        }
    }

    @objc func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: Self.appVersionString()
        ])
    }

    @objc func showLearningStats() {
        let stats = historyStore.computeStats()
        let alert = NSAlert()
        alert.messageText = "Learning Progress"
        alert.informativeText = "• Saved words: \(stats.totalSaved)\n• Mastered (interval >= 21 days): \(stats.totalMastered)\n• Daily streak: \(stats.dayStreak) days\n• Cards due today: \(stats.dueCount) cards (session limit: \(config.learning.dailyReviewLimit))"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func requestAccessibilityPermissionMenu() {
        requestAccessibilityPermissionIfNeeded(forcePrompt: true)
    }

    @objc func openTranslatePanelMenu() {
        let outcome = reloadConfig(showSuccess: false)
        openTranslatePanelShowingSetupStatus(loadMessage: outcome.message)
    }

    @objc func openSettingsMenu() {
        let outcome = AppConfig.loadOutcome()
        let key: String
        let speechKey: String
        do {
            key = try APIKeyStore.shared.load() ?? ""
            speechKey = try APIKeyStore.speech.load() ?? ""
        } catch {
            setResultText("Error: \(error.localizedDescription)", style: .error)
            openTranslatePanelShowingSetupStatus(loadMessage: error.localizedDescription)
            return
        }

        if let controller = settingsWindowController {
            controller.showSettings(config: outcome.config, apiKey: key, speechAPIKey: speechKey)
            return
        }

        let controller = SettingsWindowController(
            config: outcome.config, apiKey: key, speechAPIKey: speechKey
        ) { [weak self] config, key, speechKey in
            try self?.saveSettings(config: config, apiKey: key, speechAPIKey: speechKey)
        }
        settingsWindowController = controller
        controller.showSettings(config: outcome.config, apiKey: key, speechAPIKey: speechKey)
    }

    func saveSettings(config: AppConfig, apiKey newAPIKey: String, speechAPIKey newSpeechKey: String) throws {
        let previousKey = try APIKeyStore.shared.load()
        // A changed speech provider, endpoint, credential, or voice makes every cached clip
        // stale. The key counts: pointing it at a different vendor changes the voice too.
        let speechChanged = config.speechProvider != self.config.speechProvider
            || config.apiSpeechURL != self.config.apiSpeechURL
            || config.speechModels != self.config.speechModels
            || config.speechFallbackModel != self.config.speechFallbackModel
            || newSpeechKey != speechAPIKey
        try APIKeyStore.shared.save(newAPIKey)
        try APIKeyStore.speech.save(newSpeechKey)
        do {
            try AppConfig.write(config)
        } catch {
            let configError = error
            do {
                if let previousKey {
                    try APIKeyStore.shared.save(previousKey)
                } else {
                    try APIKeyStore.shared.delete()
                }
            } catch {
                throw NSError(
                    domain: "NTranslate.Settings",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Could not save config (\(configError.localizedDescription)) or restore the previous API key (\(error.localizedDescription))."]
                )
            }
            throw configError
        }
        if speechChanged { clearAudioCache(recordID: currentRecordID) }
        _ = reloadConfig(showSuccess: true)
    }

    @objc func openTranslationHistory() {
        historyWindowController.showHistory()
    }

    /// Opens the translate panel and shows config/permission errors immediately when present.
    func openTranslatePanelShowingSetupStatus(loadMessage: String? = nil) {
        let pointer: NSPoint
        if let button = statusItem.button, let buttonWindow = button.window {
            let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            pointer = NSPoint(x: buttonFrameOnScreen.midX, y: buttonFrameOnScreen.minY)
        } else {
            pointer = NSEvent.mouseLocation
        }
        if !panel.isVisible {
            showMousePoint = pointer
        } else if !isPinned {
            movePanelToPointer(pointer)
        }

        let issues = config.setupIssues(
            apiKey: apiKey,
            loadMessage: loadMessage,
            accessibilityTrusted: AXIsProcessTrusted()
        )

        if issues.isEmpty {
            let current = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            if current.isEmpty
                || lastResultStyle != .normal
                || current.hasPrefix("Error:")
                || current.hasPrefix("Config load error:")
                || current.hasPrefix("Created ")
            {
                setResultText(PopoverFeedback.emptySelectionGuidance(hotkey: config.hotkey.displayString), style: .loading)
            }
            showSetupActions(kinds: [])
            clearStatus()
        } else {
            setResultText(AppConfig.formatSetupIssues(issues), style: .error)
            let kinds = Set(issues.compactMap(\.action))
            showSetupActions(kinds: kinds)
            setStatus("Fix the issues above, then try again.")
        }

        reflowLayout()
        updateBusyState()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
    }

    static func appVersionString() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    @objc func manualToggle() {
        guard NSApp.currentEvent?.type == .leftMouseUp else { return }
        if panel.isVisible {
            restoresPreviousAppOnClose = true
            closePanel()
            return
        }
        if let button = statusItem.button, let buttonWindow = button.window {
            let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            showMousePoint = NSPoint(x: buttonFrameOnScreen.midX, y: buttonFrameOnScreen.minY)
        } else {
            showMousePoint = NSEvent.mouseLocation
        }
        reflowLayout()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if let hotKeyEventHandlerRef { RemoveEventHandler(hotKeyEventHandlerRef) }
        registeredHotKeys.forEach { UnregisterEventHotKey($0) }
        registeredHotKeys.removeAll()
        CrashRecovery.markCleanShutdown()
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }

    @objc func reloadConfig() {
        _ = reloadConfig(showSuccess: false)
    }

    @discardableResult
    func reloadConfig(showSuccess: Bool) -> AppConfig.LoadOutcome {
        let outcome = AppConfig.loadOutcome()
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        config = outcome.config
        applyTheme()
        registerHotKey()
        do {
            apiKey = try APIKeyStore.shared.load() ?? ""
            speechAPIKey = try APIKeyStore.speech.load() ?? ""
        } catch {
            apiKey = ""
            speechAPIKey = ""
            translator = nil
            setResultText("Error: \(error.localizedDescription)", style: .error)
            return outcome
        }
        historyStore = TranslationHistoryStore(config: config)
        WeaveCache.prepare(historyDirectory: config.historyDirectoryURL)
        historyWindowController = HistoryWindowController(store: historyStore) { [weak self] record in
            guard let self else { return }
            self.openTranslatePanelShowingSetupStatus()
            self.openHistoryRecord(record)
        }
        if let loadError = historyStore.loadError {
            setStatus(loadError, autoClearAfter: 12)
        } else if let syncWarning = historyStore.syncWarning {
            setStatus(syncWarning, autoClearAfter: 12)
        }
        reflowLayout()
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAPIKey.isEmpty {
            translator = nil
        } else {
            translator = Translator(config: config, apiKey: trimmedAPIKey, speechAPIKey: speechAPIKey)
        }
        reviewWindowController.updateDependencies(store: historyStore, translator: translator, config: config)
        guard !trimmedAPIKey.isEmpty else {
            setResultText("Error: API key is empty — open Settings… and enter your 9router API key.", style: .error)
            return outcome
        }
        configureLanguageControls()
        updateShortcutLabels()
        assert(URL(string: config.apiBaseURL) != nil)
        assert(URL(string: config.apiSpeechURL) != nil)
        if let message = outcome.message {
            setResultText("Error: \(message)", style: .error)
        } else if outcome.didSeedConfig {
            setResultText("Created config at \(AppConfig.configPath)")
        } else if showSuccess {
            setResultText("Reloaded config from \(AppConfig.configPath)")
        }
        return outcome
    }

    func requestAccessibilityPermissionIfNeeded(forcePrompt: Bool = false) {
        let alreadyTrusted = AXIsProcessTrusted()
        NSLog("[NTranslate] Accessibility trusted=\(alreadyTrusted) forcePrompt=\(forcePrompt) bundle=\(Bundle.main.bundleIdentifier ?? "nil") path=\(Bundle.main.bundleURL.path)")
        guard !alreadyTrusted || forcePrompt else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            setResultText(PopoverFeedback.accessibilityRequired)
        }
    }

    func restorePreviousAppFocus() {
        guard restoresPreviousAppOnClose else { return }
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }

    func installOutsideClickMonitor() {
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

    func removeOutsideClickMonitor() {
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
    func presentPanel(activatesApp: Bool, restoresPreviousAppOnCloseValue: Bool) {
        let wasVisible = panel.isVisible
        if !wasVisible {
            userMovedWindow = false
            isPinned = config.ui.rememberPin
            updatePinButton()
            updateReviewBadge()
        }
        restoresPreviousAppOnClose = restoresPreviousAppOnCloseValue
        activatesAppOnShow = activatesApp
        panel.makeKeyAndOrderFront(nil)
        if activatesApp {
            NSApp.activate(ignoringOtherApps: true)
        }
        if !wasVisible {
            installOutsideClickMonitor()
            DispatchQueue.main.async { [weak self] in
                self?.reflowLayout()
            }
        }
        focusInputTextView()
    }

    @objc func closePanelMenu() {
        closePopover()
    }

    func closePanel() {
        guard panel.isVisible else { return }
        hideFloatingSelectionBar()
        mainRequest?.cancel()
        subRequest?.cancel()
        qaRequest?.cancel()
        mainRequest = nil
        subRequest = nil
        qaRequest = nil
        requestGeneration += 1
        isRequestInFlight = false
        subGeneration += 1
        qaGeneration += 1
        subSection?.requestInFlight = false
        removeSubSection()
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

    @objc func togglePin() {
        isPinned.toggle()
        updatePinButton()
        persistRememberPin()
    }

    func persistRememberPin() {
        guard config.ui.rememberPin != isPinned else { return }
        var next = config
        next.ui.rememberPin = isPinned
        config = next
        try? AppConfig.write(next)
    }

    @objc func checkForUpdatesClicked() {
        if let pendingRelease {
            showUpdateAlert(release: pendingRelease)
            return
        }
        performUpdateCheck(silent: false)
    }

    func performUpdateCheck(silent: Bool) {
        if silent {
            guard UpdateManager.shouldRunAutomaticCheck() else { return }
            UpdateManager.recordAutomaticCheck()
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                if let release = try await UpdateManager.shared.checkForUpdate() {
                    await MainActor.run {
                        self.pendingRelease = release
                        self.updateButton.isHidden = false
                        self.reflowLayout()
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

    func showUpdateAlert(release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "Update Available: \(release.tag)"
        alert.informativeText = "A new version of NTranslate is available."
        alert.alertStyle = .informational
        alert.accessoryView = PopoverController.releaseNotesView(release.notes)
        alert.addButton(withTitle: "Update & Restart")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            setStatus("Downloading update \(release.tag)...", autoClearAfter: 600)
            Task { [weak self] in
                guard let self else { return }
                do {
                    let dmgURL = try await UpdateManager.shared.downloadDMG(from: release.dmgURL)
                    await MainActor.run { self.setStatus("Installing update...", autoClearAfter: 600) }
                    try UpdateManager.shared.installUpdateAndRestart(dmgURL: dmgURL)
                } catch {
                    await MainActor.run {
                        self.clearStatus()
                        self.showUpdateErrorAlert(error)
                    }
                }
            }
        }
    }

    /// Release notes in a fixed-height scroller, rendered as markdown.
    /// ponytail: inline-markdown only (same parser as the result pane); headings/lists stay literal.
    static func releaseNotesView(_ notes: String) -> NSView {
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 380, height: 240))
        textView.isEditable = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(
            .markdownDisplay(text.isEmpty ? "No release notes." : text,
                             font: .systemFont(ofSize: 12),
                             color: .labelColor)
        )

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 380, height: 240))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        scroll.documentView = textView
        return scroll
    }

    func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date!"
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        alert.informativeText = "NTranslate \(currentVersion) is currently the newest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func showUpdateErrorAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Update Check Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func updatePinButton() {
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
            pinButton.contentTintColor = Palette.chromeIconTint
        }
    }

    func focusInputTextView() {
        attemptFocusInputTextView(remainingRetries: 10)
    }

    private func attemptFocusInputTextView(remainingRetries: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeKey()
            // `presentPanel` runs twice per hotkey (once to show the panel, again once the selection
            // read returns), so this can land in the middle of a click. NSTextView tracks the mouse
            // in its own event loop — taking first responder away mid-track drops the double-click's
            // word selection and parks the caret at offset 0.
            if NSEvent.pressedMouseButtons != 0 {
                guard remainingRetries > 0 else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                    self?.attemptFocusInputTextView(remainingRetries: remainingRetries - 1)
                }
                return
            }
            if let focused = self.panel.firstResponder as? NSTextView,
               focused === self.inputTextView || focused.selectedRange().length > 0 {
                return
            }
            self.panel.makeFirstResponder(self.inputTextView)
        }
    }

    func updateLanguageSelection(for text: String) {
        let pair = resolvedLanguagePair(for: text)
        selectLanguage(pair.source, kind: .source)
        selectLanguage(pair.target, kind: .target)
        updatePaneLanguageLabels()
    }

    func showSetupActions(kinds: Set<SetupIssue.Action>) {
        setupOpenSettingsButton.isHidden = !kinds.contains(.openSettings)
        setupGrantAccessButton.isHidden = !kinds.contains(.grantAccessibility)
        if !kinds.isEmpty {
            inPaneRetryButton.isHidden = true
        }
    }

    func maybeHintSubtranslate() {
        guard !didShowSubtranslateHint else { return }
        guard PopoverIntegrationPolicy.usesSubtranslate(
            panelVisible: panel.isVisible,
            primaryResult: textView.string,
            hasPendingImage: pendingImage != nil
        ) else { return }
        didShowSubtranslateHint = true
        setStatus("Select a word or phrase in the source to open a sub-translation.", autoClearAfter: 6)
    }

    func showEmptySelectionPanel(message: String? = nil) {
        let text = message ?? PopoverFeedback.emptySelectionGuidance(hotkey: config.hotkey.displayString)
        if !isPinned {
            showMousePoint = NSEvent.mouseLocation
            if panel.isVisible { movePanelToPointer(showMousePoint) }
        }
        invalidateTranslationRequest()
        invalidateSpeech(stopPlayback: true)
        setPendingImage(nil)
        inputTextView.string = ""
        let style = PopoverFeedback.resultStyle(for: text)
        setResultText(text, style: style == .normal ? .loading : style)
        if text == PopoverFeedback.accessibilityRequired {
            showSetupActions(kinds: [.grantAccessibility])
        }
        clearStatus()
        reflowLayout()
        updateBusyState()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
    }

    func setPendingImage(_ data: Data?) {
        pendingImage = data
        imagePlaceholderLabel.isHidden = data == nil
        updateBusyState()
    }
}