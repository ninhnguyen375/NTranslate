import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation

struct AppConfig: Codable {
    struct Hotkey: Codable {
        var key: String
        var option: Bool
        var command: Bool
        var control: Bool
        var shift: Bool
    }

    struct UI: Codable {
        var width: Double
        var height: Double
        var autoCopy: Bool
    }

    var apiBaseURL: String
    var keychainService: String
    var model: String
    var lang: String
    var systemPrompt: String
    var speechSourceModel: String
    var speechSourceModelVietnamese: String
    var speechSourceModelChinese: String
    var speechTargetModel: String
    var hotkey: Hotkey
    var ui: UI

    static let configPath = NSString(string: "~/Code/MacOS/translate/config.json").expandingTildeInPath

    static let `default` = AppConfig(
        apiBaseURL: "http://localhost:20128/v1/chat/completions",
        keychainService: "9r-api-key",
        model: "9r-gemini-low",
        lang: "Vietnamese",
        systemPrompt: "You are a translation system. Translate the selected text to {{config.lang}}. Return only the final replacement text, with no explanations. Preserve meaning, tone, names, numbers, URLs, line breaks, and formatting where possible. The output will directly replace the user's selected text.",
        speechSourceModel: "edge-tts/en-US-AvaMultilingualNeural",
        speechSourceModelVietnamese: "edge-tts/vi-VN-HoaiMyNeural",
        speechSourceModelChinese: "edge-tts/zh-CN-XiaoxiaoNeural",
        speechTargetModel: "edge-tts/vi-VN-HoaiMyNeural",
        hotkey: .init(key: "D", option: true, command: false, control: false, shift: false),
        ui: .init(width: 480, height: 320, autoCopy: false)
    )

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return .default }
        return config
    }

    var speechURL: String {
        apiBaseURL.replacingOccurrences(of: "/chat/completions", with: "/audio/speech")
    }
}

struct SelectionReader {
    static func snapshotText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedElementRef) == .success,
              let focusedElement = focusedElementRef
        else { return nil }
        let element = unsafeDowncast(focusedElement, to: AXUIElement.self)
        var selectedTextRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
              let text = selectedTextRef as? String
        else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct APIKeychain {
    static func load(service: String) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        task.arguments = ["find-generic-password", "-s", service, "-w"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { throw NSError(domain: "Keychain", code: Int(task.terminationStatus)) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            throw NSError(domain: "Keychain", code: 1)
        }
        return value
    }
}

final class Translator {
    let config: AppConfig
    let apiKey: String

    init(config: AppConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    private func renderSystemPrompt() -> String {
        config.systemPrompt.replacingOccurrences(of: "{{config.lang}}", with: config.lang)
    }

    func translate(_ text: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: config.apiBaseURL) else {
            completion(.failure(NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid apiBaseURL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let wrappedText = "<selected-text>\(text)</selected-text>"
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": renderSystemPrompt()],
                ["role": "user", "content": wrappedText]
            ]
        ])
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(NSError(domain: "HTTP", code: 0)))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                return
            }
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let content = (((obj?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
            completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.resume()
    }

    func speak(_ text: String, model: String, completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty text"])))
            return
        }
        guard let url = URL(string: config.speechURL) else {
            completion(.failure(NSError(domain: "Config", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid speech URL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": trimmed
        ])
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(NSError(domain: "HTTP", code: 0)))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                return
            }
            do {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("translate-speech-\(UUID().uuidString)")
                    .appendingPathExtension("mp3")
                try data.write(to: outputURL, options: .atomic)
                completion(.success(outputURL))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

@MainActor
final class PopoverController: NSObject, NSApplicationDelegate, NSTextViewDelegate {
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
    private let translateButton = NSButton(frame: .zero)
    private let copyButton = NSButton(frame: .zero)
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
    private var config = AppConfig.load()
    private var audioPlayer: AVAudioPlayer?
    private var isSpeakingSource = false
    private var isSpeakingResult = false
    private var inputContainerView: NSView?
    private var keyMonitor: Any?

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
        reloadConfig()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "c"
            else { return event }
            self.copyResult()
            return nil
        }
    }


    private func buildPopover() {
        let width = CGFloat(config.ui.width)
        let height = CGFloat(config.ui.height)
        let padding: CGFloat = 14
        let headerHeight: CGFloat = 18
        let minInputHeight: CGFloat = 30
        let maxInputHeight: CGFloat = 74
        let inputHeight = inputHeight(for: inputTextView.string, minHeight: minInputHeight, maxHeight: maxInputHeight, width: width - padding * 2)
        let buttonHeight: CGFloat = 30
        let buttonGap: CGFloat = 8
        let buttonY = height - padding - headerHeight - 10 - inputHeight - 12 - buttonHeight
        let resultY = padding
        let resultHeight = max(120, buttonY - 12 - resultY)

        let vc = NSViewController()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Translate")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .labelColor
        title.frame = NSRect(x: padding, y: height - padding - headerHeight, width: 200, height: headerHeight)

        let inputFrame = NSRect(x: padding, y: height - padding - headerHeight - 10 - inputHeight, width: width - padding * 2, height: inputHeight)
        let inputContainer = NSView(frame: inputFrame)
        inputContainer.wantsLayer = true
        inputContainer.layer?.cornerRadius = 10
        inputContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        inputContainerView = inputContainer

        inputTextView.isEditable = true
        inputTextView.isSelectable = true
        inputTextView.delegate = self
        inputTextView.font = .systemFont(ofSize: 13)
        inputTextView.drawsBackground = false
        inputTextView.textColor = .labelColor
        inputTextView.isVerticallyResizable = true
        inputTextView.isHorizontallyResizable = false
        inputTextView.textContainerInset = NSSize(width: 6, height: 6)
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.textContainer?.containerSize = NSSize(width: inputFrame.width - 20, height: .greatestFiniteMagnitude)
        inputTextView.frame = NSRect(x: 0, y: 0, width: inputFrame.width - 20, height: inputHeight - 2)

        inputScrollView.frame = NSRect(x: 10, y: 1, width: inputFrame.width - 20, height: inputHeight - 2)
        inputScrollView.borderType = .noBorder
        inputScrollView.drawsBackground = false
        inputScrollView.hasVerticalScroller = inputHeight >= maxInputHeight
        inputScrollView.hasHorizontalScroller = false
        inputScrollView.autohidesScrollers = true
        inputScrollView.documentView = inputTextView
        inputContainer.addSubview(inputScrollView)

        translateButton.title = "Translate"
        translateButton.image = NSImage(systemSymbolName: "arrow.right.circle", accessibilityDescription: "Translate")
        translateButton.imagePosition = .imageLeading
        translateButton.target = self
        translateButton.action = #selector(runTranslate)
        translateButton.bezelStyle = .rounded
        translateButton.controlSize = .large
        translateButton.frame = NSRect(x: padding, y: buttonY, width: 110, height: buttonHeight)

        copyButton.title = "Copy"
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyButton.imagePosition = .imageLeading
        copyButton.target = self
        copyButton.action = #selector(copyResult)
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .large
        copyButton.frame = NSRect(x: translateButton.frame.maxX + buttonGap, y: buttonY, width: 78, height: buttonHeight)

        speakSourceButton.target = self
        speakSourceButton.action = #selector(speakInput)
        speakSourceButton.bezelStyle = .rounded
        speakSourceButton.controlSize = .large
        speakSourceButton.frame = NSRect(x: copyButton.frame.maxX + buttonGap, y: buttonY, width: 94, height: buttonHeight)

        speakResultButton.target = self
        speakResultButton.action = #selector(speakResult)
        speakResultButton.bezelStyle = .rounded
        speakResultButton.controlSize = .large
        speakResultButton.frame = NSRect(x: speakSourceButton.frame.maxX + buttonGap, y: buttonY, width: 94, height: buttonHeight)

        updateSpeakButtons()

        let resultCard = NSView(frame: NSRect(x: padding, y: resultY, width: width - padding * 2, height: resultHeight))
        resultCard.wantsLayer = true
        resultCard.layer?.cornerRadius = 12
        resultCard.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        textView.isEditable = false
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
        root.addSubview(inputContainer)
        root.addSubview(translateButton)
        root.addSubview(copyButton)
        root.addSubview(speakSourceButton)
        root.addSubview(speakResultButton)
        root.addSubview(resultCard)
        vc.view = root
        popover.contentViewController = vc
        popover.behavior = .transient
    }

    private func rebuildPopoverLayout() {
        let wasShown = popover.isShown
        let existingResult = textView.string
        let existingInput = inputTextView.string
        buildPopover()
        inputTextView.string = existingInput
        textView.string = existingResult
        if wasShown {
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    private func inputHeight(for text: String, minHeight: CGFloat, maxHeight: CGFloat, width: CGFloat) -> CGFloat {
        let contentWidth = max(100, width - 20)
        let storage = NSTextStorage(string: text.isEmpty ? " " : text)
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        storage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: NSRange(location: 0, length: storage.length))
        layoutManager.ensureLayout(for: container)
        let usedHeight = layoutManager.usedRect(for: container).height
        let measured = ceil(usedHeight + 14)
        return min(max(minHeight, measured), maxHeight)
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === inputTextView else { return }
        let selectedRange = inputTextView.selectedRange()
        let currentText = inputTextView.string
        rebuildPopoverLayout()
        inputTextView.string = currentText
        inputTextView.setSelectedRange(selectedRange)
    }

    private func updateSpeakButtons() {
        speakSourceButton.title = isSpeakingSource ? "Loading" : "Speak Src"
        speakSourceButton.image = NSImage(systemSymbolName: isSpeakingSource ? "hourglass" : "speaker.wave.2", accessibilityDescription: "Speak source")
        speakSourceButton.imagePosition = .imageLeading
        speakSourceButton.isEnabled = !isSpeakingSource

        speakResultButton.title = isSpeakingResult ? "Loading" : "Speak Tr"
        speakResultButton.image = NSImage(systemSymbolName: isSpeakingResult ? "hourglass" : "speaker.wave.2", accessibilityDescription: "Speak translation")
        speakResultButton.imagePosition = .imageLeading
        speakResultButton.isEnabled = !isSpeakingResult
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
        let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        if sample.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF }) {
            return config.speechSourceModelChinese
        }
        if sample.contains(where: { $0.value >= 0x0102 && $0.value <= 0x1EF9 }) || text.localizedCaseInsensitiveContains("đ") {
            return config.speechSourceModelVietnamese
        }
        return config.speechSourceModel
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Grant Accessibility Access", action: #selector(requestAccessibilityPermissionMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Reload Config", action: #selector(reloadConfigMenu), keyEquivalent: "r")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func requestAccessibilityPermissionMenu() {
        requestAccessibilityPermissionIfNeeded(forcePrompt: true)
    }

    @objc private func reloadConfigMenu() {
        reloadConfig()
        textView.string = "Reloaded config from \(AppConfig.configPath)"
    }

    private func hotKeyCode(for key: String) -> UInt32 {
        switch key.uppercased() {
        case "A": return UInt32(kVK_ANSI_A)
        case "B": return UInt32(kVK_ANSI_B)
        case "C": return UInt32(kVK_ANSI_C)
        case "D": return UInt32(kVK_ANSI_D)
        case "E": return UInt32(kVK_ANSI_E)
        case "F": return UInt32(kVK_ANSI_F)
        case "G": return UInt32(kVK_ANSI_G)
        case "H": return UInt32(kVK_ANSI_H)
        case "I": return UInt32(kVK_ANSI_I)
        case "J": return UInt32(kVK_ANSI_J)
        case "K": return UInt32(kVK_ANSI_K)
        case "L": return UInt32(kVK_ANSI_L)
        case "M": return UInt32(kVK_ANSI_M)
        case "N": return UInt32(kVK_ANSI_N)
        case "O": return UInt32(kVK_ANSI_O)
        case "P": return UInt32(kVK_ANSI_P)
        case "Q": return UInt32(kVK_ANSI_Q)
        case "R": return UInt32(kVK_ANSI_R)
        case "S": return UInt32(kVK_ANSI_S)
        case "T": return UInt32(kVK_ANSI_T)
        case "U": return UInt32(kVK_ANSI_U)
        case "V": return UInt32(kVK_ANSI_V)
        case "W": return UInt32(kVK_ANSI_W)
        case "X": return UInt32(kVK_ANSI_X)
        case "Y": return UInt32(kVK_ANSI_Y)
        case "Z": return UInt32(kVK_ANSI_Z)
        default: return UInt32(kVK_ANSI_D)
        }
    }

    private func hotKeyModifiers() -> UInt32 {
        var flags: UInt32 = 0
        if config.hotkey.option { flags |= UInt32(optionKey) }
        if config.hotkey.command { flags |= UInt32(cmdKey) }
        if config.hotkey.control { flags |= UInt32(controlKey) }
        if config.hotkey.shift { flags |= UInt32(shiftKey) }
        return flags
    }

    private func registerHotKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let hotKeyID = EventHotKeyID(signature: OSType(0x54524E53), id: 1)
        let status = RegisterEventHotKey(hotKeyCode(for: config.hotkey.key), hotKeyModifiers(), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            textView.string = "Failed to register hotkey"
            return
        }
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
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @objc private func manualToggle() {
        guard NSApp.currentEvent?.type == .leftMouseUp else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func reloadConfig() {
        config = AppConfig.load()
        rebuildPopoverLayout()
        do {
            translator = try Translator(config: config, apiKey: APIKeychain.load(service: config.keychainService))
            registerHotKey()
            assert(URL(string: config.apiBaseURL) != nil)
            assert(URL(string: config.speechURL) != nil)
        } catch {
            textView.string = "Config load error: \(error.localizedDescription)"
        }
    }

    private func requestAccessibilityPermissionIfNeeded(forcePrompt: Bool = false) {
        guard !AXIsProcessTrusted() || forcePrompt else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            textView.string = "Grant Accessibility access in System Settings > Privacy & Security > Accessibility, then reopen or retry."
        }
    }

    private func moveAnchorWindowToMouse() {
        let mouse = NSEvent.mouseLocation
        anchorWindow.setFrame(NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1), display: false)
        anchorWindow.orderFrontRegardless()
    }

    func translateAtCursor() {
        if !AXIsProcessTrusted() {
            requestAccessibilityPermissionIfNeeded(forcePrompt: true)
        }
        let text = SelectionReader.snapshotText() ?? NSPasteboard.general.string(forType: .string) ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputTextView.string = trimmed
        rebuildPopoverLayout()
        textView.string = "Translating..."
        moveAnchorWindowToMouse()
        if !popover.isShown {
            popover.show(relativeTo: anchorWindow.contentView!.bounds, of: anchorWindow.contentView!, preferredEdge: .maxY)
        }
        NSApp.activate(ignoringOtherApps: true)
        runTranslate()
    }

    @objc func runTranslate() {
        guard let translator else { return }
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        textView.string = "Translating..."
        translator.translate(text) { [weak self] result in
            Task { @MainActor in
                switch result {
                case let .success(value):
                    self?.textView.string = value
                    self?.textView.scrollToBeginningOfDocument(nil)
                    if self?.config.ui.autoCopy == true {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }
                case let .failure(error):
                    self?.textView.string = "Error: \(error.localizedDescription)"
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
            textView.string = "Error: Empty speech model"
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
                        self.textView.string = "Error: \(error.localizedDescription)"
                    }
                case let .failure(error):
                    self.textView.string = "Error: \(error.localizedDescription)"
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

    @objc func copyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
        popover.performClose(nil)
    }
}

@main
struct AppMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = PopoverController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
