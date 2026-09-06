// Work-file types shared by the vocabulary pack generator and its self-check.
//
// The generator appends one JSONL line per finished word so an interrupted run resumes without
// redoing work. These helpers own that file's format, its tolerance for a truncated final line,
// and the latest-wins fold into the shipped pack.
import Foundation

struct WorkLine: Codable {
    let w: String
    let status: String   // "ok" | "error"
    var r: String?
    var err: String?
    var at: String
    var model: String?
}

struct PackEntry: Codable {
    let w: String
    let r: String
}

struct PackOut: Codable {
    let sourceLanguage: String
    let targetLanguage: String
    let model: String?
    let generatedAt: String
    let entries: [PackEntry]
}

/// Appends one line at a time so an interrupted run loses at most the line being written.
final class WorkLog: @unchecked Sendable {
    private let url: URL
    private let handle: FileHandle
    private let lock = NSLock()
    private let encoder = JSONEncoder()

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func append(_ line: WorkLine) {
        guard var data = try? encoder.encode(line) else { return }
        data.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        try? handle.write(contentsOf: data)
        try? handle.synchronize()
    }

    func close() {
        try? handle.close()
    }

    /// Reads back what previous runs recorded. A truncated final line is dropped rather than
    /// failing the whole resume.
    static func read(url: URL) -> [WorkLine] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        var lines: [WorkLine] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let line = try? decoder.decode(WorkLine.self, from: Data(raw.utf8)) else { continue }
            lines.append(line)
        }
        return lines
    }
}


enum VocabWork {
    /// Words a previous run finished successfully, lowercased.
    static func completedWords(_ lines: [WorkLine]) -> Set<String> {
        Set(lines.filter { $0.status == "ok" && ($0.r?.isEmpty == false) }.map { $0.w.lowercased() })
    }

    /// How many times each word has been recorded as a failure.
    static func failureCounts(_ lines: [WorkLine]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for line in lines where line.status == "error" {
            counts[line.w.lowercased(), default: 0] += 1
        }
        return counts
    }

    /// Pack entries folded out of the work file: successful lines only, latest line per word wins,
    /// sorted so the shipped file has a stable diff.
    static func packEntries(_ lines: [WorkLine]) -> [PackEntry] {
        var latest: [String: WorkLine] = [:]
        for line in lines where line.status == "ok" && (line.r?.isEmpty == false) {
            latest[line.w.lowercased()] = line
        }
        return latest.values
            .sorted { $0.w.lowercased() < $1.w.lowercased() }
            .map { PackEntry(w: $0.w, r: $0.r ?? "") }
    }

    /// Words the list asked for that the work file never produced.
    static func missingWords(list: [String], lines: [WorkLine]) -> [String] {
        let done = completedWords(lines)
        return list.filter { !done.contains($0.lowercased()) }
    }

    /// Headwords from a list file: first CSV field per line, comments and blanks dropped,
    /// duplicates removed while keeping the original frequency order.
    static func parseWordList(_ text: String) -> [String] {
        var words: [String] = []
        var seen = Set<String>()
        for raw in text.split(separator: "\n") {
            let word = raw.split(separator: ",")[0].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, !word.hasPrefix("#") else { continue }
            if seen.insert(word.lowercased()).inserted { words.append(word) }
        }
        return words
    }
}
