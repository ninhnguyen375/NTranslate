// Self-check for the passage cache following the user's history folder.
import Foundation

@MainActor
func run() {
    let fm = FileManager.default
    let legacy = fm.temporaryDirectory.appendingPathComponent("weave-legacy-\(UUID().uuidString)")
    let legacyWeave = legacy.appendingPathComponent("weave", isDirectory: true)
    let legacyAudio = legacy.appendingPathComponent("weave-audio", isDirectory: true)
    let target = fm.temporaryDirectory.appendingPathComponent("weave-check-\(UUID().uuidString)")

    defer {
        try? fm.removeItem(at: target)
        try? fm.removeItem(at: legacy)
    }

    let passage = WeavePassage(
        words: ["rival"], text: "A: hi\nB: hello", promptVersion: "1", generatedAt: Date(), title: "T", isDone: nil
    )
    try! fm.createDirectory(at: legacyWeave, withIntermediateDirectories: true)
    try! JSONEncoder().encode(passage).write(to: legacyWeave.appendingPathComponent("abc.json"))
    try! fm.createDirectory(at: legacyAudio, withIntermediateDirectories: true)
    try! Data([1, 2, 3]).write(to: legacyAudio.appendingPathComponent("old.audio"))
    try! Data("{}".utf8).write(to: legacy.appendingPathComponent("vocab-progress.json"))

    WeaveCache.prepare(historyDirectory: target, legacy: legacy)

    assert(WeaveCache.directory().path == target.appendingPathComponent("weave").path)
    assert(WeaveCache.load(key: "abc")?.text == passage.text, "legacy passage did not move")
    assert(!fm.fileExists(atPath: legacyWeave.appendingPathComponent("abc.json").path), "legacy copy left behind")
    assert(
        fm.fileExists(atPath: target.appendingPathComponent("weave-audio/old.audio").path),
        "legacy audio did not move"
    )

    assert(
        fm.fileExists(atPath: target.appendingPathComponent("vocab-progress.json").path),
        "vocab progress did not move"
    )

    // Audio is keyed by text and model, so the same line replays from disk and a different one does not.
    WeaveAudioCache.store(Data([9, 9]), text: "hello", model: "tts-1")
    assert(WeaveAudioCache.load(text: "hello", model: "tts-1") == Data([9, 9]))
    assert(WeaveAudioCache.load(text: "hello", model: "tts-2") == nil)
    assert(WeaveAudioCache.load(text: "hellO", model: "tts-1") == nil)
    assert(WeaveAudioCache.url(text: "hello", model: "tts-1").path.hasPrefix(target.path))

    print("weave-cache-check: ok")
}

@main
enum WeaveCacheCheck {
    static func main() {
        MainActor.assumeIsolated { run() }
    }
}
