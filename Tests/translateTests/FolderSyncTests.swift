import AppKit
import Foundation
import Testing
@testable import translate

@Suite("FolderSyncTests")
@MainActor
struct FolderSyncTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ntranslate-foldersync-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func record(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        updatedAt: Date? = nil,
        deletedAt: Date? = nil,
        mode: TranslationMode = .translate,
        source: String = "hello",
        result: String = "xin chào",
        sourceLanguage: String = "English",
        targetLanguage: String = "Vietnamese",
        isSaved: Bool = false
    ) -> TranslationRecord {
        TranslationRecord(
            id: id,
            timestamp: timestamp,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            mode: mode,
            sourceText: source,
            resultText: result,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            isSaved: isSaved
        )
    }

    @Test func mergeDisjointListsCombinesAll() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory, deviceID: "mac-1")

        let r1 = record(source: "one")
        let r2 = record(source: "two")
        let merged = store.merge([[r1], [r2]])

        #expect(merged.count == 2)
        #expect(Set(merged.map(\.id)) == Set([r1.id, r2.id]))
    }

    @Test func mergeSameIDDifferentUpdatedAtNewestWins() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory, deviceID: "mac-1")

        let id = UUID()
        let t = Date(timeIntervalSince1970: 1000)
        let older = record(id: id, timestamp: t, updatedAt: Date(timeIntervalSince1970: 1001), result: "cũ")
        let newer = record(id: id, timestamp: t, updatedAt: Date(timeIntervalSince1970: 2000), result: "mới")

        let merged = store.merge([[older], [newer]])
        #expect(merged.count == 1)
        #expect(merged.first?.resultText == "mới")
    }

    @Test func mergeSameIDEqualUpdatedAtDeterministic() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory, deviceID: "mac-1")

        let id = UUID()
        let t = Date(timeIntervalSince1970: 1000)
        let rA = record(id: id, timestamp: t, updatedAt: t, result: "A")
        let rB = record(id: id, timestamp: t, updatedAt: t, result: "B")

        let merged1 = store.mergeWithDeviceIDs([([rA], "deviceA"), ([rB], "deviceB")])
        let merged2 = store.mergeWithDeviceIDs([([rB], "deviceB"), ([rA], "deviceA")])

        #expect(merged1.count == 1)
        #expect(merged2.count == 1)
        #expect(merged1.first?.resultText == merged2.first?.resultText)
    }

    @Test func tombstoneDoesNotResurrect() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeA = TranslationHistoryStore(directoryURL: directory, deviceID: "devA")
        let r = record(timestamp: Date(timeIntervalSince1970: 1000), source: "hello")
        try storeA.append(r)

        let storeB = TranslationHistoryStore(directoryURL: directory, deviceID: "devB")
        #expect(storeB.records.count == 1)

        try storeA.remove(recordID: r.id)
        #expect(storeA.records.isEmpty)

        storeB.refresh()
        #expect(storeB.records.isEmpty)
    }

    @Test func legacyHistoryMigrationPreservesAllRecordsAndRenamesFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let r1 = record(timestamp: Date(timeIntervalSince1970: 1000), source: "legacy1")
        let r2 = record(timestamp: Date(timeIntervalSince1970: 20000000), source: "legacy2")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([r1, r2])
        try data.write(to: directory.appendingPathComponent("history.json"))

        let store = TranslationHistoryStore(directoryURL: directory, deviceID: "devMigrate")
        #expect(store.records.count == 2)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json.migrated").path))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
    }

    @Test func appendTouchesOnlyMonthFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranslationHistoryStore(directoryURL: directory, deviceID: "devMonth")
        let t1 = Date(timeIntervalSince1970: 1724300000) // Aug 2024
        let r1 = record(timestamp: t1, source: "month1")
        try store.append(r1)

        let myDeviceDir = directory.appendingPathComponent("devices/devMonth")
        let files = try FileManager.default.contentsOfDirectory(atPath: myDeviceDir.path)
        #expect(files.contains("2024-08.json"))
        #expect(files.filter { $0.hasSuffix(".json") }.count == 1)
    }

    @Test func editOldRecordWritesToOriginalMonthFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranslationHistoryStore(directoryURL: directory, deviceID: "devEdit")
        let t1 = Date(timeIntervalSince1970: 1724300000) // Aug 2024
        let r1 = record(timestamp: t1, source: "old month")
        try store.append(r1)

        try store.setSaved(true, recordID: r1.id)

        let myDeviceDir = directory.appendingPathComponent("devices/devEdit")
        let files = try FileManager.default.contentsOfDirectory(atPath: myDeviceDir.path)
        #expect(files.contains("2024-08.json"))
        #expect(files.filter { $0.hasSuffix(".json") }.count == 1)
    }

    @Test func audioCleanupPreservesTombstoneAudio() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = TranslationHistoryStore(directoryURL: directory, deviceID: "devAudio")
        let r = record(source: "withAudio")
        try store.append(r)
        try store.attachAudio(Data([1, 2, 3]), kind: .source, recordID: r.id)

        let audioDir = directory.appendingPathComponent("audio")
        var audioFiles = try FileManager.default.contentsOfDirectory(atPath: audioDir.path)
        #expect(audioFiles.count == 1)

        // Fresh orphan stays: it may belong to a month file another device has not synced yet.
        let freshOrphanURL = audioDir.appendingPathComponent("fresh-orphan.audio")
        try Data([9, 9]).write(to: freshOrphanURL)
        _ = TranslationHistoryStore(directoryURL: directory, deviceID: "devAudio")
        audioFiles = try FileManager.default.contentsOfDirectory(atPath: audioDir.path)
        #expect(audioFiles.contains("fresh-orphan.audio"))

        // Settled orphan (older than the grace window) is swept.
        let staleOrphanURL = audioDir.appendingPathComponent("stale-orphan.audio")
        try Data([9, 9]).write(to: staleOrphanURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -30 * 24 * 3600)],
            ofItemAtPath: staleOrphanURL.path
        )
        _ = TranslationHistoryStore(directoryURL: directory, deviceID: "devAudio")
        audioFiles = try FileManager.default.contentsOfDirectory(atPath: audioDir.path)
        #expect(!audioFiles.contains("stale-orphan.audio"))
        #expect(audioFiles.contains("fresh-orphan.audio"))
    }

    @Test func refreshWithNoDiskChangesKeepsRecordsAndStillSeesOtherDeviceWrites() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let reader = TranslationHistoryStore(directoryURL: directory, deviceID: "devReader")
        let writer = TranslationHistoryStore(directoryURL: directory, deviceID: "devWriter")
        try writer.append(record(timestamp: Date(timeIntervalSince1970: 1_724_300_000), source: "first"))

        reader.refresh()
        #expect(reader.records.count == 1)

        // Idle refresh: nothing changed on disk, records must survive the cached fast path.
        reader.refresh()
        reader.refresh()
        #expect(reader.records.count == 1)
        #expect(reader.records.first?.sourceText == "first")

        // A later write from the other device must still be picked up.
        try writer.append(record(timestamp: Date(timeIntervalSince1970: 1_724_400_000), source: "second"))
        reader.refresh()
        #expect(reader.records.count == 2)
        #expect(Set(reader.records.map(\.sourceText)) == Set(["first", "second"]))
    }

    @Test func legacyRecordWithoutUpdatedAtFallsBackToTimestamp() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let json = """
        [{"id":"\(UUID().uuidString)","timestamp":"\(ISO8601DateFormatter().string(from: timestamp))",        "sourceText":"hello","resultText":"xin chào","sourceLanguage":"English",        "targetLanguage":"Vietnamese","isSaved":false}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode([TranslationRecord].self, from: Data(json.utf8))

        #expect(decoded.count == 1)
        #expect(decoded[0].updatedAt == decoded[0].timestamp)
        #expect(decoded[0].deletedAt == nil)
    }

    @Test func corruptDeviceFileIsSkippedAndOtherDevicesStillMerge() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let good = TranslationHistoryStore(directoryURL: directory, deviceID: "devGood")
        try good.append(record(timestamp: Date(timeIntervalSince1970: 1_724_300_000), source: "good"))

        let brokenDir = directory.appendingPathComponent("devices/devBroken", isDirectory: true)
        try FileManager.default.createDirectory(at: brokenDir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: brokenDir.appendingPathComponent("2024-08.json"))

        let reader = TranslationHistoryStore(directoryURL: directory, deviceID: "devReader")
        #expect(reader.records.count == 1)
        #expect(reader.loadError != nil)
    }

    @Test func expiredTombstoneIsPrunedFromDisk() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let timestamp = Date(timeIntervalSince1970: 1_724_300_000) // Aug 2024
        let expired = record(
            timestamp: timestamp,
            updatedAt: Date(timeIntervalSinceNow: -400 * 24 * 3600),
            deletedAt: Date(timeIntervalSinceNow: -400 * 24 * 3600),
            source: "expired"
        )
        let deviceDir = directory.appendingPathComponent("devices/devPrune", isDirectory: true)
        try FileManager.default.createDirectory(at: deviceDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([expired]).write(to: deviceDir.appendingPathComponent("2024-08.json"))

        let store = TranslationHistoryStore(directoryURL: directory, deviceID: "devPrune")
        #expect(store.records.isEmpty)

        let data = try Data(contentsOf: deviceDir.appendingPathComponent("2024-08.json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode([TranslationRecord].self, from: data).isEmpty)
    }
}
