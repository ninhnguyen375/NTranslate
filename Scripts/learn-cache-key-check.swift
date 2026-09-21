// Standalone check: a Learn card is keyed by term + languages + mode, not by the sentence it was
// met in. See CLAUDE.md, `swift test` cannot run in this toolchain.
// Run it with `./Scripts/check-all.sh`, which owns the file list it compiles against.
import Foundation

/// AppConfig drags in AppKit and the prompt files; the convenience init only reads this property.
struct AppConfig {
    var historyDirectoryURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
}

private var failures = 0

private func expect(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

private func record(_ sourceText: String, mode: TranslationMode = .learn, target: String = "Vietnamese") -> TranslationRecord {
    TranslationRecord(
        id: UUID(),
        timestamp: Date(),
        mode: mode,
        sourceText: sourceText,
        resultText: "x",
        sourceLanguage: "English",
        targetLanguage: target,
        isSaved: true
    )
}

@main
struct LearnCacheKeyCheck {
    static func main() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("learn-cache-key-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TranslationHistoryStore(directoryURL: dir)

        try store.append(record("abandon (context: The crew had to abandon ship.)"))

        let lookup: (String, String) -> TranslationRecord? = { text, target in
            store.reusableRecord(
                mode: .learn,
                sourceText: text,
                sourceLanguage: "English",
                targetLanguage: target,
                sourceIsAutoDetect: false
            )
        }

        expect(lookup("abandon", "Vietnamese") != nil,
               "the bare term must hit the card stored with an encounter sentence")
        expect(lookup("Abandon.", "Vietnamese") != nil,
               "case and edge punctuation must not split the key")
        expect(lookup("abandon (context: A different sentence entirely.)", "Vietnamese") != nil,
               "a new encounter of the same word must reuse the card")
        expect(lookup("The crew had to abandon ship.", "Vietnamese") != nil,
               "the original sentence must still find its card")
        expect(lookup("desert", "Vietnamese") == nil, "another word must not match")
        expect(lookup("abandon", "French") == nil, "another target language must not match")
        expect(
            store.reusableRecord(
                mode: .translate,
                sourceText: "abandon",
                sourceLanguage: "English",
                targetLanguage: "Vietnamese",
                sourceIsAutoDetect: false
            ) == nil,
            "another mode must not match"
        )

        // A second encounter must not create a second card.
        let kept = try store.appendIfAbsent(record("abandon (context: Another sentence.)"))
        expect(kept.sourceText == "abandon (context: The crew had to abandon ship.)",
               "appendIfAbsent must return the existing card, got \(kept.sourceText)")
        expect(store.records.filter { $0.mode == .learn }.count == 1,
               "one card only, got \(store.records.filter { $0.mode == .learn }.count)")

        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("learn-cache-key-check: ok")
    }
}
