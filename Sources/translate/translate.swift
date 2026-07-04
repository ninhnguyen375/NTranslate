import Foundation
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation

extension NSAttributedString {
    static func markdownDisplay(_ text: String, font: NSFont) -> NSAttributedString {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return NSAttributedString(string: "", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        }
        let markdown = trimmed.replacingOccurrences(of: "\n", with: "  \n")
        if #available(macOS 12.0, *) {
            if let attributed = try? AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            ) {
                let mutable = NSMutableAttributedString(attributedString: NSAttributedString(attributed))
                let fullRange = NSRange(location: 0, length: mutable.length)
                mutable.addAttributes([
                    .font: font,
                    .foregroundColor: NSColor.labelColor
                ], range: fullRange)
                mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                    guard let currentFont = value as? NSFont else { return }
                    let traits = currentFont.fontDescriptor.symbolicTraits
                    var converted = font
                    if traits.contains(.bold) {
                        converted = NSFontManager.shared.convert(converted, toHaveTrait: .boldFontMask)
                    }
                    if traits.contains(.italic) {
                        converted = NSFontManager.shared.convert(converted, toHaveTrait: .italicFontMask)
                    }
                    mutable.addAttribute(.font, value: converted, range: range)
                }
                return mutable
            }
        }
        return NSAttributedString(string: trimmed, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
    }
}

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
    var sourceLang: String
    var targetLang: String
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
        sourceLang: "Auto detect",
        targetLang: "Vietnamese",
        systemPrompt: "You are a translation system. Translate the selected text from {{config.sourceLang}} to {{config.targetLang}}. If source is Auto detect, detect it first. Return only the final replacement text as valid markdown, with no explanations. Preserve meaning, tone, names, numbers, URLs, line breaks, and formatting where possible. Use markdown for emphasis, lists, and structure only when it improves readability and stays faithful to the source. The output will directly replace the user's selected text.",
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

    var resolvedSourceLang: String {
        sourceLang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Auto detect" : sourceLang
    }

    var resolvedTargetLang: String {
        targetLang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Vietnamese" : targetLang
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

    private enum RequestMode {
        case translate(sourceLang: String, targetLang: String)
        case learn(sourceLang: String, targetLang: String)
    }

    init(config: AppConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    private func renderSystemPrompt(sourceLang: String, targetLang: String) -> String {
        config.systemPrompt
            .replacingOccurrences(of: "{{config.sourceLang}}", with: sourceLang)
            .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
    }

    private func renderLearnPrompt(sourceLang: String, targetLang: String) -> String {
        """
        You are an English learning assistant for a Vietnamese learner.
        Explain the selected text in concise Vietnamese.
        If the selected text is not a single English word, extract the most useful English word or short phrase to learn.
        Return markdown only in this exact format, with no intro and no extra sections:

        IPA: /.../
        n. ...
        v. ...
        adj. ...

        Ví dụ
        - Example sentence.
          → Bản dịch tiếng Việt.
        - Example sentence.
          → Bản dịch tiếng Việt.

        Nhớ nhanh
        - ...
        - ...
        - ...

        Rules:
        - Omit any part of speech that does not fit.
        - Keep each meaning very short.
        - Examples must be natural and useful.
        - In "Nhớ nhanh", explain the fastest way to grasp and remember the word.
        - Target learner language: Vietnamese.
        - Source language hint: \(sourceLang). Target language hint: \(targetLang).
        """
    }

    private func request(_ text: String, mode: RequestMode, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: config.apiBaseURL) else {
            completion(.failure(NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid apiBaseURL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let wrappedText = "<selected-text>\(text)</selected-text>"
        let systemPrompt: String
        switch mode {
        case let .translate(sourceLang, targetLang):
            systemPrompt = renderSystemPrompt(sourceLang: sourceLang, targetLang: targetLang)
        case let .learn(sourceLang, targetLang):
            systemPrompt = renderLearnPrompt(sourceLang: sourceLang, targetLang: targetLang)
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
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

    func translate(_ text: String, sourceLang: String, targetLang: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        request(text, mode: .translate(sourceLang: sourceLang, targetLang: targetLang), completion: completion)
    }

    func learn(_ text: String, sourceLang: String, targetLang: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        request(text, mode: .learn(sourceLang: sourceLang, targetLang: targetLang), completion: completion)
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
    private var globalKeyMonitor: Any?
    private var globalMouseMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var shouldRestorePreviousAppFocus = false
    private var shouldActivateAppForSelectionFlow = false
    private var shouldRestoreFocusOnDismiss = false
    private let supportedLanguages = ["Auto detect", "English", "Vietnamese", "Chinese"]

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
            if event.keyCode == UInt16(kVK_Escape) {
                self.shouldRestoreFocusOnDismiss = true
                self.shouldRestorePreviousAppFocus = true
                self.popover.performClose(nil)
                return nil
            }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "c"
            else { return event }
            self.shouldRestoreFocusOnDismiss = true
            self.copyResult()
            return nil
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return }
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in
                    self.shouldRestoreFocusOnDismiss = true
                    self.shouldRestorePreviousAppFocus = true
                    self.popover.performClose(nil)
                }
                return
            }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
                  event.charactersIgnoringModifiers?.lowercased() == "c"
            else { return }
            Task { @MainActor in
                self.shouldRestoreFocusOnDismiss = true
                self.copyResult()
            }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, self.popover.isShown else { return }
            Task { @MainActor in
                self.shouldRestoreFocusOnDismiss = false
                self.shouldRestorePreviousAppFocus = false
                self.popover.performClose(nil)
            }
        }
    }


    private func buildPopover() {
        let width = CGFloat(config.ui.width)
        let height = max(CGFloat(config.ui.height), preferredPopoverHeight())
        let padding: CGFloat = 14
        let headerHeight: CGFloat = 18
        let languageHeight: CGFloat = 28
        let minInputHeight: CGFloat = 30
        let maxInputHeight: CGFloat = 74
        let buttonHeight: CGFloat = 30
        let buttonGap: CGFloat = 8
        let buttonTitles = ["Translate", "Learn", "Copy", speakSourceButtonTitle(), speakResultButtonTitle()]
        let buttonFonts = [translateButton, learnButton, copyButton, speakSourceButton, speakResultButton].map {
            ($0.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)).withSize(NSFont.systemFontSize)
        }
        let languageY = height - padding - headerHeight - 10 - languageHeight
        let inputHeight = inputHeight(for: inputTextView.string, minHeight: minInputHeight, maxHeight: maxInputHeight, width: width - padding * 2)
        let inputY = languageY - 10 - inputHeight
        let buttonY = inputY - 12 - buttonHeight
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

        learnButton.title = "Learn"
        learnButton.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "Learn")
        learnButton.imagePosition = .imageLeading
        learnButton.target = self
        learnButton.action = #selector(runLearn)
        learnButton.bezelStyle = .rounded
        learnButton.controlSize = .large

        copyButton.title = "Copy"
        copyButton.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        copyButton.imagePosition = .imageLeading
        copyButton.target = self
        copyButton.action = #selector(copyResult)
        copyButton.bezelStyle = .rounded
        copyButton.controlSize = .large

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
        root.addSubview(closeButton)
        root.addSubview(sourceLanguagePopup)
        root.addSubview(swapLanguagesButton)
        root.addSubview(targetLanguagePopup)
        root.addSubview(inputContainer)
        root.addSubview(translateButton)
        root.addSubview(learnButton)
        root.addSubview(copyButton)
        root.addSubview(speakSourceButton)
        root.addSubview(speakResultButton)
        root.addSubview(resultCard)
        vc.view = root
        popover.contentViewController = vc
        popover.delegate = self
        popover.behavior = .transient
    }

    private func rebuildPopoverLayout() {
        let wasShown = popover.isShown
        let existingResult = textView.string
        let existingInput = inputTextView.string
        buildPopover()
        inputTextView.string = existingInput
        setResultText(existingResult)
        if wasShown {
            popover.contentSize = popover.contentViewController?.view.frame.size ?? .zero
            textView.scrollToBeginningOfDocument(nil)
        }
    }

    private func setResultText(_ value: String) {
        textView.textStorage?.setAttributedString(.markdownDisplay(value, font: .systemFont(ofSize: 13)))
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

    private func measuredTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let contentWidth = max(100, width)
        let storage = NSTextStorage(attributedString: text.length == 0 ? NSAttributedString(string: " ") : text)
        let container = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        return ceil(layoutManager.usedRect(for: container).height)
    }

    private func selectedSourceLanguage() -> String {
        sourceLanguagePopup.selectedItem?.title ?? config.resolvedSourceLang
    }

    private func selectedTargetLanguage() -> String {
        targetLanguagePopup.selectedItem?.title ?? config.resolvedTargetLang
    }

    private func normalizeSourceLanguage(_ value: String) -> String {
        supportedLanguages.contains(value) ? value : "Auto detect"
    }

    private func normalizeTargetLanguage(_ value: String) -> String {
        supportedLanguages.contains(value) && value != "Auto detect" ? value : "Vietnamese"
    }

    private func resolvedLanguagePair(for text: String) -> (source: String, target: String) {
        let source = normalizeSourceLanguage(selectedSourceLanguage())
        var target = normalizeTargetLanguage(selectedTargetLanguage())
        if source == "Vietnamese" {
            target = "English"
        }
        if source == target {
            target = source == "English" ? "Vietnamese" : "English"
        }
        if source == "Auto detect" {
            let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
            let looksVietnamese = sample.contains(where: { $0.value >= 0x0102 && $0.value <= 0x1EF9 }) || text.localizedCaseInsensitiveContains("đ")
            if looksVietnamese {
                target = "English"
            }
        }
        return (source, target)
    }

    private func configureLanguageControls() {
        sourceLanguagePopup.removeAllItems()
        sourceLanguagePopup.addItems(withTitles: supportedLanguages)
        sourceLanguagePopup.selectItem(withTitle: normalizeSourceLanguage(config.resolvedSourceLang))
        sourceLanguagePopup.target = self
        sourceLanguagePopup.action = #selector(languageSelectionChanged)

        targetLanguagePopup.removeAllItems()
        targetLanguagePopup.addItems(withTitles: supportedLanguages.filter { $0 != "Auto detect" })
        targetLanguagePopup.selectItem(withTitle: normalizeTargetLanguage(config.resolvedTargetLang))
        targetLanguagePopup.target = self
        targetLanguagePopup.action = #selector(languageSelectionChanged)

        swapLanguagesButton.title = "⇄"
        swapLanguagesButton.bezelStyle = .rounded
        swapLanguagesButton.target = self
        swapLanguagesButton.action = #selector(swapLanguages)
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as AnyObject? === inputTextView else { return }
        let selectedRange = inputTextView.selectedRange()
        let currentText = inputTextView.string
        rebuildPopoverLayout()
        inputTextView.string = currentText
        inputTextView.setSelectedRange(selectedRange)
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
        let source = normalizeSourceLanguage(selectedSourceLanguage())
        let target = normalizeTargetLanguage(selectedTargetLanguage())
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

    private func layoutActionButtons(y: CGFloat, height: CGFloat, gap: CGFloat, width: CGFloat, titles: [String], fonts: [NSFont]) {
        let buttons = [translateButton, learnButton, copyButton, speakSourceButton, speakResultButton]
        let symbolPadding: CGFloat = 30
        let horizontalPadding: CGFloat = 18
        let minWidth: CGFloat = 68
        let naturalWidths = zip(titles, fonts).map { title, font in
            max(minWidth, ceil((title as NSString).size(withAttributes: [.font: font]).width) + symbolPadding + horizontalPadding)
        }
        let availableWidth = max(0, width - gap * CGFloat(max(0, buttons.count - 1)))
        let totalNaturalWidth = naturalWidths.reduce(0, +)
        let scale = totalNaturalWidth > 0 ? min(1, availableWidth / totalNaturalWidth) : 1
        var x: CGFloat = 14
        for (index, button) in buttons.enumerated() {
            let buttonWidth = max(minWidth, floor(naturalWidths[index] * scale))
            button.frame = NSRect(x: x, y: y, width: buttonWidth, height: height)
            x += buttonWidth + gap
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
        setResultText("Reloaded config from \(AppConfig.configPath)")
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
            setResultText("Failed to register hotkey")
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
            shouldRestoreFocusOnDismiss = true
            shouldRestorePreviousAppFocus = true
            popover.performClose(nil)
        } else if let button = statusItem.button {
            shouldActivateAppForSelectionFlow = true
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
            setResultText("Config load error: \(error.localizedDescription)")
        }
    }

    private func requestAccessibilityPermissionIfNeeded(forcePrompt: Bool = false) {
        guard !AXIsProcessTrusted() || forcePrompt else { return }
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
        defer {
            previousApp = nil
            shouldRestorePreviousAppFocus = false
            shouldActivateAppForSelectionFlow = false
            shouldRestoreFocusOnDismiss = false
        }
        guard shouldRestorePreviousAppFocus, shouldRestoreFocusOnDismiss else { return }
        previousApp?.activate(options: [.activateIgnoringOtherApps])
    }

    func popoverDidClose(_ notification: Notification) {
        restorePreviousAppFocus()
    }

    func popoverDidShow(_ notification: Notification) {
        guard shouldActivateAppForSelectionFlow else { return }
        NSApp.activate(ignoringOtherApps: true)
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
        rebuildPopoverLayout()
        updateLanguageSelection(for: trimmed)
        setResultText("Translating...")
        moveAnchorWindowToMouse()
        if !popover.isShown {
            shouldRestorePreviousAppFocus = true
            shouldActivateAppForSelectionFlow = false
            shouldRestoreFocusOnDismiss = false
            popover.show(relativeTo: anchorWindow.contentView!.bounds, of: anchorWindow.contentView!, preferredEdge: .maxY)
        }
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
                    self?.rebuildPopoverLayout()
                    self?.setResultText(value)
                    self?.textView.scrollToBeginningOfDocument(nil)
                    if self?.config.ui.autoCopy == true {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }
                case let .failure(error):
                    self?.rebuildPopoverLayout()
                    self?.setResultText("Error: \(error.localizedDescription)")
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
                    self?.rebuildPopoverLayout()
                    self?.setResultText(value)
                    self?.textView.scrollToBeginningOfDocument(nil)
                case let .failure(error):
                    self?.rebuildPopoverLayout()
                    self?.setResultText("Error: \(error.localizedDescription)")
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

    private func writeClipboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.declareTypes([.string], owner: nil)
        let didWritePasteboard = pasteboard.setString(value, forType: .string)
        let didVerifyPasteboard = NSPasteboard.general.string(forType: .string) == value
        guard !(didWritePasteboard && didVerifyPasteboard) else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pbcopy")
        let input = Pipe()
        task.standardInput = input
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        do {
            try task.run()
            if let data = value.data(using: .utf8) {
                input.fileHandleForWriting.write(data)
            }
            input.fileHandleForWriting.closeFile()
            task.waitUntilExit()
        } catch {
            setResultText("Error: \(error.localizedDescription)")
        }
    }

    @objc func copyResult() {
        let value = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != "Translating..." else {
            shouldRestoreFocusOnDismiss = true
            shouldRestorePreviousAppFocus = true
            popover.performClose(nil)
            return
        }
        writeClipboard(value)
        shouldRestoreFocusOnDismiss = true
        shouldRestorePreviousAppFocus = true
        popover.performClose(nil)
    }

    @objc private func closePopover() {
        shouldRestoreFocusOnDismiss = true
        shouldRestorePreviousAppFocus = true
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
