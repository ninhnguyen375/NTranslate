// Self-check for LearnBadgeView parsing and stripping.
//
//   swiftc -parse-as-library Sources/translate/VocabPack.swift Sources/translate/WeaveCache.swift \
//     Sources/translate/VocabDiscovery.swift Sources/translate/LearnBadgeView.swift \
//     Scripts/learn-badge-check.swift -o /tmp/learn-badge-check && /tmp/learn-badge-check
//
import AppKit
import Foundation

private var failures = 0

private func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("ok   \(message)")
    } else {
        failures += 1
        print("FAIL \(message)")
    }
}

@main
enum LearnBadgeCheckMain {
    static func main() {
        testParseC1Low()
        testParseA1High()
        testParseB2Medium()
        testStripLine()
        testPartialStreamLine()

        if failures > 0 {
            print("\n\(failures) check(s) FAILED")
            exit(1)
        } else {
            print("\nAll checks passed.")
        }
    }

    private static func testParseC1Low() {
        let text = """
        Từ gốc: lithospheric plate
        Phiên âm: /ˌlɪθ.əˈsfɪər.ɪk pleɪt/
        Mức dùng: formal · ít gặp · C1
        n. mảng thạch quyển
        """
        guard let usage = LearnUsageInfo.parse(from: text) else {
            expect(false, "LearnUsageInfo parse failed for C1 low")
            return
        }
        expect(usage.cefr == "C1", "CEFR is C1: \(String(describing: usage.cefr))")
        expect(usage.cefrLevel == .c1, "cefrLevel is .c1")
        expect(usage.frequencyLevel == 1, "frequencyLevel is 1 (low): \(usage.frequencyLevel)")
        expect(usage.frequency == "Rare", "frequency is 'Rare'")
        expect(usage.register == "formal", "register is 'formal'")
    }

    private static func testParseA1High() {
        let text = "Mức dùng: neutral · rất phổ biến · A1"
        let usage = LearnUsageInfo.parseLine(text)
        expect(usage.cefr == "A1", "CEFR is A1")
        expect(usage.cefrLevel == .a1, "cefrLevel is .a1")
        expect(usage.frequencyLevel == 3, "frequencyLevel is 3 (high)")
        expect(usage.frequency == "Very common", "frequency is 'Very common'")
        expect(usage.register == "neutral", "register is 'neutral'")
    }

    private static func testParseB2Medium() {
        let text = "Mức dùng: thân mật · phổ biến · CEFR B2"
        let usage = LearnUsageInfo.parseLine(text)
        expect(usage.cefr == "B2", "CEFR is B2")
        expect(usage.cefrLevel == .b2, "cefrLevel is .b2")
        expect(usage.frequencyLevel == 2, "frequencyLevel is 2 (medium)")
        expect(usage.frequency == "Common", "frequency is 'Common'")
        expect(usage.register == "thân mật", "register is 'thân mật'")
    }

    /// A half-streamed usage line must not produce a badge: the values are still incomplete.
    private static func testPartialStreamLine() {
        let partial = """
        Từ gốc: lithospheric plate
        Mức dùng: formal · rất ph
        """
        expect(LearnUsageInfo.parse(from: partial) == nil, "Partial usage line is not parsed")
        expect(LearnUsageInfo.parse(from: partial + "\n") != nil, "Completed usage line is parsed")
    }

    private static func testStripLine() {
        let input = """
        Từ gốc: test
        Phiên âm: /test/
        Mức dùng: formal · ít gặp · C1
        n. thử nghiệm
        """
        let stripped = LearnUsageInfo.stripUsageLine(from: input)
        expect(!stripped.contains("Mức dùng:"), "Stripped output does not contain 'Mức dùng:'")
        expect(stripped.contains("Từ gốc: test"), "Stripped output contains 'Từ gốc: test'")
        expect(stripped.contains("n. thử nghiệm"), "Stripped output contains 'n. thử nghiệm'")
    }
}
