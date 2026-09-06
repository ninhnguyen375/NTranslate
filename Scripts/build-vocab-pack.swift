// Offline generator for the Learn vocabulary pack.
//
// Generating ~2800 cards takes a long time and can stop halfway (quota, network, a closed lid),
// so every finished word is appended to a JSONL work file the moment it lands. Re-running the
// same command resumes: words already recorded as "ok" are skipped.
//
//   swiftc -parse-as-library \
//     Sources/translate/Translator.swift Sources/translate/AppConfig.swift \
//     Sources/translate/AppConfigPrompts.swift Sources/translate/LanguageDetector.swift \
//     Sources/translate/AppTheme.swift Sources/translate/APIKeyStore.swift \
//     Sources/translate/NativeSpeechEngine.swift \
//     Scripts/VocabWork.swift Scripts/build-vocab-pack.swift -o /tmp/build-vocab-pack
//
//   /tmp/build-vocab-pack                 # generate (resumable, run as many times as needed)
//   /tmp/build-vocab-pack --limit 30      # trial run to check cost and quality first
//   /tmp/build-vocab-pack --pack          # fold the work file into Resources/vocab-en-vi.json
//
// The API key comes from NTRANSLATE_API_KEY, or from the Keychain when that is unset.
import Foundation

/// `AppConfigPrompts` calls into the settings window for one prompt-drift helper the generator
/// never uses. Standing it in here keeps this script off the AppKit half of the app.
enum SettingsWindowController {
    static func promptNeedsSync(current: String, appDefault: String) -> Bool { false }
}

/// A dead endpoint answers every request, so without this the rest of the list burns through as
/// failures in a couple of minutes and produces nothing.
let consecutiveFailureLimit = 20

enum BuildError: LocalizedError {
    case missingWordList(String)
    case missingAPIKey
    case quotaExhausted(Int, Int)
    case serviceDown(Int, Int, String)

    var errorDescription: String? {
        switch self {
        case let .missingWordList(path):
            return "Word list not found at \(path)"
        case .missingAPIKey:
            return "No API key. Set NTRANSLATE_API_KEY or store one in the app's Keychain entry."
        case let .quotaExhausted(done, total):
            return "Quota exhausted after \(done)/\(total) words. Progress saved; run the same command again to resume."
        case let .serviceDown(done, total, reason):
            return "Stopped after \(consecutiveFailureLimit) failures in a row at \(done)/\(total) words: \(reason)\nProgress saved; run the same command again to resume once the service is back."
        }
    }
}

@main
struct BuildVocabPack {
    static let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    static let workURL = repoRoot.appendingPathComponent("Scripts/.vocab-work/en-vi.jsonl")
    /// Cards from an earlier prompt version. They are folded in first so a word the current run
    /// has not reached yet still ships, and gets replaced the day it is regenerated.
    static let legacyWorkURL = repoRoot.appendingPathComponent("Scripts/.vocab-work/en-vi-legacy.jsonl")
    static let packURL = repoRoot.appendingPathComponent("Resources/vocab-en-vi.json")
    static let defaultWordList = repoRoot.appendingPathComponent("Scripts/data/wordlist.txt")

    static let sourceLanguage = "English"
    static let targetLanguage = "Vietnamese"

    static func main() async {
        // Progress must reach a redirected log as it happens, not in one block at exit.
        setvbuf(stdout, nil, _IONBF, 0)
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args.contains("--pack") {
                try pack()
            } else {
                try await generate(args: args)
            }
        } catch {
            FileHandle.standardError.write(Data("\n\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func flagValue(_ name: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    // MARK: - Generate

    static func generate(args: [String]) async throws {
        let listURL = flagValue("--words", in: args).map { URL(fileURLWithPath: $0) } ?? defaultWordList
        guard let listText = try? String(contentsOf: listURL, encoding: .utf8) else {
            throw BuildError.missingWordList(listURL.path)
        }
        let concurrency = flagValue("--concurrency", in: args).flatMap(Int.init) ?? 5
        let limit = flagValue("--limit", in: args).flatMap(Int.init)
        let skipFailed = args.contains("--skip-failed")

        let words = VocabWork.parseWordList(listText)
        let previous = WorkLog.read(url: workURL)
        let done = VocabWork.completedWords(previous)
        let failureCount = VocabWork.failureCounts(previous)

        var pending = words.filter { word in
            let key = word.lowercased()
            if done.contains(key) { return false }
            if skipFailed, failureCount[key, default: 0] >= 3 { return false }
            return true
        }
        if let limit { pending = Array(pending.prefix(limit)) }

        print("Word list: \(words.count) · already done: \(done.count) · to generate now: \(pending.count)")
        guard !pending.isEmpty else {
            print("Nothing to do. Run with --pack to build \(packURL.lastPathComponent).")
            return
        }

        let config = AppConfig.load()
        let apiKey = try resolveAPIKey()
        let translator = Translator(config: config, apiKey: apiKey)
        let model = config.model
        let log = try WorkLog(url: workURL)
        defer { log.close() }

        let progress = Progress(total: pending.count, alreadyDone: done.count, grandTotal: words.count)
        var quotaHit = false
        var consecutiveFailures = 0
        var lastFailure = ""

        var cursor = 0
        await withTaskGroup(of: WordOutcome.self) { group in
            func addNext() {
                guard cursor < pending.count, !quotaHit, consecutiveFailures < consecutiveFailureLimit else { return }
                let word = pending[cursor]
                cursor += 1
                group.addTask { await run(word: word, translator: translator, sourceLang: sourceLanguage, targetLang: targetLanguage) }
            }
            for _ in 0..<max(1, concurrency) { addNext() }

            while let outcome = await group.next() {
                switch outcome.result {
                case let .success(text):
                    log.append(WorkLine(w: outcome.word, status: "ok", r: text, err: nil, at: stamp(), model: model))
                    progress.recordSuccess()
                    consecutiveFailures = 0
                case let .failure(error):
                    log.append(WorkLine(w: outcome.word, status: "error", r: nil, err: error.localizedDescription, at: stamp(), model: model))
                    progress.recordFailure()
                    consecutiveFailures += 1
                    lastFailure = error.localizedDescription
                    if isQuotaError(error) { quotaHit = true }
                }
                progress.printIfDue()
                addNext()
            }
        }

        progress.printFinal()
        if quotaHit {
            throw BuildError.quotaExhausted(progress.doneOverall, words.count)
        }
        if consecutiveFailures >= consecutiveFailureLimit {
            throw BuildError.serviceDown(progress.doneOverall, words.count, lastFailure)
        }
        print("Run --pack when the list is complete enough.")
    }

    struct WordOutcome {
        let word: String
        let result: Result<String, Error>
    }

    /// Transient failures get two retries with backoff. A quota failure is returned immediately,
    /// because retrying it only burns the rest of the list.
    static func run(word: String, translator: Translator, sourceLang: String, targetLang: String) async -> WordOutcome {
        var lastError: Error = BuildError.missingAPIKey
        for attempt in 0..<3 {
            do {
                let text = try await learn(word, translator: translator, sourceLang: sourceLang, targetLang: targetLang)
                return WordOutcome(word: word, result: .success(text))
            } catch {
                lastError = error
                if isQuotaError(error) { break }
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                }
            }
        }
        return WordOutcome(word: word, result: .failure(lastError))
    }

    static func learn(_ word: String, translator: Translator, sourceLang: String, targetLang: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            _ = translator.learn(word, sourceLang: sourceLang, targetLang: targetLang) { result in
                continuation.resume(with: result)
            }
        }
    }

    static func isQuotaError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "HTTP", nsError.code == 429 || nsError.code == 402 { return true }
        let text = error.localizedDescription.lowercased()
        return text.contains("quota") || text.contains("insufficient")
    }

    static func resolveAPIKey() throws -> String {
        if let env = ProcessInfo.processInfo.environment["NTRANSLATE_API_KEY"],
           !env.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return env
        }
        if let stored = try? APIKeyStore.shared.load(),
           !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored
        }
        throw BuildError.missingAPIKey
    }

    static func stamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Pack

    /// Folds the work file into the shipped pack: "ok" lines only, latest line wins per word.
    static func pack() throws {
        let legacy = WorkLog.read(url: legacyWorkURL)
        let current = WorkLog.read(url: workURL)
        guard !current.isEmpty || !legacy.isEmpty else {
            print("No work file at \(workURL.path). Generate first.")
            return
        }
        // Order matters: packEntries keeps the last line per word, so current always wins.
        let lines = legacy + current
        let entries = VocabWork.packEntries(lines)
        if !legacy.isEmpty {
            let upgraded = VocabWork.completedWords(current).count
            print("Merged \(VocabWork.completedWords(legacy).count) legacy cards with \(upgraded) regenerated ones.")
        }
        let out = PackOut(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            model: lines.last(where: { $0.status == "ok" })?.model,
            generatedAt: stamp(),
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(out)
        try FileManager.default.createDirectory(at: packURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: packURL)

        let size = Double(data.count) / 1_048_576
        print(String(format: "Wrote %@ · %d entries · %.1f MB", packURL.path, entries.count, size))
        if let listText = try? String(contentsOf: defaultWordList, encoding: .utf8) {
            let missing = VocabWork.missingWords(list: VocabWork.parseWordList(listText), lines: lines)
            if !missing.isEmpty {
                let sample = missing.prefix(10).joined(separator: ", ")
                print("\(missing.count) words still missing (they fall back to the API): \(sample)\(missing.count > 10 ? ", ..." : "")")
            }
        }
    }
}

/// Throughput counter, printed every 25 words so a long run shows it is alive.
final class Progress: @unchecked Sendable {
    private let total: Int
    private let alreadyDone: Int
    private let grandTotal: Int
    private let start = Date()
    private var ok = 0
    private var failed = 0

    init(total: Int, alreadyDone: Int, grandTotal: Int) {
        self.total = total
        self.alreadyDone = alreadyDone
        self.grandTotal = grandTotal
    }

    var doneOverall: Int { alreadyDone + ok }

    func recordSuccess() { ok += 1 }
    func recordFailure() { failed += 1 }

    func printIfDue() {
        guard (ok + failed) % 25 == 0 else { return }
        print(line())
    }

    func printFinal() {
        print(line())
    }

    private func line() -> String {
        let processed = ok + failed
        let elapsed = Date().timeIntervalSince(start)
        let rate = processed > 0 ? elapsed / Double(processed) : 0
        let remaining = Double(total - processed) * rate
        return String(
            format: "%d/%d words · %d errors · %.1f min elapsed · ~%.0f min left",
            doneOverall, grandTotal, failed, elapsed / 60, remaining / 60
        )
    }
}
