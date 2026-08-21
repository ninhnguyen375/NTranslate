import Foundation

enum TranslationMode: String, Codable, Equatable, Sendable {
    case translate
    case learn
    case proofread

    var displayName: String {
        switch self {
        case .translate: "Translate"
        case .learn: "Learn"
        case .proofread: "Proofread"
        }
    }
}

enum SRSGrade: Int, Sendable {
    case again = 0 // Lại
    case hard = 1  // Khó
    case easy = 2  // Dễ
}

struct TranslationRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let mode: TranslationMode
    let sourceText: String
    let resultText: String
    let sourceLanguage: String
    let targetLanguage: String
    var sourceAudioPath: String?
    var resultAudioPath: String?
    var isSaved: Bool

    // SRS Spaced Repetition fields
    var dueDate: Date?
    var interval: Int // days
    var ease: Double

    init(
        id: UUID,
        timestamp: Date,
        mode: TranslationMode = .translate,
        sourceText: String,
        resultText: String,
        sourceLanguage: String,
        targetLanguage: String,
        sourceAudioPath: String? = nil,
        resultAudioPath: String? = nil,
        isSaved: Bool,
        dueDate: Date? = nil,
        interval: Int = 0,
        ease: Double = 2.5
    ) {
        self.id = id
        self.timestamp = timestamp
        self.mode = mode
        self.sourceText = sourceText
        self.resultText = resultText
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.sourceAudioPath = sourceAudioPath
        self.resultAudioPath = resultAudioPath
        self.isSaved = isSaved
        self.dueDate = dueDate
        self.interval = interval
        self.ease = ease
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, mode, sourceText, resultText, sourceLanguage, targetLanguage
        case sourceAudioPath, resultAudioPath, isSaved
        case dueDate, interval, ease
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        timestamp = try values.decode(Date.self, forKey: .timestamp)
        mode = values.contains(.mode)
            ? try values.decode(TranslationMode.self, forKey: .mode)
            : .translate
        sourceText = try values.decode(String.self, forKey: .sourceText)
        resultText = try values.decode(String.self, forKey: .resultText)
        sourceLanguage = try values.decode(String.self, forKey: .sourceLanguage)
        targetLanguage = try values.decode(String.self, forKey: .targetLanguage)
        sourceAudioPath = try values.decodeIfPresent(String.self, forKey: .sourceAudioPath)
        resultAudioPath = try values.decodeIfPresent(String.self, forKey: .resultAudioPath)
        isSaved = try values.decode(Bool.self, forKey: .isSaved)
        dueDate = try values.decodeIfPresent(Date.self, forKey: .dueDate)
        interval = try values.decodeIfPresent(Int.self, forKey: .interval) ?? 0
        ease = try values.decodeIfPresent(Double.self, forKey: .ease) ?? 2.5
    }

    /// SM-2 simplified algorithm: 3 levels (again: 0, hard: 1, easy: 2)
    mutating func applySRSGrade(_ grade: SRSGrade, currentDate: Date = Date(), calendar: Calendar = .current) {
        let currentEase = ease > 1.3 ? ease : 2.5
        var nextInterval: Int
        var nextEase: Double

        switch grade {
        case .again:
            nextInterval = 1
            nextEase = max(1.3, currentEase - 0.2)
        case .hard:
            nextInterval = interval <= 1 ? 2 : Int(Double(interval) * 1.2)
            nextEase = max(1.3, currentEase - 0.15)
        case .easy:
            if interval == 0 {
                nextInterval = 1
            } else if interval == 1 {
                nextInterval = 3
            } else {
                nextInterval = max(interval + 1, Int(Double(interval) * currentEase))
            }
            nextEase = currentEase + 0.1
        }

        self.interval = nextInterval
        self.ease = nextEase
        let startOfToday = calendar.startOfDay(for: currentDate)
        self.dueDate = calendar.date(byAdding: .day, value: nextInterval, to: startOfToday) ?? currentDate.addingTimeInterval(Double(nextInterval) * 86400)
    }
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

    convenience init(config: AppConfig, fileManager: FileManager = .default) {
        self.init(directoryURL: config.historyDirectoryURL, fileManager: fileManager)
    }

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
        try validateForMutation(record)
        var updated = records.filter { $0.id != record.id }
        updated.append(record)
        updated.sort { $0.timestamp > $1.timestamp }
        try persist(updated)
        records = updated
    }

    func reusableRecord(
        mode: TranslationMode,
        sourceText: String,
        sourceLanguage: String,
        targetLanguage: String,
        sourceIsAutoDetect: Bool
    ) -> TranslationRecord? {
        let sourceText = Self.trim(sourceText)
        return records.first {
            $0.mode == mode
                && Self.trim($0.sourceText) == sourceText
                && $0.targetLanguage == targetLanguage
                && (sourceIsAutoDetect || $0.sourceLanguage == sourceLanguage)
        }
    }

    /// Recent translations for the same language pair, newest first, used as translation context.
    func recentContext(
        sourceLanguage: String,
        targetLanguage: String,
        excludingText: String,
        limit: Int = 10
    ) -> [TranslationRecord] {
        let excluded = Self.trim(excludingText)
        return records.filter {
            $0.mode == .translate
                && $0.sourceLanguage == sourceLanguage
                && $0.targetLanguage == targetLanguage
                && Self.trim($0.sourceText) != excluded
        }.prefix(limit).map { $0 }
    }

    @discardableResult
    func appendIfAbsent(_ record: TranslationRecord) throws -> TranslationRecord {
        try validateForMutation(record)
        if let existing = reusableRecord(
            mode: record.mode,
            sourceText: record.sourceText,
            sourceLanguage: record.sourceLanguage,
            targetLanguage: record.targetLanguage,
            sourceIsAutoDetect: false
        ) {
            return existing
        }
        try append(record)
        return record
    }

    func setSaved(_ isSaved: Bool, recordID: UUID) throws {
        try update(recordID: recordID) { record in
            record.isSaved = isSaved
            if isSaved && record.dueDate == nil {
                record.dueDate = Date()
                record.interval = 0
                record.ease = 2.5
            }
        }
    }

    func toggleSaved(recordID: UUID) throws {
        try update(recordID: recordID) { record in
            record.isSaved.toggle()
            if record.isSaved && record.dueDate == nil {
                record.dueDate = Date()
                record.interval = 0
                record.ease = 2.5
            }
        }
    }

    func updateSRS(recordID: UUID, grade: SRSGrade, currentDate: Date = Date(), calendar: Calendar = .current) throws {
        try update(recordID: recordID) { record in
            record.applySRSGrade(grade, currentDate: currentDate, calendar: calendar)
        }
    }

    func dueReviews(currentDate: Date = Date(), calendar: Calendar = .current) -> [TranslationRecord] {
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentDate) ?? currentDate
        return records.filter { record in
            guard record.isSaved else { return false }
            guard let due = record.dueDate else { return true } // saved without due date is due immediately
            return due <= endOfToday
        }
    }

    struct LearningStats: Sendable {
        let totalSaved: Int
        let totalMastered: Int // interval >= 21 days
        let dayStreak: Int
        let dueCount: Int
    }

    func computeStats(currentDate: Date = Date(), calendar: Calendar = .current) -> LearningStats {
        let saved = records.filter { $0.isSaved }
        let mastered = saved.filter { $0.interval >= 21 }
        let due = dueReviews(currentDate: currentDate, calendar: calendar).count

        // Streak calculation based on translation timestamp days
        var activeDays = Set<Date>()
        for record in records {
            let dayStart = calendar.startOfDay(for: record.timestamp)
            activeDays.insert(dayStart)
        }

        var streak = 0
        var checkDay = calendar.startOfDay(for: currentDate)
        // If not active today yet, check if active yesterday to continue streak
        if !activeDays.contains(checkDay) {
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: checkDay), activeDays.contains(yesterday) {
                checkDay = yesterday
            }
        }

        while activeDays.contains(checkDay) {
            streak += 1
            guard let prevDay = calendar.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = prevDay
        }

        return LearningStats(
            totalSaved: saved.count,
            totalMastered: mastered.count,
            dayStreak: streak,
            dueCount: due
        )
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

    private func validateForMutation(_ record: TranslationRecord) throws {
        try ensureWritable()
        guard Self.hasContent(record.sourceText), Self.hasContent(record.resultText),
              Self.hasContent(record.sourceLanguage), Self.hasContent(record.targetLanguage)
        else { throw StoreError.invalidRecord }
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasContent(_ text: String) -> Bool {
        !trim(text).isEmpty
    }

    func remove(recordID: UUID) throws {
        try remove(recordIDs: [recordID])
    }

    func remove(recordIDs: Set<UUID>) throws {
        try ensureWritable()
        let count = records.count
        let updated = records.filter { !recordIDs.contains($0.id) }
        guard updated.count < count else { throw StoreError.recordNotFound }
        
        let removed = records.filter { recordIDs.contains($0.id) }
        try persist(updated)
        records = updated
        
        for record in removed {
            if let path = record.sourceAudioPath, let url = try? containedAudioURL(for: path) {
                try? fileManager.removeItem(at: url)
            }
            if let path = record.resultAudioPath, let url = try? containedAudioURL(for: path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }
}
