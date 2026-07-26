import AppKit
import Testing
@testable import translate

struct TranslateTests {
    @Test func imageSearchURLPreservesUnicodeAndGoogleImagesMode() throws {
        let url = try #require(PopoverIntegrationPolicy.imageSearchURL(query: "thiên hà xoắn ốc NASA"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.host == "www.google.com")
        #expect(components.queryItems?.first(where: { $0.name == "tbm" })?.value == "isch")
        #expect(components.queryItems?.first(where: { $0.name == "q" })?.value == "thiên hà xoắn ốc NASA")
    }

    @Test func resolvedImageSearchURLPrefersSuccessQueryOverFallback() throws {
        let url = try #require(PopoverIntegrationPolicy.resolvedImageSearchURL(queryResult: .success("success_query"), fallbackText: "fallback_text"))
        #expect(url.absoluteString.contains("q=success_query"))
        #expect(!url.absoluteString.contains("fallback"))
    }

    @Test func resolvedImageSearchURLFallsBackOnFailure() throws {
        let url = try #require(PopoverIntegrationPolicy.resolvedImageSearchURL(queryResult: .failure(NSError(domain: "", code: 0)), fallbackText: "fallback_text"))
        #expect(url.absoluteString.contains("q=fallback_text"))
    }

    @Test func imageSearchPromptRequestsOnlyConcreteQuery() {
        #expect(Translator.imageSearchPrompt.contains("Return only"))
        #expect(Translator.imageSearchPrompt.localizedCaseInsensitiveContains("concrete"))
    }

    @Test func plainDisplayPreservesReadableText() {
        let rendered = NSAttributedString.plainDisplay("**Bold** and *italic*", font: .systemFont(ofSize: 13))
        #expect(rendered.string == "**Bold** and *italic*")
    }

    @Test func plainDisplayUsesProvidedColor() {
        let rendered = NSAttributedString.plainDisplay("hi", font: .systemFont(ofSize: 13), color: .systemRed)
        #expect(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == NSColor.systemRed)
    }

    @Test func popoverFeedbackMarksLoadingAndErrorStyles() {
        #expect(PopoverFeedback.resultStyle(for: PopoverFeedback.translating) == .loading)
        #expect(PopoverFeedback.resultStyle(for: PopoverFeedback.learning) == .loading)
        #expect(PopoverFeedback.resultStyle(for: PopoverFeedback.emptySelectionGuidance) == .loading)
        #expect(PopoverFeedback.resultStyle(for: PopoverFeedback.textTooLong) == .error)
        #expect(PopoverFeedback.resultStyle(for: "Error: boom") == .error)
        #expect(PopoverFeedback.resultStyle(for: "xin chào") == .normal)
    }

    @Test func popoverFeedbackIgnoresStaleGenerations() {
        #expect(PopoverFeedback.isStale(resultGeneration: 1, currentGeneration: 2))
        #expect(!PopoverFeedback.isStale(resultGeneration: 3, currentGeneration: 3))
    }

    @Test func popoverFeedbackCopyableResultExcludesHintsAndErrors() {
        #expect(!PopoverFeedback.isCopyableResult(PopoverFeedback.translating))
        #expect(!PopoverFeedback.isCopyableResult(PopoverFeedback.learning))
        #expect(!PopoverFeedback.isCopyableResult(PopoverFeedback.emptyInputHint))
        #expect(!PopoverFeedback.isCopyableResult(PopoverFeedback.textTooLong))
        #expect(!PopoverFeedback.isCopyableResult("Error: failed"))
        #expect(!PopoverFeedback.isCopyableResult("   "))
        #expect(PopoverFeedback.isCopyableResult("hello"))
    }

    @Test func popoverFeedbackAccessibilityFallbackNoteNamesSource() {
        #expect(PopoverFeedback.accessibilityFallbackNote(source: .clipboard) == "Used clipboard (selection read failed)")
        #expect(PopoverFeedback.accessibilityFallbackNote(source: .simulatedCopy) == "Used simulated copy (selection read failed)")
    }

    @Test func hotkeyCodeFallsBackToDForUnknownKey() {
        #expect(HotkeyKeyCode.code(for: "1") == HotkeyKeyCode.code(for: "D"))
    }

    @Test func hotkeyCodeIsCaseInsensitive() {
        #expect(HotkeyKeyCode.code(for: "a") == HotkeyKeyCode.code(for: "A"))
    }

    @Test func languageDetectorNormalizesUnknownSourceToAutoDetect() {
        #expect(LanguageDetector.normalizeSource("French") == "Auto detect")
    }

    @Test func languageDetectorNormalizesUnknownOrAutoTargetToVietnamese() {
        #expect(LanguageDetector.normalizeTarget("French") == "Vietnamese")
        #expect(LanguageDetector.normalizeTarget("Auto detect") == "Vietnamese")
    }

    @Test func languageDetectorAutoDetectsVietnameseTextAndTargetsEnglish() {
        let pair = LanguageDetector.resolvedPair(selectedSource: "Auto detect", selectedTarget: "Vietnamese", text: "xin chào các bạn")
        #expect(pair.target == "English")
    }

    @Test func languageDetectorAllowsSameSourceAndTargetForGrammarMode() {
        let pair = LanguageDetector.resolvedPair(selectedSource: "English", selectedTarget: "English", text: "hello")
        #expect(pair.source == "English")
        #expect(pair.target == "English")
    }

    @Test func languageDetectorRecognizesChineseText() {
        #expect(LanguageDetector.looksChinese("你好") == true)
        #expect(LanguageDetector.looksChinese("hello") == false)
    }

    @Test func appConfigDecodeOutcomeReportsMalformedJSON() {
        let outcome = AppConfig.decodeOutcome(data: Data("{".utf8))
        guard case let .failed(config, message) = outcome else {
            Issue.record("Expected failed outcome")
            return
        }
        #expect(config.apiBaseURL == AppConfig.default.apiBaseURL)
        #expect(message.isEmpty == false)
    }

    @Test func appConfigDecodeOutcomeLoadsValidJSON() throws {
        let data = try JSONEncoder().encode(AppConfig.default)
        let outcome = AppConfig.decodeOutcome(data: data)
        guard case let .loaded(config) = outcome else {
            Issue.record("Expected loaded outcome")
            return
        }
        #expect(config.apiBaseURL == AppConfig.default.apiBaseURL)
        #expect(config.ui.simulateCopy == false)
    }

    @Test func appConfigDefaultsIssueFields() {
        #expect(AppConfig.default.sentenceLearnPrompt == AppConfig.defaultSentenceLearnPrompt)
        #expect(!AppConfig.default.autoPrefetchSpeech)
    }

    @Test func appConfigDecodeDefaultsIssueFieldsWhenMissing() throws {
        let data = try JSONEncoder().encode(AppConfig.default)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "sentenceLearnPrompt")
        object.removeValue(forKey: "autoPrefetchSpeech")
        let decoded = try JSONDecoder().decode(
            AppConfig.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.sentenceLearnPrompt == AppConfig.defaultSentenceLearnPrompt)
        #expect(!decoded.autoPrefetchSpeech)
    }

    @Test func appConfigDecodeKeepsExplicitIssueFields() throws {
        let data = try JSONEncoder().encode(AppConfig.default)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["sentenceLearnPrompt"] = "custom sentence prompt"
        object["autoPrefetchSpeech"] = true
        let decoded = try JSONDecoder().decode(
            AppConfig.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        #expect(decoded.sentenceLearnPrompt == "custom sentence prompt")
        #expect(decoded.autoPrefetchSpeech)
    }

    @Test func learnPromptRoutesByWhitespace() {
        var config = AppConfig.default
        config.learnPrompt = "WORD {{config.sourceLang}} {{config.targetLang}}"
        config.sentenceLearnPrompt = "SENTENCE {{config.sourceLang}} {{config.targetLang}}"

        #expect(Translator.renderLearnPrompt(for: "can't", sourceLang: "English", targetLang: "Vietnamese", config: config) == "WORD English Vietnamese")
        #expect(Translator.renderLearnPrompt(for: "state-of-the-art", sourceLang: "English", targetLang: "Vietnamese", config: config) == "WORD English Vietnamese")
        #expect(Translator.renderLearnPrompt(for: "hello world", sourceLang: "English", targetLang: "Vietnamese", config: config) == "SENTENCE English Vietnamese")
        #expect(Translator.renderLearnPrompt(for: "hello\nworld", sourceLang: "English", targetLang: "Vietnamese", config: config) == "SENTENCE English Vietnamese")
    }

    @Test func languageDetectorUsesConfiguredNativeLangFallback() {
        let pair = LanguageDetector.resolvedPair(
            selectedSource: "Auto detect",
            selectedTarget: "English",
            text: "hello world",
            targetLanguages: ["English", "French"],
            nativeLang: "French"
        )
        #expect(pair.target == "French")
    }

    @Test func languageDetectorFallbackTargetPrefersNonNativeWhenDetectedIsNative() {
        let target = LanguageDetector.fallbackTarget(
            detected: "Vietnamese",
            targetLanguages: ["English", "Vietnamese"],
            nativeLang: "Vietnamese"
        )
        #expect(target == "English")
    }

    @Test func appConfigDecodeDerivesSpeechURLWhenMissing() throws {
        let json = """
        {"apiBaseURL":"http://localhost:1/v1/chat/completions","apiKey":"","model":"m","sourceLang":"Auto detect","targetLang":"Vietnamese","systemPrompt":"p","speechSourceModel":"a","speechSourceModelVietnamese":"b","speechSourceModelChinese":"c","speechTargetModel":"d","hotkey":{"key":"D","option":true,"command":false,"control":false,"shift":false},"ui":{"width":480,"height":320,"autoCopy":false}}
        """
        let outcome = AppConfig.decodeOutcome(data: Data(json.utf8))
        guard case let .loaded(config) = outcome else {
            Issue.record("Expected loaded outcome")
            return
        }
        #expect(config.apiSpeechURL == "http://localhost:1/v1/audio/speech")
        #expect(config.nativeLang == "Vietnamese")
        #expect(config.languages == AppConfig.defaultLanguages)
        #expect(config.targetLanguages == AppConfig.defaultTargetLanguages)
        #expect(config.maxTranslateLength == 5000)
        #expect(config.grammarPrompt == AppConfig.defaultGrammarPrompt)
    }

    @Test func appConfigDecodeKeepsExplicitSpeechURLAndNewKeys() throws {
        let json = """
        {"apiBaseURL":"http://localhost:1/v1/chat/completions","apiSpeechURL":"http://speech.example/v1/audio/speech","apiKey":"k","model":"m","sourceLang":"Auto detect","targetLang":"English","nativeLang":"English","languages":["Auto detect","English"],"targetLanguages":["English"],"maxTranslateLength":123,"systemPrompt":"p","learnPrompt":"learn","grammarPrompt":"grammar {{lang}} {{config.nativeLang}}","speechSourceModel":"a","speechSourceModelVietnamese":"b","speechSourceModelChinese":"c","speechTargetModel":"d","hotkey":{"key":"D","option":true,"command":false,"control":false,"shift":false},"ui":{"width":480,"height":320,"autoCopy":false}}
        """
        let outcome = AppConfig.decodeOutcome(data: Data(json.utf8))
        guard case let .loaded(config) = outcome else {
            Issue.record("Expected loaded outcome")
            return
        }
        #expect(config.apiSpeechURL == "http://speech.example/v1/audio/speech")
        #expect(config.nativeLang == "English")
        #expect(config.languages == ["Auto detect", "English"])
        #expect(config.targetLanguages == ["English"])
        #expect(config.maxTranslateLength == 123)
        #expect(config.grammarPrompt.contains("{{lang}}"))
    }

    @Test func appConfigDecodeAcceptsLegacySpeechURLKey() throws {
        let json = """
        {"apiBaseURL":"http://localhost:1/v1/chat/completions","speechURL":"http://legacy.example/v1/audio/speech","apiKey":"","model":"m","sourceLang":"Auto detect","targetLang":"Vietnamese","systemPrompt":"p","speechSourceModel":"a","speechSourceModelVietnamese":"b","speechSourceModelChinese":"c","speechTargetModel":"d","hotkey":{"key":"D","option":true,"command":false,"control":false,"shift":false},"ui":{"width":480,"height":320,"autoCopy":false}}
        """
        let outcome = AppConfig.decodeOutcome(data: Data(json.utf8))
        guard case let .loaded(config) = outcome else {
            Issue.record("Expected loaded outcome")
            return
        }
        #expect(config.apiSpeechURL == "http://legacy.example/v1/audio/speech")
    }

    @Test func appConfigDecodeDefaultsSimulateCopyWhenMissing() throws {
        let json = """
        {"apiBaseURL":"http://localhost:1/v1/chat/completions","apiKey":"","model":"m","sourceLang":"Auto detect","targetLang":"Vietnamese","systemPrompt":"p","speechSourceModel":"a","speechSourceModelVietnamese":"b","speechSourceModelChinese":"c","speechTargetModel":"d","hotkey":{"key":"D","option":true,"command":false,"control":false,"shift":false},"ui":{"width":480,"height":320,"autoCopy":false}}
        """
        let outcome = AppConfig.decodeOutcome(data: Data(json.utf8))
        guard case let .loaded(config) = outcome else {
            Issue.record("Expected loaded outcome")
            return
        }
        #expect(config.ui.simulateCopy == false)
    }

    @Test func appConfigSeedCreatesMissingFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntranslate-seed-\(UUID().uuidString)", isDirectory: true)
        let path = dir.appendingPathComponent("config.json").path
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(AppConfig.seedConfigFileIfMissing(at: path) == .created)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(AppConfig.seedConfigFileIfMissing(at: path) == .alreadyExists)

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(decoded.apiBaseURL == AppConfig.default.apiBaseURL)
        #expect(decoded.apiKey.isEmpty)
    }

    @Test func appConfigLoadOutcomeSeedsMissingFileThenLoads() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntranslate-load-\(UUID().uuidString)", isDirectory: true)
        let path = dir.appendingPathComponent("config.json").path
        defer { try? FileManager.default.removeItem(at: dir) }

        let outcome = AppConfig.loadOutcome(at: path)
        guard case let .seeded(config) = outcome else {
            Issue.record("Expected seeded outcome, got \(outcome)")
            return
        }
        #expect(outcome.didSeedConfig)
        #expect(config.model == AppConfig.default.model)
        #expect(FileManager.default.fileExists(atPath: path))

        let second = AppConfig.loadOutcome(at: path)
        guard case .loaded = second else {
            Issue.record("Expected loaded outcome on second read")
            return
        }
        #expect(!second.didSeedConfig)
    }

    @Test func appConfigEncodePrettyJSONDoesNotEscapeSlashes() throws {
        let data = try AppConfig.encodePrettyJSON()
        let text = String(data: data, encoding: .utf8) ?? ""
        #expect(text.contains("http://localhost:20128/v1/chat/completions"))
        #expect(!text.contains("http:\\/\\/"))
    }

    @Test func appConfigBackfillsHistoryDirectoryIfMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("config.json").path

        let jsonWithoutHistoryDir = """
        {
          "apiBaseURL": "http://localhost:20128/v1/chat/completions",
          "apiSpeechURL": "http://localhost:20128/v1/audio/speech",
          "apiKey": "test",
          "model": "test",
          "sourceLang": "Auto detect",
          "targetLang": "Vietnamese",
          "nativeLang": "Vietnamese",
          "languages": ["Auto detect", "English"],
          "targetLanguages": ["English", "Vietnamese"],
          "maxTranslateLength": 5000,
          "systemPrompt": "test",
          "learnPrompt": "test",
          "sentenceLearnPrompt": "test",
          "grammarPrompt": "test",
          "autoPrefetchSpeech": false,
          "speechSourceModel": "test",
          "speechSourceModelVietnamese": "test",
          "speechSourceModelChinese": "test",
          "speechTargetModel": "test",
          "hotkey": { "key": "D", "option": true, "command": false, "control": false, "shift": false },
          "ui": { "width": 630, "height": 320, "autoCopy": false, "simulateCopy": false }
        }
        """
        try Data(jsonWithoutHistoryDir.utf8).write(to: URL(fileURLWithPath: path))

        let outcome = AppConfig.loadOutcome(at: path)
        guard case let .loaded(config) = outcome else {
            Issue.record("Expected loaded outcome")
            return
        }
        #expect(config.historyDirectory == "")

        let updatedData = try Data(contentsOf: URL(fileURLWithPath: path))
        let updatedText = String(data: updatedData, encoding: .utf8) ?? ""
        #expect(updatedText.contains("\"historyDirectory\""))
    }

    @Test func appConfigSetupIssuesReportsEmptyApiKeyAndAccessibility() {
        var config = AppConfig.default
        config.apiKey = ""
        let issues = config.setupIssues(accessibilityTrusted: false)
        #expect(issues.contains(where: { $0.contains("apiKey is empty") }))
        #expect(issues.contains(where: { $0.contains("Accessibility") }))
        #expect(AppConfig.formatSetupIssues(issues).hasPrefix("Error:"))
    }

    @Test func appConfigSetupIssuesEmptyWhenReady() {
        var config = AppConfig.default
        config.apiKey = "sk-test"
        #expect(config.setupIssues(accessibilityTrusted: true).isEmpty)
    }

    @Test func popoverFeedbackTreatsSetupErrorsAsErrorStyle() {
        #expect(PopoverFeedback.resultStyle(for: "Error: apiKey is empty") == .error)
        #expect(PopoverFeedback.resultStyle(for: "Config load error: boom") == .error)
        #expect(!PopoverFeedback.isCopyableResult("Error: apiKey is empty"))
    }

    @Test func popoverLayoutMathClampsInputHeight() {
        let height = PopoverLayoutMath.inputHeight(
            text: String(repeating: "hello ", count: 200),
            font: .systemFont(ofSize: 13),
            inset: NSSize(width: 4, height: 4),
            lineFragmentPadding: 5,
            minHeight: 30,
            maxHeight: 74,
            width: 100
        )
        #expect(height == 74)
    }

    @Test func popoverLayoutMathMeasuresEmptyText() {
        let height = PopoverLayoutMath.measuredTextHeight(NSAttributedString(string: ""), width: 200)
        #expect(height > 0)
    }

    @Test func splitPaneWidthDividesEvenlyWithOddRemainderToRight() {
        let panes = PopoverLayoutMath.splitPaneWidth(contentWidth: 464, divider: 1)
        #expect(panes.left == 231)
        #expect(panes.right == 232)
        #expect(panes.left + panes.right + 1 == 464)
    }

    @Test func splitPaneHeightClampsBetweenMinAndMax() {
        let clampedLow = PopoverLayoutMath.splitPaneHeight(
            sourceMeasured: 10,
            resultMeasured: 20,
            paneHeaderHeight: 26,
            minPaneHeight: 200,
            maxPaneHeight: 420
        )
        #expect(clampedLow == 200)

        let clampedHigh = PopoverLayoutMath.splitPaneHeight(
            sourceMeasured: 1000,
            resultMeasured: 1000,
            paneHeaderHeight: 26,
            minPaneHeight: 200,
            maxPaneHeight: 420
        )
        #expect(clampedHigh == 420)

        let mid = PopoverLayoutMath.splitPaneHeight(
            sourceMeasured: 100,
            resultMeasured: 180,
            paneHeaderHeight: 26,
            minPaneHeight: 200,
            maxPaneHeight: 420
        )
        #expect(mid == 206)
    }

    @Test func splitPrismHeightSumsChromeAndPane() {
        let height = PopoverLayoutMath.splitPrismHeight(
            padding: 14,
            paddingBottom: 16,
            headerHeight: 22,
            statusHeight: 0,
            headerGap: 12,
            splitPaneHeight: 160,
            footerGap: 16,
            bottomBarHeight: 32
        )
        // 14 + 22 + 0 + 12 + 160 + 16 + 32 + 16
        #expect(height == 272)
    }

    @Test func splitPrismHeightIncludesStatusWhenPresent() {
        let height = PopoverLayoutMath.splitPrismHeight(
            padding: 14,
            paddingBottom: 16,
            headerHeight: 22,
            statusHeight: 14,
            headerGap: 12,
            splitPaneHeight: 160,
            footerGap: 16,
            bottomBarHeight: 32
        )
        #expect(height == 286)
    }

    @Test func clickIsInsidePanelRecognizesInsideAndOutsidePoints() {
        let frame = NSRect(x: 100, y: 100, width: 200, height: 100)
        #expect(PopoverLayoutMath.clickIsInsidePanel(click: NSPoint(x: 150, y: 150), panelFrame: frame))
        #expect(!PopoverLayoutMath.clickIsInsidePanel(click: NSPoint(x: 50, y: 50), panelFrame: frame))
    }

    @Test func nonTextSelectionDetectedWhenRangeExistsButTextEmpty() {
        #expect(SelectionReader.isNonTextSelection(text: nil, selectedRangeLength: 1, role: nil))
        #expect(!SelectionReader.isNonTextSelection(text: "hello", selectedRangeLength: 1, role: nil))
    }

    @Test func nonTextSelectionDetectedForImageRole() {
        #expect(SelectionReader.isNonTextSelection(text: nil, selectedRangeLength: nil, role: "AXImage"))
    }

    @Test func selectionReadFailureIncludesAttributeAndTypes() {
        let error = SelectionReadFailure.unexpectedValue(attribute: "AXFocusedUIElement", expected: "AXUIElement", actual: "String")
        #expect(error.description == "Accessibility read failed at AXFocusedUIElement: expected AXUIElement, got String")
    }

    @Test func clipboardImageWinsOverTextAndTextFallbackIsTrimmed() throws {
        let pasteboard = NSPasteboard(name: .init("NTranslateTests.clipboardPriority"))
        let item = NSPasteboardItem()
        item.setData(try testPNG(), forType: .png)
        item.setString("  fallback text  ", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        guard case let .image(image) = try SelectionReader.translatableInput(from: pasteboard) else {
            Issue.record("Expected image input")
            return
        }
        #expect(image.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        pasteboard.clearContents()
        pasteboard.setString("  fallback text\n", forType: .string)
        #expect(try SelectionReader.translatableInput(from: pasteboard) == .text("fallback text"))
    }

    @Test func clipboardTriesEveryAdvertisedRasterBeforeFailing() throws {
        let pasteboard = NSPasteboard(name: .init("NTranslateTests.clipboardRasterFallback"))
        let item = NSPasteboardItem()
        item.setData(Data("invalid png".utf8), forType: .png)
        item.setData(try testTIFF(), forType: .tiff)
        item.setString("text must not win", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        guard case let .image(image) = try SelectionReader.translatableInput(from: pasteboard) else {
            Issue.record("Expected TIFF fallback image")
            return
        }
        #expect(image.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func normalizedPNGHasSignatureAndEnforcesEncodedLimit() throws {
        let source = try testPNG()
        let normalized = try SelectionReader.normalizedPNG(from: source)
        #expect(normalized.starts(with: [0x89, 0x50, 0x4E, 0x47]))

        let limit = 8
        #expect(try SelectionReader.normalizedPNG(from: source, maximumBytes: limit) { _ in Data(count: limit) }.count == limit)
        #expect(throws: ImageInputError.self) {
            try SelectionReader.normalizedPNG(from: source, maximumBytes: limit) { _ in Data(count: limit + 1) }
        }
        #expect(throws: ImageInputError.self) {
            try SelectionReader.normalizedPNG(from: source) { _ in nil }
        }
    }

    @Test func decodedImageSizeLimitIsOverflowSafe() {
        #expect(SelectionReader.decodedRasterByteCount(width: 5_000, height: 5_000) == 100_000_000)
        #expect(SelectionReader.decodedRasterByteCount(width: UInt64.max, height: 2) == nil)
        #expect(SelectionReader.isDecodedRasterWithinLimit(width: 5_120, height: 5_120))
        #expect(!SelectionReader.isDecodedRasterWithinLimit(width: 5_121, height: 5_120))
        #expect(!SelectionReader.isDecodedRasterWithinLimit(width: UInt64.max, height: UInt64.max))
    }

    @Test func simulatedCopyRestoresClipboardAfterSuccessfulAndFailedParsing() throws {
        let pasteboard = NSPasteboard(name: .init("NTranslateTests.clipboardRestore"))
        pasteboard.clearContents()
        pasteboard.setString("original", forType: .string)

        let input = try SelectionReader.simulatedCopyInput(from: pasteboard) { _ in
            pasteboard.clearContents()
            pasteboard.setString(" copied ", forType: .string)
            return true
        }
        #expect(input == .text("copied"))
        #expect(pasteboard.string(forType: .string) == "original")

        #expect(try SelectionReader.simulatedCopyInput(from: pasteboard) { _ in false } == nil)
        #expect(pasteboard.string(forType: .string) == "original")

        #expect(throws: ImageInputError.self) {
            try SelectionReader.simulatedCopyInput(from: pasteboard) { _ in
                pasteboard.clearContents()
                pasteboard.setData(Data("invalid".utf8), forType: .png)
                return true
            }
        }
        #expect(pasteboard.string(forType: .string) == "original")
    }

    @Test func translatorTextPayloadKeepsStringContent() throws {
        let data = try Translator.requestPayload(model: "model", systemPrompt: "system", userContent: "<selected-text>hello</selected-text>")
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages[1]["content"] as? String == "<selected-text>hello</selected-text>")
    }

    @Test func translatorImagePayloadUsesOrderedTextAndImageParts() throws {
        var config = AppConfig.default
        config.sourceLang = "English"
        config.systemPrompt = "Translate from {{config.sourceLang}} to {{config.targetLang}}."
        let data = try Translator.imageRequestPayload(
            pngData: Data([0x00, 0xFF]),
            targetLang: "Vietnamese",
            systemPrompt: Translator.imageSystemPrompt(targetLang: "Vietnamese", config: config),
            model: "model"
        )
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(json["messages"] as? [[String: Any]])
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "Translate from Auto detect to Vietnamese.")
        let content = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "text")
        #expect(content[0]["text"] as? String == "Translate all readable text in this image into Vietnamese. Return only the translation.")
        #expect(content[1]["type"] as? String == "image_url")
        let imageURL = try #require(content[1]["image_url"] as? [String: Any])
        #expect(imageURL["url"] as? String == "data:image/png;base64,AP8=")
        #expect(imageURL["detail"] == nil)
    }

    @Test func translatorResponseContentTrimsValidContentAndRejectsInvalidContent() throws {
        let valid = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": "  xin chào \n"]]]
        ])
        #expect(try Translator.responseContent(from: valid) == "xin chào")

        let empty = try JSONSerialization.data(withJSONObject: [
            "choices": [["message": ["content": " \n"]]]
        ])
        #expect(throws: Translator.ResponseError.self) { try Translator.responseContent(from: empty) }
        #expect(throws: Translator.ResponseError.self) { try Translator.responseContent(from: Data("{}".utf8)) }
        #expect(throws: Translator.ResponseError.self) { try Translator.responseContent(from: Data("invalid".utf8)) }
    }

    private func testPNG() throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.setColor(.systemRed, atX: 0, y: 0)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }

    private func testTIFF() throws -> Data {
        try #require(NSBitmapImageRep(data: testPNG())?.tiffRepresentation)
    }

    @Test func popoverIntegrationPolicyDisablesImageOnlyControls() {
        #expect(!PopoverIntegrationPolicy.sourceControlsEnabled(hasPendingImage: true))
        #expect(PopoverIntegrationPolicy.sourceControlsEnabled(hasPendingImage: false))
    }

    @Test func popoverIntegrationPolicyRequiresUnchangedCurrentRecord() {
        let id = UUID()
        #expect(PopoverIntegrationPolicy.canSave(recordID: id, sourceText: "hello", currentSourceText: "hello", resultText: "xin chào", currentResultText: "xin chào"))
        #expect(!PopoverIntegrationPolicy.canSave(recordID: id, sourceText: "hello", currentSourceText: "changed", resultText: "xin chào", currentResultText: "xin chào"))
        #expect(!PopoverIntegrationPolicy.canSave(recordID: nil, sourceText: "hello", currentSourceText: "hello", resultText: "xin chào", currentResultText: "xin chào"))
    }

    @Test func popoverIntegrationPolicyPrefetchesOnlyValidTextRequests() {
        #expect(PopoverIntegrationPolicy.shouldPrefetchSource(enabled: true, hasPendingImage: false, text: " hello "))
        #expect(!PopoverIntegrationPolicy.shouldPrefetchSource(enabled: false, hasPendingImage: false, text: "hello"))
        #expect(!PopoverIntegrationPolicy.shouldPrefetchSource(enabled: true, hasPendingImage: true, text: "hello"))
        #expect(!PopoverIntegrationPolicy.shouldPrefetchSource(enabled: true, hasPendingImage: false, text: "  "))
    }

    @Test func popoverAsyncPoliciesRejectInvalidatedRequestsAndStalePrefetches() {
        var generation = AsyncGeneration()
        let request = generation.advance()
        #expect(generation.accepts(request))
        generation.invalidate()
        #expect(!generation.accepts(request))
        #expect(!PopoverIntegrationPolicy.acceptsPrefetch(translationGeneration: request, currentGeneration: generation.current))
    }

    @Test func popoverAsyncPolicyAttachesAudioToExactRecordIdentity() {
        let first = UUID()
        let second = UUID()
        let identity = SpeechIdentity(kind: .source, text: "hello", model: "tts")
        #expect(PopoverIntegrationPolicy.recordedSpeechIdentity(identity, translationGeneration: 7, currentGeneration: 7, recordID: first)?.recordID == first)
        #expect(PopoverIntegrationPolicy.recordedSpeechIdentity(identity, translationGeneration: 6, currentGeneration: 7, recordID: first) == nil)
        #expect(PopoverIntegrationPolicy.canAttachAudio(identity: SpeechIdentity(kind: .source, text: "hello", model: "tts", recordID: first), currentRecordID: second) == false)
    }

    @Test func invalidSuccessfulSpeechResponseIsNotCacheable() {
        #expect(!SpeechAudioPolicy.isValid(Data("not audio".utf8)))
        #expect(SpeechAudioPolicy.isValid(Data([1])) { _ in })
        #expect(!SpeechAudioPolicy.isValid(Data([1])) { _ in throw CocoaError(.fileReadCorruptFile) })
    }

    @Test func speechPlaybackStateTransitions() {
        let source = SpeechIdentity(kind: .source, text: "hello", model: "tts-1")
        var state = SpeechPlaybackState()

        #expect(state.action(for: source) == .play)
        let generation = state.beginLoading(source)
        #expect(state.action(for: source) == .loading)
        #expect(state.action(for: SpeechIdentity(kind: .result, text: "other", model: "tts-1")) == .play)
        #expect(state.accepts(generation: generation, identity: source))
        let markedPlaying = state.markPlaying(generation: generation, identity: source)
        #expect(markedPlaying)
        #expect(state.action(for: source) == .pause)
        let paused = state.pause(source)
        #expect(paused)
        #expect(state.action(for: source) == .resume)
        let resumed = state.resume(source)
        #expect(resumed)
        #expect(state.action(for: source) == .pause)

        state.invalidateRequests()
        let markedPlayingAfterInvalidate = state.markPlaying(generation: generation, identity: source)
        #expect(!markedPlayingAfterInvalidate)
        state.reset()
        #expect(state.action(for: source) == .play)
    }

    @Test func speechPlaybackStateKeepsPlaybackIdentity() {
        let source = SpeechIdentity(kind: .source, text: "hello", model: "tts-1")
        let result = SpeechIdentity(kind: .result, text: "xin chào", model: "tts-2", recordID: UUID())
        var state = SpeechPlaybackState()

        state.beginPlaying(source)
        #expect(state.action(for: source) == .pause)
        #expect(state.action(for: result) == .play)
        let pausedWrongIdentity = state.pause(result)
        #expect(!pausedWrongIdentity)
        let resumedWhilePlaying = state.resume(source)
        #expect(!resumedWhilePlaying)

        state.beginPlaying(result)
        #expect(state.action(for: source) == .play)
        #expect(state.action(for: result) == .pause)
    }

    @Test func speechPlaybackStateRejectsStaleLoadingCompletion() {
        let old = SpeechIdentity(kind: .result, text: "same", model: "tts", recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let current = SpeechIdentity(kind: .result, text: "same", model: "tts", recordID: UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        var state = SpeechPlaybackState()

        let oldGeneration = state.beginLoading(old)
        let currentGeneration = state.beginLoading(current)
        #expect(!state.accepts(generation: oldGeneration, identity: old))
        let finishedStaleLoading = state.finishLoading(generation: oldGeneration, identity: old)
        #expect(!finishedStaleLoading)
        #expect(state.action(for: old) == .play)
        #expect(state.action(for: current) == .loading)
        let finishedCurrentLoading = state.finishLoading(generation: currentGeneration, identity: current)
        #expect(finishedCurrentLoading)
        #expect(state.action(for: current) == .play)
    }

    @Test func speechModelResolverUsesTargetLanguage() {
        let config = AppConfig.default
        #expect(SpeechModelResolver.model(for: "Vietnamese", config: config) == config.speechTargetModel)
        #expect(SpeechModelResolver.model(for: "English", config: config) == config.speechSourceModel)
        #expect(SpeechModelResolver.model(for: "Chinese", config: config) == config.speechSourceModelChinese)
    }

    @Test func crashReportSummaryParsesExceptionType() {
        let data = Data("""
        {"timestamp":"2026-07-06 12:44:26.00 +0700","exception":{"type":"EXC_BAD_ACCESS"},"termination":{"namespace":"SIGNAL","indicator":"Segmentation fault: 11"}}
        {"ignored":"full report"}
        """.utf8)
        let summary = CrashRecovery.summary(fromCrashReportData: data)
        #expect(summary?.timestamp == "2026-07-06 12:44:26.00 +0700")
        #expect(summary?.exceptionType == "EXC_BAD_ACCESS")
        #expect(summary?.terminationReason == "SIGNAL: Segmentation fault: 11")
    }

    @Test func crashReportSummaryReturnsNilForInvalidData() {
        #expect(CrashRecovery.summary(fromCrashReportData: Data("not json".utf8)) == nil)
    }

    @Test func crashAlertRequiresCrashReportFile() {
        let report = URL(fileURLWithPath: "/tmp/NTranslate-2026-07-12-123456.ips")
        #expect(!CrashRecovery.shouldPresentCrashAlert(
            uncleanShutdown: true,
            crashReportURL: nil,
            acknowledgedReportName: nil
        ))
        #expect(!CrashRecovery.shouldPresentCrashAlert(
            uncleanShutdown: false,
            crashReportURL: report,
            acknowledgedReportName: nil
        ))
        #expect(CrashRecovery.shouldPresentCrashAlert(
            uncleanShutdown: true,
            crashReportURL: report,
            acknowledgedReportName: nil
        ))
        #expect(!CrashRecovery.shouldPresentCrashAlert(
            uncleanShutdown: true,
            crashReportURL: report,
            acknowledgedReportName: report.lastPathComponent
        ))
    }
}
