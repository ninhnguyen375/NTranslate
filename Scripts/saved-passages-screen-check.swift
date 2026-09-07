// Self-check for saved passages screen data parsing and mutations.
import Foundation
import AppKit

@MainActor
func run() {
    // 1. CustomDialogueDialog.parseWords verification
    let input1 = "negotiation, contract; deadline\nclause,   dispute, negotiation"
    let parsed1 = CustomDialogueDialog.parseWords(input1)
    assert(parsed1 == ["negotiation", "contract", "deadline", "clause", "dispute"], "failed parse words with punctuation and duplicates: \(parsed1)")

    let input2 = ",,,  ... !?  "
    let parsed2 = CustomDialogueDialog.parseWords(input2)
    assert(parsed2.isEmpty, "punctuation-only input must yield empty words")

    let input3 = (1...20).map { "word\($0)" }.joined(separator: ", ")
    let parsed3 = CustomDialogueDialog.parseWords(input3)
    assert(parsed3.count == 15, "words count must be capped at 15")

    // 2. WeavePassage mutations and round-trip
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory.appendingPathComponent("passages-check-\(UUID().uuidString)")
    defer { try? fm.removeItem(at: tempDir) }

    WeaveCache.prepare(historyDirectory: tempDir)
    let key = "test-passage-key"
    var passage = WeavePassage(
        words: ["contract", "deadline"],
        text: "Topic: Project talk\nA: Sign the contract.\nB: The deadline is tomorrow.",
        promptVersion: "1",
        generatedAt: Date(),
        title: "Contract Deadline",
        isDone: false
    )
    WeaveCache.store(passage, key: key)

    let loaded = WeaveCache.load(key: key)
    assert(loaded != nil, "stored passage must be loadable")
    assert(loaded?.isDone == false, "initial isDone must be false")
    assert(loaded?.words == ["contract", "deadline"])

    // Toggle Done
    passage.isDone = true
    WeaveCache.store(passage, key: key)
    let updated = WeaveCache.load(key: key)
    assert(updated?.isDone == true, "updated isDone must be true")

    // Delete
    WeaveCache.delete(key: key)
    assert(WeaveCache.load(key: key) == nil, "deleted passage must not exist in cache")

    print("saved-passages-screen-check: ok")
}

@main
enum SavedPassagesScreenCheck {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}

