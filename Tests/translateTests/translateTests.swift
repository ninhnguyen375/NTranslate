import AppKit
import Testing
@testable import translate

struct TranslateTests {
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
