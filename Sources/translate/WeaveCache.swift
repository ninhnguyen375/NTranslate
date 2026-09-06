// Disk cache for review reading passages.
//
// A passage is generated for one exact set of words, so reopening the same review session should
// not pay for it twice. The key folds in the prompt itself, so editing the prompt retires old
// passages instead of serving them. Folding in only the app's version number was not enough: a
// config that still holds an older prompt would stamp new passages with the new version and keep
// serving text the current prompt would never produce.
import CryptoKit
import Foundation

struct WeavePassage: Codable, Sendable {
    let words: [String]
    let text: String
    let promptVersion: String
    let generatedAt: Date
    /// Set once a title has been generated for a passage whose own text carries none.
    /// Absent in files written before titles existed, which is why it is optional.
    var title: String?
    /// Set when the learner marks the passage as read. Absent in files written before Done existed.
    var isDone: Bool?
}

enum WeaveCache {
    static func cacheKey(words: [String], promptVersion: String, prompt: String = "") -> String {
        let payload = ([promptVersion, prompt] + words.map { $0.lowercased() }.sorted()).joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func directory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NTranslate", isDirectory: true)
            .appendingPathComponent("weave", isDirectory: true)
    }

    static func url(for key: String) -> URL {
        directory().appendingPathComponent("\(key).json")
    }

    /// A miss and a corrupt file are the same thing to the caller: generate it again.
    static func load(key: String) -> WeavePassage? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(WeavePassage.self, from: data)
    }

    /// Every passage still on disk, newest first, so a learner can reopen one instead of paying for
    /// a new one. Files that no longer decode are simply left out.
    static func all() -> [WeavePassage] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONDecoder().decode(WeavePassage.self, from: Data(contentsOf: $0)) }
            .sorted { $0.generatedAt > $1.generatedAt }
    }

    /// Same as `all()`, but paired with the key each passage is filed under, so a row in the
    /// list can be deleted or retitled.
    static func entries() -> [(key: String, passage: WeavePassage)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let passage = try? JSONDecoder().decode(WeavePassage.self, from: Data(contentsOf: url)) else { return nil }
                return (url.deletingPathExtension().lastPathComponent, passage)
            }
            .sorted { $0.passage.generatedAt > $1.passage.generatedAt }
    }

    static func delete(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    static func store(_ passage: WeavePassage, key: String) {
        do {
            try FileManager.default.createDirectory(at: directory(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(passage)
            try data.write(to: url(for: key), options: .atomic)
        } catch {
            // Losing the cache costs one extra request, never the passage itself.
            FileHandle.standardError.write(Data("WeaveCache: could not store passage: \(error)\n".utf8))
        }
    }
}
