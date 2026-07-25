import Foundation

struct TranslationRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let sourceText: String
    let resultText: String
    let sourceLanguage: String
    let targetLanguage: String
    var sourceAudioPath: String?
    var resultAudioPath: String?
    var isSaved: Bool
}

enum TranslationAudioKind: String, Sendable {
    case source
    case result
}

@MainActor
final class TranslationHistoryStore {
    enum StoreError: Error, LocalizedError {
        case locked(String)
        case invalidRecord
        case recordNotFound
        case invalidAudioPath(String)

        var errorDescription: String? {
            switch self {
            case let .locked(message): message
            case .invalidRecord: "Translation history records require non-empty text and languages."
            case .recordNotFound: "Translation history record was not found."
            case let .invalidAudioPath(path): "Audio path escapes the history audio directory: \(path)"
            }
        }
    }

    private let fileManager: FileManager
    let directoryURL: URL
    let historyURL: URL
    let audioDirectoryURL: URL
    private(set) var records: [TranslationRecord] = []
    private(set) var loadError: String?

    convenience init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NTranslate", isDirectory: true)
        self.init(directoryURL: base, fileManager: fileManager)
    }

    init(directoryURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL.standardizedFileURL
        historyURL = self.directoryURL.appendingPathComponent("history.json")
        audioDirectoryURL = self.directoryURL.appendingPathComponent("audio", isDirectory: true)
        load()
    }

    func append(_ record: TranslationRecord) throws {
        try ensureWritable()
        guard Self.hasContent(record.sourceText), Self.hasContent(record.resultText),
              Self.hasContent(record.sourceLanguage), Self.hasContent(record.targetLanguage)
        else { throw StoreError.invalidRecord }
        var updated = records.filter { $0.id != record.id }
        updated.append(record)
        updated.sort { $0.timestamp > $1.timestamp }
        try persist(updated)
        records = updated
    }

    func setSaved(_ isSaved: Bool, recordID: UUID) throws {
        try update(recordID: recordID) { $0.isSaved = isSaved }
    }

    func toggleSaved(recordID: UUID) throws {
        try update(recordID: recordID) { $0.isSaved.toggle() }
    }

    func attachAudio(_ data: Data, kind: TranslationAudioKind, recordID: UUID) throws {
        try ensureWritable()
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { throw StoreError.recordNotFound }
        try fileManager.createDirectory(at: audioDirectoryURL, withIntermediateDirectories: true)
        let relativePath = "audio/\(recordID.uuidString.lowercased())-\(kind.rawValue)-\(UUID().uuidString.lowercased()).audio"
        let audioURL = try containedAudioURL(for: relativePath)
        try data.write(to: audioURL, options: .atomic)

        var updated = records
        let previousPath: String?
        switch kind {
        case .source:
            previousPath = updated[index].sourceAudioPath
            updated[index].sourceAudioPath = relativePath
        case .result:
            previousPath = updated[index].resultAudioPath
            updated[index].resultAudioPath = relativePath
        }
        do {
            try persist(updated)
            records = updated
            if let previousPath, let previousURL = try? containedAudioURL(for: previousPath) {
                try? fileManager.removeItem(at: previousURL)
            }
        } catch {
            try? fileManager.removeItem(at: audioURL)
            throw error
        }
    }

    func audioExists(for recordID: UUID, kind: TranslationAudioKind) throws -> Bool {
        guard let record = records.first(where: { $0.id == recordID }) else { throw StoreError.recordNotFound }
        let path = kind == .source ? record.sourceAudioPath : record.resultAudioPath
        guard let path else { return false }
        return fileManager.fileExists(atPath: try containedAudioURL(for: path).path)
    }

    func audioData(for recordID: UUID, kind: TranslationAudioKind) throws -> Data? {
        guard let record = records.first(where: { $0.id == recordID }) else { throw StoreError.recordNotFound }
        let path = kind == .source ? record.sourceAudioPath : record.resultAudioPath
        guard let path else { return nil }
        let url = try containedAudioURL(for: path)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    private func load() {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            guard fileManager.fileExists(atPath: historyURL.path) else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([TranslationRecord].self, from: Data(contentsOf: historyURL))
            try validate(decoded)
            records = decoded.sorted { $0.timestamp > $1.timestamp }
        } catch {
            records = []
            loadError = "Could not load translation history at \(historyURL.path): \(error.localizedDescription)"
        }
    }

    private func validate(_ decoded: [TranslationRecord]) throws {
        guard Set(decoded.map(\.id)).count == decoded.count else { throw StoreError.invalidRecord }
        for record in decoded {
            guard Self.hasContent(record.sourceText), Self.hasContent(record.resultText),
                  Self.hasContent(record.sourceLanguage), Self.hasContent(record.targetLanguage)
            else { throw StoreError.invalidRecord }
            if let path = record.sourceAudioPath { _ = try containedAudioURL(for: path) }
            if let path = record.resultAudioPath { _ = try containedAudioURL(for: path) }
        }
    }

    private func update(recordID: UUID, mutation: (inout TranslationRecord) -> Void) throws {
        try ensureWritable()
        guard let index = records.firstIndex(where: { $0.id == recordID }) else { throw StoreError.recordNotFound }
        var updated = records
        mutation(&updated[index])
        try persist(updated)
        records = updated
    }

    private func persist(_ updated: [TranslationRecord]) throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updated).write(to: historyURL, options: .atomic)
    }

    private func ensureWritable() throws {
        if let loadError { throw StoreError.locked(loadError) }
    }

    private func containedAudioURL(for relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"),
              relativePath.split(separator: "/", omittingEmptySubsequences: false).first == "audio"
        else { throw StoreError.invalidAudioPath(relativePath) }
        let root = audioDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolved = directoryURL.appendingPathComponent(relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else { throw StoreError.invalidAudioPath(relativePath) }
        return resolved
    }

    private static func hasContent(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
