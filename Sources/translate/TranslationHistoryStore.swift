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
    var updatedAt: Date
    var deletedAt: Date?
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
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
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
        self.updatedAt = updatedAt ?? timestamp
        self.deletedAt = deletedAt
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
        case id, timestamp, updatedAt, deletedAt, mode, sourceText, resultText, sourceLanguage, targetLanguage
        case sourceAudioPath, resultAudioPath, isSaved
        case dueDate, interval, ease
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        let parsedTimestamp = try values.decode(Date.self, forKey: .timestamp)
        timestamp = parsedTimestamp
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt) ?? parsedTimestamp
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
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
    let devicesDirectoryURL: URL
    let audioDirectoryURL: URL
    let deviceID: String
    private(set) var records: [TranslationRecord] = []
    private var tombstonedRecords: [TranslationRecord] = []
    private(set) var loadError: String?
    private(set) var syncWarning: String?
    private var migrationError: String?

    /// Decoded month files keyed by path, kept so a refresh only re-decodes what changed on disk.
    private struct CachedFile {
        let stamp: FileStamp
        let records: [TranslationRecord]
    }

    /// Cheap change detector for one file. Size guards against two writes landing in the same
    /// mtime second; the atomic writes here always replace the whole file, so size moves too.
    private struct FileStamp: Equatable {
        let modified: Date
        let size: Int
    }

    private var fileCache: [String: CachedFile] = [:]
    private var lastScanSignature: [String: FileStamp]?

    static func defaultDeviceID() -> String {
        let key = "syncDeviceID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let rawHost = Host.current().localizedName ?? "mac"
        let cleanHost = rawHost.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
            .lowercased()
        let prefix = cleanHost.isEmpty ? "mac" : cleanHost
        let randomSuffix = String(UUID().uuidString.prefix(6)).lowercased()
        let newID = "\(prefix)-\(randomSuffix)"
        UserDefaults.standard.set(newID, forKey: key)
        return newID
    }

    convenience init(config: AppConfig, fileManager: FileManager = .default) {
        self.init(directoryURL: config.historyDirectoryURL, fileManager: fileManager)
    }

    convenience init(fileManager: FileManager = .default) {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NTranslate", isDirectory: true)
        self.init(directoryURL: base, fileManager: fileManager)
    }

    init(directoryURL: URL, deviceID: String? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL.standardizedFileURL
        self.historyURL = self.directoryURL.appendingPathComponent("history.json")
        self.devicesDirectoryURL = self.directoryURL.appendingPathComponent("devices", isDirectory: true)
        self.audioDirectoryURL = self.directoryURL.appendingPathComponent("audio", isDirectory: true)
        self.deviceID = deviceID ?? Self.defaultDeviceID()
        migrateLegacyHistoryIfNeeded()
        load(pruning: true)
    }

    func append(_ record: TranslationRecord) throws {
        try validateForMutation(record)
        var newRecord = record
        if newRecord.updatedAt < newRecord.timestamp {
            newRecord.updatedAt = newRecord.timestamp
        }
        try persistRecordToMonthFile(newRecord)
        applyLocally(newRecord)
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
            record.updatedAt = Date()
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
            record.updatedAt = Date()
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
            record.updatedAt = currentDate
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
        guard var record = records.first(where: { $0.id == recordID }) else { throw StoreError.recordNotFound }
        try fileManager.createDirectory(at: audioDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: audioDirectoryURL.path)
        let relativePath = "audio/\(recordID.uuidString.lowercased())-\(kind.rawValue)-\(UUID().uuidString.lowercased()).audio"
        let audioURL = try containedAudioURL(for: relativePath)
        try data.write(to: audioURL, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: audioURL.path)

        let previousPath: String?
        switch kind {
        case .source:
            previousPath = record.sourceAudioPath
            record.sourceAudioPath = relativePath
        case .result:
            previousPath = record.resultAudioPath
            record.resultAudioPath = relativePath
        }
        record.updatedAt = Date()

        do {
            try persistRecordToMonthFile(record)
            applyLocally(record)
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

    func refresh() {
        load(pruning: false)
    }

    /// Applies a record we just wrote to disk without rescanning every device file.
    private func applyLocally(_ record: TranslationRecord) {
        records.removeAll { $0.id == record.id }
        tombstonedRecords.removeAll { $0.id == record.id }
        if record.deletedAt == nil {
            records.append(record)
            records.sort(by: Self.newestFirst)
        } else {
            tombstonedRecords.append(record)
        }
    }

    private static func newestFirst(_ lhs: TranslationRecord, _ rhs: TranslationRecord) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    func monthKey(_ date: Date) -> String {
        Self.monthFormatter.string(from: date)
    }

    /// Merges multiple groups of records (e.g. from different devices/files).
    /// Same record id resolves to highest updatedAt. Tie resolved deterministically by deviceID / stable criteria.
    func merge(_ groups: [[TranslationRecord]]) -> [TranslationRecord] {
        mergeWithDeviceIDs(groups.map { ($0, "") })
    }

    private struct DeviceRecordItem {
        let record: TranslationRecord
        let deviceID: String
    }

    func mergeWithDeviceIDs(_ groups: [([TranslationRecord], String)]) -> [TranslationRecord] {
        var itemsByID: [UUID: [DeviceRecordItem]] = [:]
        for (records, deviceID) in groups {
            for record in records {
                itemsByID[record.id, default: []].append(DeviceRecordItem(record: record, deviceID: deviceID))
            }
        }

        var merged: [TranslationRecord] = []
        for (_, items) in itemsByID {
            guard let winning = items.max(by: { lhs, rhs in
                if lhs.record.updatedAt != rhs.record.updatedAt {
                    return lhs.record.updatedAt < rhs.record.updatedAt
                }
                if lhs.deviceID != rhs.deviceID {
                    return lhs.deviceID > rhs.deviceID
                }
                // Same device, same updatedAt: pick by content so every machine agrees.
                return lhs.record.resultText > rhs.record.resultText
            }) else { continue }
            merged.append(winning.record)
        }

        return merged
    }

    private static func stamp(of fileURL: URL) -> FileStamp? {
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modified = values.contentModificationDate,
              let size = values.fileSize
        else { return nil }
        return FileStamp(modified: modified, size: size)
    }

    private static func isMonthFileName(_ name: String) -> Bool {
        // Must match YYYY-MM.json exactly
        guard name.hasSuffix(".json"), name.count == 12 else { return false }
        let parts = name.dropLast(5).split(separator: "-")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 2 else { return false }
        return parts[0].allSatisfy(\.isNumber) && parts[1].allSatisfy(\.isNumber)
    }

    // ponytail: load() holds all records in memory (~48MB for 90k records). If RAM becomes an issue, upgrade to lazy loading the last 3 months only.
    // ponytail: pruning re-reads every own month file, so only do it at startup.
    private func load(pruning: Bool) {
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let deviceFolder = devicesDirectoryURL.appendingPathComponent(deviceID, isDirectory: true)
            try fileManager.createDirectory(at: deviceFolder, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directoryURL.path)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: devicesDirectoryURL.path)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deviceFolder.path)
        } catch {
            loadError = "Could not initialize directory: \(error.localizedDescription)"
            return
        }

        var groups: [([TranslationRecord], String)] = []
        var detectedError: String?
        var detectedWarning: String?

        guard let deviceDirs = try? fileManager.contentsOfDirectory(at: devicesDirectoryURL, includingPropertiesForKeys: nil) else {
            loadError = "Could not read history devices folder at \(devicesDirectoryURL.path)"
            return
        }

        var unreadableFile = false
        var scanSignature: [String: FileStamp] = [:]
        var nextCache: [String: CachedFile] = [:]

        for deviceDir in deviceDirs {
            if deviceDir.lastPathComponent.hasPrefix(".") { continue }
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: deviceDir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let devID = deviceDir.lastPathComponent
            guard let monthFiles = try? fileManager.contentsOfDirectory(at: deviceDir, includingPropertiesForKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .isUbiquitousItemKey,
                .contentModificationDateKey,
                .fileSizeKey
            ]) else {
                unreadableFile = true
                continue
            }

            for fileURL in monthFiles {
                let filename = fileURL.lastPathComponent
                if filename.hasSuffix(".icloud") {
                    try? fileManager.startDownloadingUbiquitousItem(at: fileURL)
                    detectedWarning = "Some history files are in iCloud Drive and downloading in background."
                    unreadableFile = true
                    continue
                }

                guard Self.isMonthFileName(filename) else { continue }

                if let resourceValues = try? fileURL.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]) {
                    if resourceValues.isUbiquitousItem == true && resourceValues.ubiquitousItemDownloadingStatus != .current {
                        try? fileManager.startDownloadingUbiquitousItem(at: fileURL)
                        detectedWarning = "Some history files are in iCloud Drive and downloading in background."
                        unreadableFile = true
                        continue
                    }
                }

                let path = fileURL.path
                let stamp = Self.stamp(of: fileURL)
                if let stamp { scanSignature[path] = stamp }

                // Unchanged since the last scan: reuse the decoded records, skip the read.
                if let stamp, let cached = fileCache[path], cached.stamp == stamp {
                    groups.append((cached.records, devID))
                    nextCache[path] = cached
                    continue
                }

                var fileRecords: [TranslationRecord]?
                autoreleasepool {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let decoded = try decoder.decode([TranslationRecord].self, from: data)
                        try validate(decoded)
                        fileRecords = decoded
                    } catch {
                        detectedError = "Could not load history file \(fileURL.lastPathComponent): \(error.localizedDescription)"
                        unreadableFile = true
                    }
                }
                if let fileRecords {
                    groups.append((fileRecords, devID))
                    if let stamp {
                        nextCache[path] = CachedFile(stamp: stamp, records: fileRecords)
                    }
                }
            }
        }

        fileCache = nextCache

        // Nothing on disk moved and nothing failed to read: `records` is already correct.
        // A file that produced no stamp is excluded from the signature, so it never
        // short-circuits the merge.
        if !unreadableFile,
           scanSignature.count == groups.count,
           let lastScanSignature,
           lastScanSignature == scanSignature {
            loadError = nil
            syncWarning = migrationError
            return
        }
        lastScanSignature = unreadableFile ? nil : scanSignature

        let allMerged = mergeWithDeviceIDs(groups)
        let now = Date()
        let oneYearAgo = now.addingTimeInterval(-365 * 24 * 3600)

        tombstonedRecords = allMerged.filter { record in
            guard let del = record.deletedAt else { return false }
            return del >= oneYearAgo
        }

        records = allMerged.filter { $0.deletedAt == nil }.sorted(by: Self.newestFirst)
        loadError = detectedError
        // Migration failure is not a lock: history.json is left untouched for recovery and
        // new records still land safely in this device's month files.
        syncWarning = migrationError ?? detectedWarning

        // Never destroy data while any device file is unreadable: the records it holds
        // are missing from `records`, so their audio would look orphaned.
        guard pruning, !unreadableFile else { return }
        pruneTombstones()
        pruneOrphanAudio()
    }

    private func migrateLegacyHistoryIfNeeded() {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }

        do {
            let data = try Data(contentsOf: historyURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([TranslationRecord].self, from: data)
            try validate(decoded)

            var monthly: [String: [TranslationRecord]] = [:]
            for record in decoded {
                let key = monthKey(record.timestamp)
                monthly[key, default: []].append(record)
            }

            let myDeviceDir = devicesDirectoryURL.appendingPathComponent(deviceID, isDirectory: true)
            try fileManager.createDirectory(at: myDeviceDir, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: myDeviceDir.path)

            for (key, list) in monthly {
                let monthFileURL = myDeviceDir.appendingPathComponent("\(key).json")
                var existing: [TranslationRecord] = []
                if fileManager.fileExists(atPath: monthFileURL.path), let existingData = try? Data(contentsOf: monthFileURL) {
                    existing = (try? decoder.decode([TranslationRecord].self, from: existingData)) ?? []
                }
                var map: [UUID: TranslationRecord] = [:]
                for rec in existing { map[rec.id] = rec }
                for rec in list {
                    if let cur = map[rec.id] {
                        if rec.updatedAt >= cur.updatedAt { map[rec.id] = rec }
                    } else {
                        map[rec.id] = rec
                    }
                }
                let combined = Array(map.values).sorted { $0.timestamp > $1.timestamp }

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let encoded = try encoder.encode(combined)
                try encoded.write(to: monthFileURL, options: .atomic)
                try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: monthFileURL.path)
            }

            let migratedURL = directoryURL.appendingPathComponent("history.json.migrated")
            try? fileManager.removeItem(at: migratedURL)
            try fileManager.moveItem(at: historyURL, to: migratedURL)
        } catch {
            migrationError = "Legacy migration failed: \(error.localizedDescription)"
        }
    }

    private func persistRecordToMonthFile(_ record: TranslationRecord) throws {
        try ensureWritable()
        let key = monthKey(record.timestamp)
        let myDeviceDir = devicesDirectoryURL.appendingPathComponent(deviceID, isDirectory: true)
        try fileManager.createDirectory(at: myDeviceDir, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: myDeviceDir.path)
        let monthFileURL = myDeviceDir.appendingPathComponent("\(key).json")

        var list: [TranslationRecord] = []
        if fileManager.fileExists(atPath: monthFileURL.path) {
            let data = try Data(contentsOf: monthFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            list = (try? decoder.decode([TranslationRecord].self, from: data)) ?? []
        }

        list.removeAll { $0.id == record.id }
        list.append(record)
        list.sort { $0.timestamp > $1.timestamp }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(list)
        try encoded.write(to: monthFileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: monthFileURL.path)
    }

    private func pruneTombstones() {
        let now = Date()
        let oneYearAgo = now.addingTimeInterval(-365 * 24 * 3600)
        let myDeviceDir = devicesDirectoryURL.appendingPathComponent(deviceID, isDirectory: true)
        guard let monthFiles = try? fileManager.contentsOfDirectory(at: myDeviceDir, includingPropertiesForKeys: nil) else { return }

        for fileURL in monthFiles where Self.isMonthFileName(fileURL.lastPathComponent) {
            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard var list = try? decoder.decode([TranslationRecord].self, from: data) else { continue }

            let originalCount = list.count
            list.removeAll { record in
                if let del = record.deletedAt, del < oneYearAgo { return true }
                return false
            }

            if list.count != originalCount {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let encoded = try? encoder.encode(list) {
                    try? encoded.write(to: fileURL, options: .atomic)
                    try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
                }
            }
        }
    }

    private func pruneOrphanAudio() {
        guard let audioFiles = try? fileManager.contentsOfDirectory(
            at: audioDirectoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        var validPaths: Set<String> = []
        for record in records + tombstonedRecords {
            if let path = record.sourceAudioPath { validPaths.insert(path) }
            if let path = record.resultAudioPath { validPaths.insert(path) }
        }

        // ponytail: grace window, an audio file can land before the month file that
        // references it when another device is still syncing. Only sweep settled files.
        let graceCutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for fileURL in audioFiles {
            let relativePath = "audio/\(fileURL.lastPathComponent)"
            guard !validPaths.contains(relativePath) else { continue }
            let modified = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            guard let modified, modified < graceCutoff else { continue }
            try? fileManager.removeItem(at: fileURL)
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
        guard var record = records.first(where: { $0.id == recordID }) else { throw StoreError.recordNotFound }
        mutation(&record)
        try persistRecordToMonthFile(record)
        applyLocally(record)
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
        let matching = records.filter { recordIDs.contains($0.id) }
        guard !matching.isEmpty else { throw StoreError.recordNotFound }

        let now = Date()
        for mutRecord in matching {
            var tombstone = mutRecord
            tombstone.deletedAt = now
            tombstone.updatedAt = now
            if let path = tombstone.sourceAudioPath, let url = try? containedAudioURL(for: path) {
                try? fileManager.removeItem(at: url)
            }
            if let path = tombstone.resultAudioPath, let url = try? containedAudioURL(for: path) {
                try? fileManager.removeItem(at: url)
            }
            tombstone.sourceAudioPath = nil
            tombstone.resultAudioPath = nil
            try persistRecordToMonthFile(tombstone)
            applyLocally(tombstone)
        }
    }
}
