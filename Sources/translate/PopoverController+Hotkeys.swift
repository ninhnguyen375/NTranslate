// Global hotkey registration, event handling, and proofread/learn cursor entry points.
import AppKit
import Carbon.HIToolbox

extension PopoverController {

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
            case .ocr:
                controller.perform(#selector(PopoverController.ocrHotKeyPressed), on: .main, with: nil, waitUntilDone: false)
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
            (name: "OCR Translate", hotkey: config.ocrHotkey, id: 5),
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
        beginAtCursor(loading: PopoverFeedback.proofreading) { [weak self] resolved in
            guard let self, self.prepareInputFromSelection(resolved) else { return }
            // Proofread works on text only; a pasted image would silently do nothing.
            guard self.pendingImage == nil else {
                self.setStatus("Proofread does not support images.")
                self.presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
                return
            }
            self.setResultText(PopoverFeedback.proofreading)
            self.reflowLayout()
            self.presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
            self.runProofread()
        }
    }

    func learnAtCursor() {
        beginAtCursor(loading: PopoverFeedback.learning) { [weak self] resolved in
            guard let self else { return }
            guard self.prepareInputFromSelection(resolved) else { return }
            // Learn has no image path; a pasted image would silently do nothing.
            guard self.pendingImage == nil else {
                self.setStatus("Learn does not support images.")
                self.presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
                return
            }
            self.setResultText(PopoverFeedback.learning)
            self.reflowLayout()
            self.presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
            self.runLearn()
        }
    }
}
