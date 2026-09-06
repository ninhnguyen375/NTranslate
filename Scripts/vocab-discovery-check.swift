// Standalone check for VocabDiscovery ordering and level parsing.
//
//   swiftc -parse-as-library Sources/translate/VocabPack.swift \
//     Sources/translate/VocabDiscovery.swift Scripts/vocab-discovery-check.swift \
//     -o /tmp/vocab-discovery-check && /tmp/vocab-discovery-check
import Foundation

private var failures = 0

private func expect(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

private func entry(_ word: String, level: String?) -> VocabPackEntry {
    let band = level.map { " · \($0)" } ?? ""
    return VocabPackEntry(
        w: word,
        r: "Từ gốc: \(word)\nPhiên âm: /x/\nMức dùng: neutral · rất phổ biến\(band)\nn. nghĩa"
    )
}

@main
struct VocabDiscoveryCheck {
    static func main() {
        expect(VocabDiscovery.level(of: entry("a", level: "A1").r) == .a1, "A1 must parse")
        expect(VocabDiscovery.level(of: entry("b", level: "C2").r) == .c2, "C2 must parse")
        expect(VocabDiscovery.level(of: entry("c", level: nil).r) == .unranked, "a missing band must read as unranked")
        expect(
            VocabDiscovery.level(of: "no usage line here") == .unranked,
            "text without the usage line must read as unranked"
        )

        let entries = [
            entry("zebra", level: "A1"),
            entry("apple", level: "B2"),
            entry("mango", level: "A1"),
            entry("known", level: "A1"),
            entry("stored", level: "A1"),
            entry("skipped", level: "A1"),
            entry("loose", level: nil)
        ]
        let progress = VocabDiscovery.Progress(known: ["known"], skipped: ["skipped"])
        let queue = VocabDiscovery.queue(entries: entries, level: nil, progress: progress, inStore: ["stored"])
        let words = queue.map(\.w)

        expect(!words.contains("known"), "a known word must leave the queue")
        expect(!words.contains("stored"), "a word already in the deck must leave the queue")
        expect(words.last == "skipped", "a skipped word must sit at the very end, got \(words)")
        expect(
            words.prefix(2) == ["mango", "zebra"],
            "A1 comes first, alphabetically inside the level, got \(words)"
        )
        expect(
            words.firstIndex(of: "apple")! < words.firstIndex(of: "loose")!,
            "B2 must come before unranked, got \(words)"
        )

        let a1 = VocabDiscovery.queue(entries: entries, level: .a1, progress: progress, inStore: ["stored"]).map(\.w)
        expect(a1 == ["mango", "zebra", "skipped"], "filtering by level keeps the skip-last rule, got \(a1)")

        let counts = VocabDiscovery.remainingByLevel(entries: entries, progress: progress, inStore: ["stored"])
        expect(counts[.a1] == 3, "A1 has zebra, mango and skipped left, got \(counts[.a1] ?? -1)")
        expect(counts[.b2] == 1, "B2 has apple left, got \(counts[.b2] ?? -1)")
        expect(counts[.unranked] == 1, "one unranked word left, got \(counts[.unranked] ?? -1)")

        if failures == 0 {
            print("vocab-discovery-check: all checks passed")
        } else {
            FileHandle.standardError.write(Data("vocab-discovery-check: \(failures) failure(s)\n".utf8))
            exit(1)
        }
    }
}
