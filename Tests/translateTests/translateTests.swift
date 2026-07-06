import AppKit
import Testing
@testable import translate

struct TranslateTests {
    @Test func plainDisplayPreservesReadableText() {
        let rendered = NSAttributedString.plainDisplay("**Bold** and *italic*", font: .systemFont(ofSize: 13))
        #expect(rendered.string == "**Bold** and *italic*")
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

    @Test func languageDetectorSwapsToEnglishWhenSourceIsVietnamese() {
        let pair = LanguageDetector.resolvedPair(selectedSource: "Vietnamese", selectedTarget: "Vietnamese", text: "xin chào")
        #expect(pair.source == "Vietnamese")
        #expect(pair.target == "English")
    }

    @Test func languageDetectorAutoDetectsVietnameseTextAndTargetsEnglish() {
        let pair = LanguageDetector.resolvedPair(selectedSource: "Auto detect", selectedTarget: "Vietnamese", text: "xin chào các bạn")
        #expect(pair.target == "English")
    }

    @Test func languageDetectorFallsBackWhenSourceEqualsTarget() {
        let pair = LanguageDetector.resolvedPair(selectedSource: "English", selectedTarget: "English", text: "hello")
        #expect(pair.target == "Vietnamese")
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
}
