// Read-only lookup table of pre-generated Learn cards for common words.
//
// A pack is produced offline by `Scripts/build-vocab-pack.swift` and shipped next to the app.
// On a hit, the caller materializes the entry into the history store and then follows the
// ordinary "reused record" path, so audio, Save Word, and SRS behave exactly as before.
import Foundation

struct VocabPackEntry: Codable, Sendable {
    let w: String
    let r: String
}

struct VocabPackFile: Codable, Sendable {
    let sourceLanguage: String
    let targetLanguage: String
    var model: String?
    var generatedAt: String?
    let entries: [VocabPackEntry]
}

@MainActor
final class VocabPack {
    static let shared = VocabPack()

    static let fileName = "vocab-en-vi"

    private var loaded = false
    private var sourceLanguage = ""
    private var targetLanguage = ""
    private var index: [String: String] = [:]
    private var entries: [VocabPackEntry] = []

    /// Lowercased, whitespace-collapsed form used as the lookup key on both sides.
    nonisolated static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Search order: the copy inside the app bundle, then Application Support so a pack can be
    /// dropped in without rebuilding (this is also the path a debug build finds).
    static func packURLs() -> [URL] {
        var urls: [URL] = []
        if let bundled = Bundle.main.url(forResource: fileName, withExtension: "json") {
            urls.append(bundled)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NTranslate", isDirectory: true)
            .appendingPathComponent("\(fileName).json")
        urls.append(support)
        return urls
    }

    nonisolated static func decode(_ data: Data) throws -> VocabPackFile {
        try JSONDecoder().decode(VocabPackFile.self, from: data)
    }

    nonisolated static func buildIndex(_ file: VocabPackFile) -> [String: String] {
        var index: [String: String] = [:]
        index.reserveCapacity(file.entries.count)
        for entry in file.entries {
            let key = normalize(entry.w)
            guard !key.isEmpty, !entry.r.isEmpty else { continue }
            index[key] = entry.r
        }
        return index
    }

    /// Same rule the history store uses: the target must match exactly, and the source must
    /// match unless it was never determined.
    nonisolated static func languagesMatch(
        packSource: String,
        packTarget: String,
        requestedSource: String,
        requestedTarget: String,
        sourceIsAutoDetect: Bool
    ) -> Bool {
        guard requestedTarget == packTarget else { return false }
        return sourceIsAutoDetect || requestedSource == packSource
    }

    private struct Snapshot: Sendable {
        var sourceLanguage = ""
        var targetLanguage = ""
        var index: [String: String] = [:]
        var entries: [VocabPackEntry] = []
    }

    /// Decode + index off the main thread so the first Learn click is not paying 46 ms.
    func warm() async {
        guard !loaded else { return }
        let urls = Self.packURLs()
        let snapshot = await Task.detached(priority: .utility) {
            Self.readFromDisk(urls: urls)
        }.value
        applyIfNeeded(snapshot)
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        applyIfNeeded(Self.readFromDisk(urls: Self.packURLs()))
    }

    private func applyIfNeeded(_ snapshot: Snapshot) {
        guard !loaded else { return }
        loaded = true
        sourceLanguage = snapshot.sourceLanguage
        targetLanguage = snapshot.targetLanguage
        index = snapshot.index
        entries = snapshot.entries
    }

    nonisolated private static func readFromDisk(urls: [URL]) -> Snapshot {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let file = try decode(data)
                return Snapshot(
                    sourceLanguage: file.sourceLanguage,
                    targetLanguage: file.targetLanguage,
                    index: buildIndex(file),
                    entries: file.entries
                )
            } catch {
                // A corrupt pack must never break Learn: fall through and let the API answer.
                FileHandle.standardError.write(Data("VocabPack: ignoring \(url.lastPathComponent): \(error)\n".utf8))
            }
        }
        return Snapshot()
    }

    /// The pre-generated Learn card for `text`, or nil when the pack has no answer for this
    /// word or this language pair. `sourceIsAutoDetect` mirrors the history-store rule: an
    /// undetermined source language is allowed to match the pack's own source language.
    func lookup(
        _ text: String,
        sourceLanguage requestedSource: String,
        targetLanguage requestedTarget: String,
        sourceIsAutoDetect: Bool
    ) -> String? {
        loadIfNeeded()
        guard !index.isEmpty else { return nil }
        guard Self.languagesMatch(
            packSource: sourceLanguage,
            packTarget: targetLanguage,
            requestedSource: requestedSource,
            requestedTarget: requestedTarget,
            sourceIsAutoDetect: sourceIsAutoDetect
        ) else { return nil }
        return index[Self.normalize(text)]
    }

    /// The pack's own source language, used as the stored language when the request was auto-detect.
    var packSourceLanguage: String {
        loadIfNeeded()
        return sourceLanguage
    }

    var isEmpty: Bool {
        loadIfNeeded()
        return index.isEmpty
    }

    /// Every entry in pack order, for screens that browse the pack instead of looking one word up.
    func allEntries() -> [VocabPackEntry] {
        loadIfNeeded()
        return entries
    }
}
