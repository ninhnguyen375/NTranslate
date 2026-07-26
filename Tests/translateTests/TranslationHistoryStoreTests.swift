import AppKit
import Foundation
import Testing
@testable import translate

@Suite("TranslationHistoryStoreTests")
@MainActor
struct TranslationHistoryStoreTests {
    @Test func roundTripIsNewestFirstAndPersistsBookmark() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory)
        let older = record(timestamp: Date(timeIntervalSince1970: 1))
        let newer = record(timestamp: Date(timeIntervalSince1970: 2), source: "new")

        try store.append(older)
        try store.append(newer)
        try store.setSaved(true, recordID: older.id)

        let reloaded = TranslationHistoryStore(directoryURL: directory)
        #expect(reloaded.records.map(\.id) == [newer.id, older.id])
        #expect(reloaded.records.first(where: { $0.id == older.id })?.isSaved == true)
    }

    @Test func rejectsEmptyRecords() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory)

        #expect(throws: TranslationHistoryStore.StoreError.self) {
            try store.append(record(source: "   "))
        }
        #expect(store.records.isEmpty)
    }

    @Test func malformedHistoryLocksMutationsWithoutOverwrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let malformed = Data("{not-json".utf8)
        try malformed.write(to: historyURL)

        let store = TranslationHistoryStore(directoryURL: directory)
        #expect(store.loadError != nil)
        #expect(throws: TranslationHistoryStore.StoreError.self) {
            try store.append(record())
        }
        #expect(try Data(contentsOf: historyURL) == malformed)
    }

    @Test func semanticallyMalformedHistoryLocksEveryMutationWithoutOverwrite() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyURL = directory.appendingPathComponent("history.json")
        let id = UUID()
        var invalid = [record(source: "   "), record()]
        invalid[1] = TranslationRecord(
            id: id, timestamp: invalid[1].timestamp, sourceText: "hello", resultText: "result",
            sourceLanguage: "English", targetLanguage: "Vietnamese",
            sourceAudioPath: "audio/../../escape.audio", resultAudioPath: nil, isSaved: false
        )
        invalid.append(TranslationRecord(
            id: id, timestamp: Date(), sourceText: "duplicate", resultText: "result",
            sourceLanguage: "English", targetLanguage: "Vietnamese",
            sourceAudioPath: nil, resultAudioPath: nil, isSaved: false
        ))
        let malformed = try encoded(invalid)
        try malformed.write(to: historyURL)

        let store = TranslationHistoryStore(directoryURL: directory)
        #expect(store.loadError != nil)
        #expect(store.records.isEmpty)
        #expect(throws: TranslationHistoryStore.StoreError.self) { try store.append(record()) }
        #expect(throws: TranslationHistoryStore.StoreError.self) { try store.setSaved(true, recordID: id) }
        #expect(throws: TranslationHistoryStore.StoreError.self) { try store.attachAudio(Data([1]), kind: .source, recordID: id) }
        #expect(try Data(contentsOf: historyURL) == malformed)
    }

    @Test func audioPathsAreRelativeAndMissingAudioReturnsNil() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory)
        let item = record()
        try store.append(item)
        try store.attachAudio(Data([0, 1, 2]), kind: .source, recordID: item.id)

        let path = try #require(store.records.first?.sourceAudioPath)
        #expect(!path.hasPrefix("/"))
        #expect(path.hasPrefix("audio/"))
        #expect(try store.audioExists(for: item.id, kind: .source))
        #expect(try store.audioData(for: item.id, kind: .source) == Data([0, 1, 2]))
        try FileManager.default.removeItem(at: directory.appendingPathComponent(path))
        #expect(!(try store.audioExists(for: item.id, kind: .source)))
        #expect(try store.audioData(for: item.id, kind: .source) == nil)
    }

    @Test func customHistoryDirectoryIsRespected() throws {
        let customDir = try temporaryDirectory().appendingPathComponent("custom_history")
        var config = AppConfig.default
        config.historyDirectory = customDir.path
        let store = TranslationHistoryStore(config: config)
        #expect(store.directoryURL.path == customDir.standardizedFileURL.path)
        #expect(store.audioDirectoryURL.path == customDir.appendingPathComponent("audio").standardizedFileURL.path)
    }

    @Test func filterRecords() {
        let r1 = TranslationRecord(id: UUID(), timestamp: Date(), sourceText: "hello world", resultText: "xin chào thế giới", sourceLanguage: "en", targetLanguage: "vi", isSaved: true)
        let r2 = TranslationRecord(id: UUID(), timestamp: Date(), sourceText: "apple", resultText: "quả táo", sourceLanguage: "en", targetLanguage: "vi", isSaved: false)
        let records = [r1, r2]

        let filteredSaved = HistoryWindowController.filter(records: records, query: "", savedOnly: true)
        #expect(filteredSaved.count == 1 && filteredSaved[0].id == r1.id)

        let filteredQuery = HistoryWindowController.filter(records: records, query: "táo", savedOnly: false)
        #expect(filteredQuery.count == 1 && filteredQuery[0].id == r2.id)
    }

    @Test func rejectsTraversalAndSymlinkEscapes() throws {
        let directory = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("audio"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("audio/link"),
            withDestinationURL: outside
        )
        try Data([9]).write(to: outside.appendingPathComponent("escaped.audio"))

        var traversal = record()
        traversal.sourceAudioPath = "audio/../escaped.audio"
        try encoded([traversal]).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
        let traversalStore = TranslationHistoryStore(directoryURL: directory)
        #expect(throws: TranslationHistoryStore.StoreError.self) {
            _ = try traversalStore.audioData(for: traversal.id, kind: .source)
        }

        var symlink = record()
        symlink.sourceAudioPath = "audio/link/escaped.audio"
        try encoded([symlink]).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
        let symlinkStore = TranslationHistoryStore(directoryURL: directory)
        #expect(throws: TranslationHistoryStore.StoreError.self) {
            _ = try symlinkStore.audioData(for: symlink.id, kind: .source)
        }
    }

    @Test func removesAudioWhenMetadataWriteFails() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory)
        let item = record()
        try store.append(item)
        let historyURL = directory.appendingPathComponent("history.json")
        try FileManager.default.removeItem(at: historyURL)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)

        #expect(throws: Error.self) {
            try store.attachAudio(Data([1, 2, 3]), kind: .result, recordID: item.id)
        }
        let audioContents = try FileManager.default.contentsOfDirectory(
            at: directory.appendingPathComponent("audio"),
            includingPropertiesForKeys: nil
        )
        #expect(audioContents.isEmpty)
        #expect(store.records.first?.resultAudioPath == nil)
    }

    @Test func failedAudioReplacementPreservesReferencedBytes() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory)
        let item = record()
        try store.append(item)
        let original = Data([4, 5, 6])
        try store.attachAudio(original, kind: .source, recordID: item.id)
        let originalPath = try #require(store.records.first?.sourceAudioPath)
        let historyURL = directory.appendingPathComponent("history.json")
        try FileManager.default.removeItem(at: historyURL)
        try FileManager.default.createDirectory(at: historyURL, withIntermediateDirectories: false)

        #expect(throws: Error.self) {
            try store.attachAudio(Data([7, 8, 9]), kind: .source, recordID: item.id)
        }
        #expect(store.records.first?.sourceAudioPath == originalPath)
        #expect(try store.audioData(for: item.id, kind: .source) == original)
    }

    @Test func rejectsLeafSymlinkEscape() throws {
        let directory = try temporaryDirectory()
        let outside = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: outside)
        }
        let audioDirectory = directory.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let outsideAudio = outside.appendingPathComponent("outside.audio")
        try Data([9]).write(to: outsideAudio)
        try FileManager.default.createSymbolicLink(
            at: audioDirectory.appendingPathComponent("leaf.audio"),
            withDestinationURL: outsideAudio
        )
        var item = record()
        item.sourceAudioPath = "audio/leaf.audio"
        try encoded([item]).write(to: directory.appendingPathComponent("history.json"), options: .atomic)

        let store = TranslationHistoryStore(directoryURL: directory)
        #expect(throws: TranslationHistoryStore.StoreError.self) {
            _ = try store.audioData(for: item.id, kind: .source)
        }
    }

    @Test func windowLoadsHistory() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory)
        try store.append(record(timestamp: Date()))

        let controller = HistoryWindowController(store: store)
        controller.reloadHistory()

        #expect(controller.window?.title == "Translation History")
        #expect(controller.numberOfRows(in: NSTableView()) == 1)
    }

    private func record(
        timestamp: Date = Date(timeIntervalSince1970: 1),
        source: String = "hello"
    ) -> TranslationRecord {
        TranslationRecord(
            id: UUID(),
            timestamp: timestamp,
            sourceText: source,
            resultText: "xin chào",
            sourceLanguage: "English",
            targetLanguage: "Vietnamese",
            sourceAudioPath: nil,
            resultAudioPath: nil,
            isSaved: false
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func encoded(_ records: [TranslationRecord]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(records)
    }
    @Test func removesRecordsAndReferencedAudio() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory)
        let first = record(source: "first")
        let second = record(source: "second")
        try store.append(first)
        try store.append(second)
        try store.attachAudio(Data([1, 2]), kind: .source, recordID: first.id)
        let audioPath = try #require(store.records.first(where: { $0.id == first.id })?.sourceAudioPath)

        try store.remove(recordIDs: [first.id])

        #expect(store.records.map(\.id) == [second.id])
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(audioPath).path))
        #expect(TranslationHistoryStore(directoryURL: directory).records.map(\.id) == [second.id])
    }

    @Test func filtersBySavedQueryAndTimeRange() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recent = TranslationRecord(id: UUID(), timestamp: now.addingTimeInterval(-3600), sourceText: "Galaxy", resultText: "Thiên hà", sourceLanguage: "English", targetLanguage: "Vietnamese", isSaved: true)
        let old = TranslationRecord(id: UUID(), timestamp: now.addingTimeInterval(-8 * 86_400), sourceText: "Old", resultText: "Cũ", sourceLanguage: "English", targetLanguage: "Vietnamese", isSaved: true)

        let filtered = HistoryWindowController.filter(records: [recent, old], query: "galaxy", savedOnly: true, timeRange: .week, now: now)

        #expect(filtered.map(\.id) == [recent.id])
    }

    @Test func openRecordCallbackUsesDoubleClickedRecord() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranslationHistoryStore(directoryURL: directory)
        let item = record(timestamp: Date())
        try store.append(item)
        var opened: UUID?
        var events: [String] = []
        let controller = HistoryWindowController(store: store) { opened = $0.id; events.append("open") }

        controller.reloadHistory()
        controller.openRecord(at: 0, stopAudio: { events.append("stop") })

        #expect(opened == item.id)
        #expect(events == ["stop", "open"])
    }
}
