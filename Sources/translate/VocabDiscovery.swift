// Browsing the shipped vocabulary pack as a deck of unseen words: which level a pack entry
// belongs to, what order the words come in, and what the learner already decided about them.
// Pure Foundation so `Scripts/vocab-discovery-check.swift` can exercise the ordering rules.
import Foundation

enum VocabDiscovery {
    /// CEFR band written into every generated card as `Mức dùng: ... · B1 ...`. Cards generated
    /// before the prompt asked for a band land in `unranked`.
    enum Level: String, CaseIterable, Sendable {
        case a1, a2, b1, b2, c1, c2, unranked

        var label: String { self == .unranked ? "Chưa gắn" : rawValue.uppercased() }
    }

    /// What the learner said about a word. `known` leaves the deck for good; `skipped` goes to
    /// the back of the queue so it stops blocking words never seen before.
    struct Progress: Codable, Equatable, Sendable {
        var known: Set<String> = []
        var skipped: Set<String> = []

        enum Decision: String, Sendable { case known, skipped }
    }

    static func level(of rendered: String) -> Level {
        guard let line = rendered.split(separator: "\n").first(where: { $0.hasPrefix("Mức dùng:") }) else {
            return .unranked
        }
        // The band is a standalone token on that line: "Mức dùng: neutral · rất phổ biến · A1".
        for part in line.split(separator: "·") {
            let token = part.trimmingCharacters(in: .whitespaces).lowercased()
            if let level = Level(rawValue: token), level != .unranked { return level }
        }
        return .unranked
    }

    /// Sort key for a word inside one level: alphabetical, so the queue is stable between runs.
    static func queue(
        entries: [VocabPackEntry],
        level: Level?,
        progress: Progress,
        inStore: Set<String> = []
    ) -> [VocabPackEntry] {
        var unseen: [(entry: VocabPackEntry, level: Level)] = []
        var skipped: [(entry: VocabPackEntry, level: Level)] = []
        for entry in entries {
            let key = VocabPack.normalize(entry.w)
            guard !key.isEmpty, !progress.known.contains(key), !inStore.contains(key) else { continue }
            let entryLevel = self.level(of: entry.r)
            if let level, entryLevel != level { continue }
            if progress.skipped.contains(key) {
                skipped.append((entry, entryLevel))
            } else {
                unseen.append((entry, entryLevel))
            }
        }
        func sort(_ items: [(entry: VocabPackEntry, level: Level)]) -> [VocabPackEntry] {
            items.sorted { lhs, rhs in
                if lhs.level != rhs.level {
                    return order(lhs.level) < order(rhs.level)
                }
                return lhs.entry.w.lowercased() < rhs.entry.w.lowercased()
            }.map(\.entry)
        }
        return sort(unseen) + sort(skipped)
    }

    /// How many words each level still has to offer, so the picker can show real numbers.
    static func remainingByLevel(
        entries: [VocabPackEntry],
        progress: Progress,
        inStore: Set<String> = []
    ) -> [Level: Int] {
        var counts: [Level: Int] = [:]
        for entry in entries {
            let key = VocabPack.normalize(entry.w)
            guard !key.isEmpty, !progress.known.contains(key), !inStore.contains(key) else { continue }
            counts[level(of: entry.r), default: 0] += 1
        }
        return counts
    }

    private static func order(_ level: Level) -> Int {
        Level.allCases.firstIndex(of: level) ?? Level.allCases.count
    }
}

/// Where the known/skipped decisions live between launches. A corrupt file is treated as an
/// empty one: losing the decisions is annoying, refusing to open the screen is worse.
@MainActor
final class VocabProgressStore {
    static let shared = VocabProgressStore()

    private struct Payload: Codable {
        var version: Int
        var known: [String]
        var skipped: [String]
    }

    private(set) var progress = VocabDiscovery.Progress()
    private var loaded = false

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NTranslate", isDirectory: true)
            .appendingPathComponent("vocab-progress.json")
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return }
        progress = VocabDiscovery.Progress(known: Set(payload.known), skipped: Set(payload.skipped))
    }

    func record(_ decision: VocabDiscovery.Progress.Decision, word: String) {
        load()
        let key = VocabPack.normalize(word)
        guard !key.isEmpty else { return }
        switch decision {
        case .known:
            progress.known.insert(key)
            progress.skipped.remove(key)
        case .skipped:
            progress.skipped.insert(key)
        }
        save()
    }

    /// A word that entered the deck no longer needs a skip marker following it around.
    func clearSkip(word: String) {
        load()
        let key = VocabPack.normalize(word)
        guard progress.skipped.remove(key) != nil else { return }
        save()
    }

    private func save() {
        let payload = Payload(version: 1, known: progress.known.sorted(), skipped: progress.skipped.sorted())
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let url = Self.fileURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // Write beside the target and swap, so a crash mid-write cannot leave a half file behind.
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent("vocab-progress.\(UUID().uuidString).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            try? data.write(to: url, options: .atomic)
        }
    }
}
