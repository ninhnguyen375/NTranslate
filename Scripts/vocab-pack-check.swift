// Self-check for the Learn vocabulary pack: lookup keys, language gating, and the resume
// bookkeeping the generator relies on when a run stops halfway.
//
//   swiftc -parse-as-library Sources/translate/VocabPack.swift Scripts/VocabWork.swift \
//     Scripts/vocab-pack-check.swift -o /tmp/vocab-pack-check && /tmp/vocab-pack-check
import Foundation

@main
struct VocabPackCheck {
    static func main() {
        checkNormalization()
        checkIndexBuild()
        checkLanguageGate()
        checkWordListParsing()
        checkResumeSkipsFinishedWords()
        checkTruncatedFinalLineIsDropped()
        checkLatestLineWinsPerWord()
        checkMissingWordsReported()
        print("vocab-pack-check: all checks passed")
    }

    static func checkNormalization() {
        assert(VocabPack.normalize("  Abandon ") == "abandon")
        assert(VocabPack.normalize("Look   Forward\tTo") == "look forward to", "collapses inner whitespace")
        assert(VocabPack.normalize("   ") == "")
    }

    static func checkIndexBuild() {
        let file = VocabPackFile(
            sourceLanguage: "English",
            targetLanguage: "Vietnamese",
            model: nil,
            generatedAt: nil,
            entries: [
                VocabPackEntry(w: "Abandon", r: "card A"),
                VocabPackEntry(w: "abandon", r: "card B"),
                VocabPackEntry(w: "empty", r: ""),
                VocabPackEntry(w: "  ", r: "card C"),
            ]
        )
        let index = VocabPack.buildIndex(file)
        assert(index["abandon"] == "card B", "later entry wins for the same key")
        assert(index["empty"] == nil, "an entry with no card is dropped")
        assert(index.count == 1, "a blank headword is dropped")

        let data = try! JSONEncoder().encode(file)
        let decoded = try! VocabPack.decode(data)
        assert(decoded.entries.count == 4)
        assert(decoded.targetLanguage == "Vietnamese")
    }

    static func checkLanguageGate() {
        func gate(source: String, target: String, auto: Bool) -> Bool {
            VocabPack.languagesMatch(
                packSource: "English", packTarget: "Vietnamese",
                requestedSource: source, requestedTarget: target, sourceIsAutoDetect: auto
            )
        }
        assert(gate(source: "English", target: "Vietnamese", auto: false))
        assert(gate(source: "Auto detect", target: "Vietnamese", auto: true), "undetermined source may still match")
        assert(!gate(source: "Chinese", target: "Vietnamese", auto: false), "wrong source language")
        assert(!gate(source: "English", target: "English", auto: false), "wrong target language")
        assert(!gate(source: "Chinese", target: "English", auto: true), "auto-detect never relaxes the target")
    }

    static func checkWordListParsing() {
        let text = """
        # a comment
        the
        be,am,is,are

        The
        look forward to
        """
        let words = VocabWork.parseWordList(text)
        assert(words == ["the", "be", "look forward to"], "got \(words)")
    }

    static func checkResumeSkipsFinishedWords() {
        let lines = [
            line("the", ok: "card"),
            line("be", error: "HTTP 429"),
            line("be", error: "HTTP 429"),
        ]
        assert(VocabWork.completedWords(lines) == ["the"])
        assert(VocabWork.failureCounts(lines)["be"] == 2)
        assert(VocabWork.failureCounts(lines)["the"] == nil)
    }

    static func checkTruncatedFinalLineIsDropped() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("vocab-work-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        let good = String(data: try! JSONEncoder().encode(line("the", ok: "card")), encoding: .utf8)!
        try! (good + "\n" + #"{"w":"be","status":"ok","#).write(to: url, atomically: true, encoding: .utf8)

        let lines = WorkLog.read(url: url)
        assert(lines.count == 1, "a half-written final line is skipped, earlier lines survive")
        assert(lines[0].w == "the")
    }

    static func checkLatestLineWinsPerWord() {
        let lines = [
            line("the", ok: "old card"),
            line("be", error: "boom"),
            line("The", ok: "new card"),
            line("and", ok: ""),
        ]
        let entries = VocabWork.packEntries(lines)
        assert(entries.count == 1, "only successful, non-empty cards are packed; got \(entries.count)")
        assert(entries[0].r == "new card", "the latest line for a word wins")
    }

    static func checkMissingWordsReported() {
        let lines = [line("the", ok: "card")]
        assert(VocabWork.missingWords(list: ["the", "be", "and"], lines: lines) == ["be", "and"])
    }

    static func line(_ word: String, ok card: String? = nil, error: String? = nil) -> WorkLine {
        WorkLine(
            w: word,
            status: card != nil ? "ok" : "error",
            r: card,
            err: error,
            at: "2026-09-06T00:00:00Z",
            model: "test-model"
        )
    }
}
