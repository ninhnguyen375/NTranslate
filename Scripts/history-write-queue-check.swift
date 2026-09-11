// Self-check for coalesced background history writes. Uses a throwaway directory so it cannot
// touch the user's real history folder.
// swiftc -parse-as-library Sources/translate/TranslationHistoryStore.swift \
//   Sources/translate/ReviewPlanner.swift Sources/translate/LearnCard.swift \
//   Scripts/history-write-queue-check.swift -o /tmp/history-write-queue-check \
//   && /tmp/history-write-queue-check

import Foundation

/// TranslationHistoryStore mentions AppConfig in one convenience init. The check does not load
/// AppConfig.swift (AppKit + prompts), so this stub supplies the one property that init reads.
struct AppConfig {
    var historyDirectoryURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
}

@MainActor
func run() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("ntranslate-history-write-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }

    let deviceID = "write-queue-check"
    let january = Date(timeIntervalSince1970: 1)
    let february = Date(timeIntervalSince1970: 40 * 24 * 3600)

    // One record, then flush, then a fresh store must see it on disk.
    do {
        let store = TranslationHistoryStore(directoryURL: root, deviceID: deviceID)
        let rec = record(id: UUID(), timestamp: january, source: "one", result: "một")
        try store.append(rec)
        store.flush()
        let disk = TranslationHistoryStore(directoryURL: root, deviceID: deviceID)
        guard disk.records.map(\.id) == [rec.id] else {
            fail("single flush: disk ids \(disk.records.map(\.id)) != [\(rec.id)]")
        }
        guard disk.records.first?.sourceText == "one" else {
            fail("single flush: source text missing")
        }
    }

    // Several records in the same month, flushed once: nothing dropped, memory order matches disk.
    do {
        let store = TranslationHistoryStore(directoryURL: root, deviceID: deviceID)
        let a = record(id: UUID(), timestamp: Date(timeIntervalSince1970: 10), source: "a", result: "A")
        let b = record(id: UUID(), timestamp: Date(timeIntervalSince1970: 20), source: "b", result: "B")
        let c = record(id: UUID(), timestamp: Date(timeIntervalSince1970: 30), source: "c", result: "C")
        try store.append(a)
        try store.append(b)
        try store.append(c)
        let memoryIDs = store.records.map(\.id)
        store.flush()
        let disk = TranslationHistoryStore(directoryURL: root, deviceID: deviceID)
        guard disk.records.map(\.id) == memoryIDs else {
            fail("same-month flush: disk \(disk.records.map(\.id)) != memory \(memoryIDs)")
        }
        guard Set(disk.records.map(\.sourceText)) == Set(["one", "a", "b", "c"]) else {
            fail("same-month flush: lost a record, got \(disk.records.map(\.sourceText))")
        }
    }

    // A different month must land in its own file, not overwrite January.
    do {
        let store = TranslationHistoryStore(directoryURL: root, deviceID: deviceID)
        let feb = record(id: UUID(), timestamp: february, source: "feb", result: "hai")
        try store.append(feb)
        store.flush()
        let disk = TranslationHistoryStore(directoryURL: root, deviceID: deviceID)
        let sources = Set(disk.records.map(\.sourceText))
        guard sources.contains("feb"), sources.contains("one") else {
            fail("cross-month write overwrote a month: \(sources)")
        }
        let janFile = root.appendingPathComponent("devices/\(deviceID)/1970-01.json")
        let febFile = root.appendingPathComponent("devices/\(deviceID)/1970-02.json")
        guard fm.fileExists(atPath: janFile.path), fm.fileExists(atPath: febFile.path) else {
            fail("each month must have its own file")
        }
    }

    // Updating an existing id replaces the row instead of duplicating it.
    do {
        let store = TranslationHistoryStore(directoryURL: root, deviceID: deviceID)
        guard let original = store.records.first(where: { $0.sourceText == "one" }) else {
            fail("expected the January record to still be in memory")
        }
        try store.append(record(
            id: original.id,
            timestamp: original.timestamp,
            source: original.sourceText,
            result: "một (updated)"
        ))
        store.flush()
        let disk = TranslationHistoryStore(directoryURL: root, deviceID: deviceID)
        let matches = disk.records.filter { $0.id == original.id }
        guard matches.count == 1 else {
            fail("update duplicated id \(original.id), count \(matches.count)")
        }
        guard matches[0].resultText == "một (updated)" else {
            fail("update did not replace result, got \(matches[0].resultText)")
        }
        guard disk.records.map(\.id) == store.records.map(\.id) else {
            fail("after update, disk order \(disk.records.map(\.id)) != memory \(store.records.map(\.id))")
        }
        guard disk.records.map(\.resultText) == store.records.map(\.resultText) else {
            fail("after flush, disk contents != memory")
        }
    }

    print("history-write-queue-check: OK")
}

func record(id: UUID, timestamp: Date, source: String, result: String) -> TranslationRecord {
    TranslationRecord(
        id: id,
        timestamp: timestamp,
        sourceText: source,
        resultText: result,
        sourceLanguage: "English",
        targetLanguage: "Vietnamese",
        isSaved: false
    )
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("history-write-queue-check: \(message)\n".utf8))
    exit(1)
}

@main
enum HistoryWriteQueueCheck {
    static func main() {
        do {
            try MainActor.assumeIsolated { try run() }
        } catch {
            fail(error.localizedDescription)
        }
    }
}
