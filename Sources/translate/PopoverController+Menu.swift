// Status-bar menu, settings, hotkeys, update checks, and panel show/hide lifecycle.
import AppKit
import ApplicationServices
import Carbon.HIToolbox

extension PopoverController {
    func buildMenu() {
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

        let openPanelItem = NSMenuItem(title: "Open Translate Panel", action: #selector(openTranslatePanelMenu), keyEquivalent: "t")
        openPanelItem.image = NSImage(systemSymbolName: "translate", accessibilityDescription: "Open Translate Panel")
        statusMenu.addItem(openPanelItem)

        let reviewItem = NSMenuItem(title: "Review SRS", action: #selector(openReviewWindow), keyEquivalent: "r")
        reviewItem.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "Review SRS")
        reviewItem.tag = Self.reviewMenuItemTag
        statusMenu.addItem(reviewItem)

        let historyItem = NSMenuItem(title: "Translation History", action: #selector(openTranslationHistory), keyEquivalent: "h")
        historyItem.image = NSImage(systemSymbolName: "clock.arrow.circlepath", accessibilityDescription: "Translation History")
        statusMenu.addItem(historyItem)

        let statsItem = NSMenuItem(title: "Learning Progress...", action: #selector(showLearningStats), keyEquivalent: "")
        statsItem.image = NSImage(systemSymbolName: "chart.line.uptrend.xyaxis", accessibilityDescription: "Learning Progress")
        statsItem.tag = Self.statsMenuItemTag
        statusMenu.addItem(statsItem)

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

    func menuWillOpen(_ menu: NSMenu) {
        if let item = menu.item(withTag: Self.accessibilityMenuItemTag) {
            item.isHidden = AXIsProcessTrusted()
        }
        updateReviewBadge()
    }

    func updateReviewBadge() {
        let stats = historyStore.computeStats()
        let reviewTitle = stats.dueCount > 0 ? "Review SRS (\(stats.dueCount) cards)" : "Review SRS"
        reviewButton.toolTip = reviewTitle
        reviewButton.setAccessibilityLabel(reviewTitle)
        if stats.dueCount > 0 {
            reviewBadgeLabel.stringValue = stats.dueCount > 99 ? "99+" : "\(stats.dueCount)"
            reviewBadgeLabel.isHidden = false
        } else {
            reviewBadgeLabel.isHidden = true
        }
        if let reviewItem = statusItem.menu?.item(withTag: Self.reviewMenuItemTag) {
            reviewItem.title = reviewTitle
        }
        if let statsItem = statusItem.menu?.item(withTag: Self.statsMenuItemTag) {
            statsItem.title = "Saved: \(stats.totalSaved) · Mastered: \(stats.totalMastered) · Streak: \(stats.dayStreak)d"
        }
    }

    @objc func openReviewWindow() {
        reviewWindowController.translator = translator
        reviewWindowController.config = config
        reviewWindowController.showReview()
    }

    @objc func showLearningStats() {
        let stats = historyStore.computeStats()
        let alert = NSAlert()
        alert.messageText = "Learning Progress"
        alert.informativeText = "• Saved words: \(stats.totalSaved)\n• Mastered (interval >= 21 days): \(stats.totalMastered)\n• Daily streak: \(stats.dayStreak) days\n• Cards due today: \(stats.dueCount) cards"
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
        do {
            key = try APIKeyStore.shared.load() ?? ""
        } catch {
            setResultText("Error: \(error.localizedDescription)")
            openTranslatePanelShowingSetupStatus(loadMessage: error.localizedDescription)
            return
        }

        if let controller = settingsWindowController {
            controller.showSettings(config: outcome.config, apiKey: key)
            return
        }

        let controller = SettingsWindowController(config: outcome.config, apiKey: key) { [weak self] config, key in
            try self?.saveSettings(config: config, apiKey: key)
        }
        settingsWindowController = controller
        controller.showSettings(config: outcome.config, apiKey: key)
    }

    func saveSettings(config: AppConfig, apiKey newAPIKey: String) throws {
        let previousKey = try APIKeyStore.shared.load()
        try APIKeyStore.shared.save(newAPIKey)
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
        _ = reloadConfig(showSuccess: true)
    }

    @objc func openTranslationHistory() {
        historyWindowController.showHistory()
    }

    /// Opens the translate panel and shows config/permission errors immediately when present.
    func openTranslatePanelShowingSetupStatus(loadMessage: String? = nil) {
        if !panel.isVisible {
            if let button = statusItem.button, let buttonWindow = button.window {
                let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
                showMousePoint = NSPoint(x: buttonFrameOnScreen.midX, y: buttonFrameOnScreen.minY)
            } else {
                showMousePoint = NSEvent.mouseLocation
            }
        }

        let issues = config.setupIssues(
            apiKey: apiKey,
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
            setStatus("Fix the errors above, then open Settings…")
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
        } else if let button = statusItem.button, let buttonWindow = button.window {
            let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
            showMousePoint = NSPoint(x: buttonFrameOnScreen.midX, y: buttonFrameOnScreen.minY)
            reflowLayout()
            presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        }
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
        registerHotKey()
        do {
            apiKey = try APIKeyStore.shared.load() ?? ""
        } catch {
            apiKey = ""
            translator = nil
            setResultText("Error: \(error.localizedDescription)")
            return outcome
        }
        historyStore = TranslationHistoryStore(config: config)
        historyWindowController = HistoryWindowController(store: historyStore) { [weak self] record in
            guard let self else { return }
            self.historyWindowController.close()
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
            translator = Translator(config: config, apiKey: trimmedAPIKey)
        }
        reviewWindowController.updateDependencies(store: historyStore, translator: translator, config: config)
        guard !trimmedAPIKey.isEmpty else {
            setResultText("Error: API key is empty — open Settings… and enter your 9router API key.")
            return outcome
        }
        configureLanguageControls()
        updateShortcutLabels()
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
            isPinned = false
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
        }
        focusInputTextView()
    }

    func closePanel() {
        guard panel.isVisible else { return }
        hideFloatingSelectionBar()
        removeSubSection()
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

    @objc func togglePin() {
        isPinned.toggle()
        updatePinButton()
    }

    @objc func checkForUpdatesClicked() {
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
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.panel.makeKey()
            self.panel.makeFirstResponder(self.inputTextView)
        }
    }

    func updateLanguageSelection(for text: String) {
        let pair = resolvedLanguagePair(for: text)
        selectLanguage(pair.source, kind: .source)
        selectLanguage(pair.target, kind: .target)
        updatePaneLanguageLabels()
    }

    func showEmptySelectionPanel(message: String = PopoverFeedback.emptySelectionGuidance) {
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

    func setPendingImage(_ data: Data?) {
        pendingImage = data
        imagePlaceholderLabel.isHidden = data == nil
        updateBusyState()
    }
}