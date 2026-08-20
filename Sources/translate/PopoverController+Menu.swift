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
        statusMenu.addItem(withTitle: "Open Translate Panel", action: #selector(openTranslatePanelMenu), keyEquivalent: "t")
        statusMenu.addItem(withTitle: "Translation History", action: #selector(openTranslationHistory), keyEquivalent: "h")
        statusMenu.addItem(withTitle: "Check for Updates...", action: #selector(checkForUpdatesClicked), keyEquivalent: "u")
        statusMenu.addItem(NSMenuItem.separator())
        let accessibilityItem = NSMenuItem(title: "Grant Accessibility Access", action: #selector(requestAccessibilityPermissionMenu), keyEquivalent: "")
        accessibilityItem.tag = Self.accessibilityMenuItemTag
        statusMenu.addItem(accessibilityItem)
        statusMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",")
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        statusMenu.items.forEach { $0.target = self }
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    static let accessibilityMenuItemTag = 9001

    func menuWillOpen(_ menu: NSMenu) {
        if let item = menu.item(withTag: Self.accessibilityMenuItemTag) {
            item.isHidden = AXIsProcessTrusted()
        }
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

    static func hotKeyModifiers(_ hotkey: AppConfig.Hotkey) -> UInt32 {
        var flags: UInt32 = 0
        if hotkey.option { flags |= UInt32(optionKey) }
        if hotkey.command { flags |= UInt32(cmdKey) }
        if hotkey.control { flags |= UInt32(controlKey) }
        if hotkey.shift { flags |= UInt32(shiftKey) }
        return flags
    }

    func installHotKeyEventHandler() {
        guard hotKeyEventHandlerRef == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let controller = Unmanaged<PopoverController>.fromOpaque(userData).takeUnretainedValue()
            switch PopoverIntegrationPolicy.hotkeyIntent(id: hotKeyID.id) {
            case .translate:
                controller.perform(#selector(PopoverController.hotKeyPressed), on: .main, with: nil, waitUntilDone: false)
            case .copyAndTranslate:
                controller.perform(#selector(PopoverController.copyAndTranslateHotKeyPressed), on: .main, with: nil, waitUntilDone: false)
            case .learn:
                controller.perform(#selector(PopoverController.learnHotKeyPressed), on: .main, with: nil, waitUntilDone: false)
            case .proofread:
                controller.perform(#selector(PopoverController.proofreadHotKeyPressed), on: .main, with: nil, waitUntilDone: false)
            case nil: break
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyEventHandlerRef)
    }

    func registerHotKey() {
        registeredHotKeys.forEach { UnregisterEventHotKey($0) }
        registeredHotKeys.removeAll()
        let signature = OSType(0x54524E53)
        let (register, skipped) = PopoverIntegrationPolicy.registrableHotkeys([
            (name: "Translate", hotkey: config.hotkey, id: 1),
            (name: "Copy & Translate", hotkey: config.copyTranslateHotkey, id: 2),
            (name: "Learn", hotkey: config.learnHotkey, id: 3),
            (name: "Proofread", hotkey: config.proofreadHotkey, id: 4),
        ])
        var failed: [String] = []
        for entry in register {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                HotkeyKeyCode.code(for: entry.hotkey.key),
                Self.hotKeyModifiers(entry.hotkey),
                EventHotKeyID(signature: signature, id: entry.id),
                GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                registeredHotKeys.append(ref)
            } else {
                failed.append(entry.name)
            }
        }
        var notes: [String] = []
        if !failed.isEmpty { notes.append("Failed to register: \(failed.joined(separator: ", "))") }
        if !skipped.isEmpty { notes.append("Duplicate hotkey ignored: \(skipped.joined(separator: ", "))") }
        if !notes.isEmpty { setStatus(notes.joined(separator: " · ")) }
    }

    @objc func hotKeyPressed() {
        translateAtCursor()
    }

    @objc func copyAndTranslateHotKeyPressed() {
        translateAtCursor(forceSimulatedCopy: true)
    }

    @objc func learnHotKeyPressed() {
        learnAtCursor()
    }

    @objc func proofreadHotKeyPressed() {
        proofreadAtCursor()
    }

    func proofreadAtCursor() {
        guard let resolved = readSelection(forceSimulatedCopy: false) else { return }
        guard prepareInputFromSelection(resolved) else { return }
        // Proofread works on text only; a pasted image would silently do nothing.
        guard pendingImage == nil else {
            setStatus("Proofread does not support images.")
            presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
            return
        }
        setResultText(PopoverFeedback.proofreading)
        reflowLayout()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        runProofread()
    }

    func learnAtCursor() {
        guard let resolved = readSelection(forceSimulatedCopy: false) else { return }
        if case let .text(candidate) = resolved.input,
           PopoverIntegrationPolicy.shouldSubtranslate(
               candidateText: candidate,
               originalSourceText: inputTextView.string,
               panelVisible: panel.isVisible,
               primaryResult: textView.string,
               hasPendingImage: pendingImage != nil
           ) {
            runSubRequest(text: candidate.trimmingCharacters(in: .whitespacesAndNewlines), mode: .learn)
            return
        }
        guard prepareInputFromSelection(resolved) else { return }
        // Learn has no image path; a pasted image would silently do nothing.
        guard pendingImage == nil else {
            setStatus("Learn does not support images.")
            presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
            return
        }
        setResultText(PopoverFeedback.learning)
        reflowLayout()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        runLearn()
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
        }
        reflowLayout()
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            translator = nil
            setResultText("Error: API key is empty — open Settings… and enter your 9router API key.")
            return outcome
        }
        translator = Translator(config: config, apiKey: trimmedAPIKey)
        configureLanguageControls()
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