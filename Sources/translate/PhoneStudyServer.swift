// Serves the Study screen to a phone over Tailscale: due cards with grading, and saved dialogues
// with audio. Binds only to the Tailscale address (100.64.0.0/10), so nothing on the local Wi-Fi
// can reach it, and every request must carry a random token kept in UserDefaults.
import AppKit

@MainActor
final class PhoneStudyServer {
    static let port: UInt16 = 8765
    private static let tokenKey = "local.ninh.ntranslate.phoneStudyToken"

    private let store: () -> TranslationHistoryStore?
    private let translator: () -> Translator?
    private let config: () -> AppConfig?
    private var listenSocket: Int32 = -1
    private(set) var host: String?

    init(
        store: @escaping () -> TranslationHistoryStore?,
        translator: @escaping () -> Translator?,
        config: @escaping () -> AppConfig?
    ) {
        self.store = store
        self.translator = translator
        self.config = config
    }

    static var token: String {
        if let existing = UserDefaults.standard.string(forKey: tokenKey), !existing.isEmpty { return existing }
        let fresh = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(fresh, forKey: tokenKey)
        return fresh
    }

    var link: String? {
        host.map { "http://\($0):\(Self.port)/?t=\(Self.token)" }
    }

    /// Starts once Tailscale has an address. Safe to call again: a running listener is kept.
    /// BSD sockets on purpose: an NWListener bound to the Tailscale address never completed a
    /// handshake on this machine, while a plain socket on the same address did.
    func startIfPossible() {
        guard listenSocket < 0, let ip = Self.tailscaleAddress() else { return }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = Self.port.bigEndian
        inet_pton(AF_INET, ip, &addr.sin_addr)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(fd, 16) == 0 else { close(fd); return }
        listenSocket = fd
        host = ip
        Thread.detachNewThread { [weak self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { return }
                DispatchQueue.global().async { self?.serve(client) }
            }
        }
    }

    /// Tailscale hands out CGNAT addresses, 100.64.0.0/10.
    nonisolated static func tailscaleAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { return nil }
        defer { freeifaddrs(head) }
        var cursor = head
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let ipv4 = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            if ipv4 >> 22 == (100 << 2 | 1) {
                return "\(ipv4 >> 24).\(ipv4 >> 16 & 0xff).\(ipv4 >> 8 & 0xff).\(ipv4 & 0xff)"
            }
        }
        return nil
    }

    /// The app icon at the size iOS wants for a home-screen shortcut; iOS ignores SVG icons.
    private static let iconPNG: Data = {
        let side = 512
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return Data() }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // iOS rounds the corners itself, so fill the square instead of leaving the macOS margin transparent.
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()
        NSApp.applicationIconImage.draw(in: NSRect(x: 0, y: 0, width: side, height: side).insetBy(dx: -64, dy: -64))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }()

    // MARK: - HTTP

    private struct Request: Sendable {
        let method: String
        let path: String
        let query: [String: String]
        let body: Data
    }

    /// Runs off the main thread: reads one request, hands it to the main actor, writes the reply.
    private nonisolated func serve(_ fd: Int32) {
        var timeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)
        var request: Request?
        // ponytail: 1 MB cap, requests here are tiny JSON bodies.
        while request == nil, buffer.count < 1_000_000 {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            request = Self.parse(buffer)
        }
        guard let request else { close(fd); return }
        Task { @MainActor [weak self] in
            guard let self else { close(fd); return }
            self.handle(request) { status, type, body in
                DispatchQueue.global().async { Self.send(fd, status: status, type: type, body: body) }
            }
        }
    }

    /// nil until the headers and the whole Content-Length body have arrived.
    private nonisolated static func parse(_ data: Data) -> Request? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        let length = lines.dropFirst().compactMap { line -> Int? in
            let pair = line.split(separator: ":", maxSplits: 1)
            guard pair.count == 2, pair[0].lowercased() == "content-length" else { return nil }
            return Int(pair[1].trimmingCharacters(in: .whitespaces))
        }.first ?? 0
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        let components = URLComponents(string: String(parts[1]))
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return Request(method: String(parts[0]), path: components?.path ?? "/", query: query, body: Data(body.prefix(length)))
    }

    private nonisolated static func send(_ fd: Int32, status: Int, type: String, body: Data) {
        let reason = status == 200 ? "OK" : "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        let payload = Data(head.utf8) + body
        payload.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.send(fd, raw.baseAddress! + offset, raw.count - offset, 0)
                if n <= 0 { break }
                offset += n
            }
        }
        close(fd)
    }

    private typealias Reply = @MainActor @Sendable (Int, String, Data) -> Void

    private func handle(_ request: Request, reply: @escaping Reply) {
        guard request.query["t"] == Self.token else {
            return reply(403, "text/plain", Data("Forbidden".utf8))
        }
        switch (request.method, request.path) {
        case ("GET", "/"):
            // The token is baked into the manifest and icon links so a home-screen launch keeps it.
            reply(200, "text/html; charset=utf-8", Data(PhoneStudyPage.html.replacingOccurrences(of: "__TOKEN__", with: Self.token).replacingOccurrences(of: "__VERSION__", with: Self.pageVersion).utf8))
        case ("GET", "/version"):
            reply(200, "text/plain", Data(Self.pageVersion.utf8))
        case ("GET", "/manifest.json"):
            reply(200, "application/manifest+json", Data(PhoneStudyPage.manifest.replacingOccurrences(of: "__TOKEN__", with: Self.token).utf8))
        case ("GET", "/icon.png"):
            reply(200, "image/png", Self.iconPNG)
        case ("GET", "/api/cards"):
            json(cards(kind: request.query["kind"].flatMap(Int.init).flatMap(ReviewPlanner.QuestionKind.init(rawValue:)),
                       all: request.query["all"] == "1"), reply)
        case ("POST", "/api/grade"):
            grade(request.body, reply)
        case ("GET", "/api/passages"):
            json(passages(), reply)
        case ("POST", "/api/passage"):
            updatePassage(request.body, reply)
        case ("POST", "/api/weave"):
            weave(request.body, reply)
        case ("GET", "/api/stats"):
            json(stats(), reply)
        case ("GET", "/api/newwords"):
            json(newWords(filter: request.query["level"] ?? "all"), reply)
        case ("POST", "/api/newword"):
            decideNewWord(request.body, reply)
        case ("GET", "/api/images"):
            images(term: request.query["term"] ?? "", reply)
        case ("GET", "/api/passage"):
            guard let key = request.query["key"], let item = passage(key: key) else {
                return reply(404, "text/plain", Data("Not found".utf8))
            }
            json(item, reply)
        case ("GET", "/api/audio"):
            audio(text: request.query["text"] ?? "", recordID: request.query["id"], language: request.query["lang"] ?? "English", reply)
        case ("POST", "/api/translate"):
            translate(request.body, reply)
        case ("GET", "/api/history"):
            json(history(query: request.query["q"] ?? "", savedOnly: request.query["saved"] == "1"), reply)
        case ("GET", "/api/record"):
            guard let id = request.query["id"].flatMap(UUID.init(uuidString:)),
                  let record = store()?.records.first(where: { $0.id == id }) else {
                return reply(404, "text/plain", Data("Not found".utf8))
            }
            json(HistoryItem(record, full: true), reply)
        case ("POST", "/api/record"):
            updateRecord(request.body, reply)
        case ("POST", "/api/ask"):
            ask(request.body, reply)
        default:
            reply(404, "text/plain", Data("Not found".utf8))
        }
    }

    /// Stable across launches (unlike hashValue), so the page only flags a real change.
    private static let pageVersion: String = {
        let hash = PhoneStudyPage.html.utf8.reduce(UInt64(5381)) { $0 &* 33 &+ UInt64($1) }
        return String(hash, radix: 36)
    }()

    private func json<T: Encodable>(_ value: T, _ reply: Reply) {
        let data = (try? JSONEncoder().encode(value)) ?? Data("null".utf8)
        reply(200, "application/json", data)
    }

    // MARK: - Cards

    private struct Card: Encodable {
        let id: String
        let term: String
        let context: String?
        let back: String
        let card: StructuredCard?
        let question: Question?
    }

    /// What the front asks, picked like the Mac session. nil means a plain Flip card.
    struct Question: Encodable {
        let kind: String
        let prompt: String
        let answer: String
        var choices: [String]? = nil
        var explanation: String? = nil
        var note: String? = nil
    }

    /// Mirrors `ReviewWindowController.question(for:)`; the phone always has a voice via the Mac.
    private static func question(for record: TranslationRecord, requested: ReviewPlanner.QuestionKind?) -> Question? {
        let card = LearnCard.parse(record.resultText)
        var available: Set<ReviewPlanner.QuestionKind> = [.flip]
        let drill = ConfusableDrillItem.build(from: [card]).first
        if record.mode == .learn {
            if !card.clozePool.isEmpty { available.insert(.cloze) }
            if card.collocationQuiz != nil { available.insert(.collocation) }
            if card.familyQuiz != nil { available.insert(.family) }
            if drill != nil { available.insert(.contrast) }
            if card.recall != nil { available.insert(.recall) }
            if !card.headword.isEmpty { available.insert(.listen) }
        }
        let resolved = ReviewPlanner.resolve(requested: requested, interval: record.interval,
                                             repetitions: record.repetitions, available: available)
        let typed: LearnCard.ClozeQuestion?
        switch resolved.kind {
        case .flip: typed = nil
        case .cloze: typed = card.clozePool.randomElement()
        case .collocation: typed = card.collocationQuiz
        case .family: typed = card.familyQuiz
        case .recall: typed = card.recall
        case .listen: typed = LearnCard.ClozeQuestion(prompt: "Listen, then type what you hear.", answer: card.headword)
        case .contrast:
            guard let drill else { return nil }
            return Question(kind: "contrast", prompt: drill.sentence, answer: drill.correct,
                            choices: [drill.correct, drill.distractor].shuffled(), explanation: drill.explanation, note: resolved.note)
        }
        guard let typed else { return resolved.note.map { Question(kind: "flip", prompt: "", answer: "", note: $0) } }
        return Question(kind: resolved.kind.label.lowercased(), prompt: typed.hintedPrompt, answer: typed.answer, note: resolved.note)
    }

    /// The parsed Learn card, so the phone draws the same sections as the Mac card.
    struct StructuredCard: Encodable {
        struct Example: Encodable { let level: String; let sentence: String; let translation: String }
        struct Confusable: Encodable { let other: String; let difference: String; let sentence: String }
        struct Pair: Encodable { let text: String; let gloss: String }
        struct Cloze: Encodable { let prompt: String; let answer: String }
        let headword: String
        let pronunciation: String
        let meanings: [Pair]
        let synonyms: [Pair]
        let antonyms: [Pair]
        let examples: [Example]
        let confusables: [Confusable]
        let family: [Pair]
        let collocations: [Pair]
        let mnemonic: String
        let cloze: Cloze?
        let naturalMeaning: String
        let grammar: [String]
        let phrases: [Pair]
        let chunks: [Pair]
        let variation: String

        init?(_ text: String) {
            guard LearnCard.shouldDisplayStructured(text) else { return nil }
            let card = LearnCard.parse(text)
            let pairs = { (forms: [LearnCard.FamilyForm]) in forms.map { Pair(text: $0.form, gloss: $0.gloss) } }
            headword = card.headword
            pronunciation = card.pronunciation
            meanings = card.meanings.map { let m = LearnCard.splitMeaning($0); return Pair(text: m.pos, gloss: m.gloss.isEmpty ? $0 : m.gloss) }
            synonyms = pairs(card.synonyms)
            antonyms = pairs(card.antonyms)
            examples = card.examples.map { Example(level: $0.level.displayLabel, sentence: $0.sentence, translation: $0.translation) }
            confusables = card.confusables.map { Confusable(other: $0.other, difference: $0.difference, sentence: $0.contrastSentence) }
            family = pairs(card.familyForms)
            collocations = card.collocations.map { Pair(text: $0.phrase, gloss: $0.meaning) }
            mnemonic = card.mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
            cloze = card.cloze.map { Cloze(prompt: $0.prompt.contains("___") ? $0.prompt : $0.hintedPrompt, answer: $0.answer) }
            naturalMeaning = card.naturalMeaning
            grammar = card.grammar
            phrases = card.phrases.map { Pair(text: $0.phrase, gloss: $0.meaning) }
            chunks = card.chunks.map { Pair(text: $0.phrase, gloss: $0.meaning) }
            variation = card.variation
        }
    }

    /// `all` is the Mac's Review All: every saved card, practice only (the page skips /api/grade).
    private func cards(kind: ReviewPlanner.QuestionKind?, all: Bool) -> [Card] {
        guard let store = store() else { return [] }
        let due = all ? store.records.filter { $0.isSaved } : store.dueReviews()
        return ReviewPlanner.interleave(due) { LearnCard.Encounter.split($0.sourceText).term }.map { record in
            let parts = LearnCard.Encounter.split(record.sourceText)
            return Card(id: record.id.uuidString, term: parts.term, context: parts.context, back: record.resultText, card: StructuredCard(record.resultText),
                        question: Self.question(for: record, requested: kind))
        }
    }

    private func grade(_ body: Data, _ reply: Reply) {
        struct Payload: Decodable { let id: String; let grade: Int }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body),
              let id = UUID(uuidString: payload.id),
              let grade = SRSGrade(rawValue: payload.grade),
              let store = store() else {
            return reply(400, "text/plain", Data("Bad request".utf8))
        }
        do {
            try store.updateSRS(recordID: id, grade: grade)
            json(["ok": true], reply)
        } catch {
            reply(500, "text/plain", Data(error.localizedDescription.utf8))
        }
    }

    // MARK: - Progress and new words

    private struct Stats: Encodable {
        struct Bucket: Encodable { let label: String; let detail: String; let count: Int }
        let buckets: [Bucket]
        let dueToday: Int
        let dueTomorrow: Int
        let dayStreak: Int
        let last7Days: [Int]
        let totalSaved: Int
        let knownWords: Int
    }

    /// Same numbers as the Mac Study home screen.
    private func stats() -> Stats {
        let deck = DeckStats.compute(records: store()?.records ?? [])
        VocabProgressStore.shared.load()
        return Stats(
            buckets: DeckStats.Bucket.allCases.map { .init(label: $0.label, detail: $0.detail, count: deck.count($0)) },
            dueToday: deck.dueToday, dueTomorrow: deck.dueTomorrow, dayStreak: deck.dayStreak,
            last7Days: deck.last7Days, totalSaved: deck.totalSaved,
            knownWords: VocabProgressStore.shared.progress.known.count
        )
    }

    private struct NewWords: Encodable {
        struct Level: Encodable { let id: String; let label: String; let count: Int }
        struct Word: Encodable { let word: String; let level: String; let back: String; let card: StructuredCard? }
        let levels: [Level]
        let knownCount: Int
        let total: Int
        let words: [Word]
    }

    private var inStoreTerms: Set<String> {
        Set((store()?.records ?? []).filter(\.isSaved).map { VocabPack.normalize(LearnCard.Encounter.split($0.sourceText).term) })
    }

    /// The Mac's Learn New Words queue. Only the head is sent; the phone asks again when it runs out.
    private func newWords(filter raw: String) -> NewWords {
        VocabProgressStore.shared.load()
        let progress = VocabProgressStore.shared.progress
        let entries = VocabPack.shared.allEntries()
        let inStore = inStoreTerms
        let remaining = VocabDiscovery.remainingByLevel(entries: entries, progress: progress, inStore: inStore)
        let levels = [NewWords.Level(id: "all", label: "All Levels", count: remaining.values.reduce(0, +))]
            + VocabDiscovery.Level.allCases.compactMap { level in
                remaining[level].map { NewWords.Level(id: level.rawValue, label: level.label, count: $0) }
            }
            + [NewWords.Level(id: "known", label: "Known", count: progress.known.count)]
        let filter = VocabDiscovery.Filter(rawValue: raw) ?? .all
        let queue: [VocabPackEntry]
        switch filter {
        case .known: queue = VocabDiscovery.knownQueue(entries: entries, progress: progress)
        case .level(let level): queue = VocabDiscovery.queue(entries: entries, level: level, progress: progress, inStore: inStore)
        case .all: queue = VocabDiscovery.queue(entries: entries, level: nil, progress: progress, inStore: inStore)
        }
        // ponytail: 40 per batch keeps the payload small; the phone refetches at the end.
        let words = queue.prefix(40).map {
            NewWords.Word(word: $0.w, level: VocabDiscovery.level(of: $0.r).label, back: $0.r, card: StructuredCard($0.r))
        }
        return NewWords(levels: levels, knownCount: progress.known.count, total: queue.count, words: Array(words))
    }

    /// Known / Unmark known / Skip / Learn, with the same side effects as the Mac buttons.
    private func decideNewWord(_ body: Data, _ reply: Reply) {
        struct Payload: Decodable { let word: String; let decision: String }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body), let store = store() else {
            return reply(400, "text/plain", Data("Bad request".utf8))
        }
        let progress = VocabProgressStore.shared
        switch payload.decision {
        case "known": progress.record(.known, word: payload.word)
        case "unknown": progress.unmarkKnown(word: payload.word)
        case "skip": progress.record(.skipped, word: payload.word)
        case "learn":
            let key = VocabPack.normalize(payload.word)
            guard let entry = VocabPack.shared.allEntries().first(where: { VocabPack.normalize($0.w) == key }) else {
                return reply(404, "text/plain", Data("Not in the pack".utf8))
            }
            let record = TranslationRecord(
                id: UUID(), timestamp: Date(), mode: .learn, sourceText: entry.w, resultText: entry.r,
                sourceLanguage: VocabPack.shared.packSourceLanguage.isEmpty ? "English" : VocabPack.shared.packSourceLanguage,
                targetLanguage: config()?.targetLang ?? "Vietnamese", isSaved: false
            )
            do {
                let stored = try store.appendIfAbsent(record)
                try store.setSaved(true, recordID: stored.id)
            } catch {
                return reply(500, "text/plain", Data(error.localizedDescription.utf8))
            }
            progress.clearSkip(word: entry.w)
            progress.unmarkKnown(word: entry.w)
        default: return reply(400, "text/plain", Data("Bad request".utf8))
        }
        json(["ok": true], reply)
    }

    // MARK: - Passages

    private struct PassageSummary: Encodable {
        let key: String
        let title: String
        let group: String?
        let isDone: Bool
        let subtitle: String
        let count: Int
    }

    private struct PassageDetail: Encodable {
        struct Turn: Encodable { let speaker: String; let source: String; let translation: String }
        let title: String
        let turns: [Turn]
        let text: String
        let words: [String]
        let scenario: String?
        let isDone: Bool
    }

    private static func title(of passage: WeavePassage) -> String {
        passage.title ?? ReadingDialogue.parse(passage.text)?.topic ?? passage.words.joined(separator: ", ")
    }

    private func passages() -> [PassageSummary] {
        WeaveCache.entries()
            .sorted { $0.passage.generatedAt > $1.passage.generatedAt }
            .map { entry in
                let passage = entry.passage
                let count = passage.count ?? 0
                // Same subtitle as the Mac list row.
                var parts = ["\(passage.words.count) words", DateFormatter.localizedString(from: passage.generatedAt, dateStyle: .medium, timeStyle: .short)]
                if let group = passage.group, !group.isEmpty { parts.insert(group, at: 0) }
                parts.append(count == 1 ? "Studied 1 time" : "Studied \(count) times")
                return PassageSummary(key: entry.key, title: Self.title(of: passage), group: passage.group, isDone: passage.isDone ?? false,
                                      subtitle: parts.joined(separator: " · "), count: count)
            }
    }

    private func passage(key: String) -> PassageDetail? {
        // Keys are hex digests; refusing anything else keeps the path inside the weave folder.
        guard key.allSatisfy(\.isHexDigit), let passage = WeaveCache.load(key: key) else { return nil }
        let turns = ReadingDialogue.parse(passage.text)?.turns.map {
            PassageDetail.Turn(speaker: $0.speaker, source: $0.source, translation: $0.translation)
        } ?? []
        return PassageDetail(title: Self.title(of: passage), turns: turns, text: passage.text, words: passage.words,
                             scenario: passage.scenario, isDone: passage.isDone ?? false)
    }

    /// The list row actions from the Mac: done (which also counts a study, like finishing on the
    /// Mac), not done, reset count, delete.
    private func updatePassage(_ body: Data, _ reply: Reply) {
        struct Payload: Decodable { let key: String; let action: String }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body),
              payload.key.allSatisfy(\.isHexDigit), var passage = WeaveCache.load(key: payload.key) else {
            return reply(400, "text/plain", Data("Bad request".utf8))
        }
        switch payload.action {
        case "done":
            passage.isDone = true
            passage.count = (passage.count ?? 0) + 1
        case "undone": passage.isDone = false
        case "reset": passage.count = 0
        case "delete":
            WeaveCache.delete(key: payload.key)
            return json(["ok": true], reply)
        default: return reply(400, "text/plain", Data("Bad request".utf8))
        }
        WeaveCache.store(passage, key: payload.key)
        json(["ok": true], reply)
    }

    /// Create Dialogue: same cache key and prompt as the Mac, so the passage lands in the shared list.
    private func weave(_ body: Data, _ reply: @escaping Reply) {
        struct Payload: Decodable { let words: [String]; let scenario: String? }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body) else {
            return reply(400, "text/plain", Data("Bad request".utf8))
        }
        let words = payload.words.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let scenario = payload.scenario?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard !words.isEmpty || scenario != nil else { return reply(400, "text/plain", Data("Add words or a scenario".utf8)) }
        guard let translator = translator(), let config = config() else { return reply(503, "text/plain", Data("API key is not set".utf8)) }
        let key = WeaveCache.cacheKey(words: words, promptVersion: AppConfig.weavePromptVersion,
                                      prompt: config.weavePrompt + (scenario.map { "\n" + $0 } ?? ""))
        if WeaveCache.load(key: key) != nil { return json(["key": key], reply) }
        _ = translator.weave(words, sourceLang: "English", targetLang: config.targetLang, scenario: scenario) { result in
            Task { @MainActor in
                switch result {
                case let .success(text):
                    let passage = WeavePassage(words: words, text: text, promptVersion: AppConfig.weavePromptVersion,
                                               generatedAt: Date(), scenario: scenario)
                    WeaveCache.store(passage, key: key)
                    self.json(["key": key], reply)
                case let .failure(error):
                    reply(502, "text/plain", Data(error.localizedDescription.utf8))
                }
            }
        }
    }

    // MARK: - Translate

    private struct TranslatePayload: Decodable {
        let text: String
        let mode: String
        let target: String
        let source: String?
    }

    private struct TranslateReply: Encodable {
        let text: String
        let sourceLanguage: String
        var card: StructuredCard? = nil
        var id: String? = nil
        var isSaved = false
    }

    /// Logs a phone lookup in History the way the Mac popover does; a repeat reuses the old record.
    private func record(_ payload: TranslatePayload, mode: TranslationMode, result: String, sourceLanguage: String) -> TranslationRecord? {
        try? store()?.appendIfAbsent(TranslationRecord(
            id: UUID(), timestamp: Date(), mode: mode, sourceText: payload.text, resultText: result,
            sourceLanguage: sourceLanguage, targetLanguage: payload.target, isSaved: false
        ))
    }

    /// Translate auto-detects the source; Learn always explains an English term in `target`.
    private func translate(_ body: Data, _ reply: @escaping Reply) {
        guard let payload = try? JSONDecoder().decode(TranslatePayload.self, from: body),
              !payload.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return reply(400, "text/plain", Data("Bad request".utf8))
        }
        // Same reuse as the Mac popover: a history hit (or a vocab pack card) answers without the LLM.
        let learn = payload.mode == "learn"
        let source = learn ? "English" : payload.source ?? LanguageDetector.autoDetect
        let auto = source == LanguageDetector.autoDetect
        if let hit = store()?.reusableRecord(mode: learn ? .learn : .translate, sourceText: payload.text,
                                             sourceLanguage: source, targetLanguage: payload.target, sourceIsAutoDetect: auto) {
            return json(TranslateReply(text: hit.resultText, sourceLanguage: hit.sourceLanguage, card: learn ? StructuredCard(hit.resultText) : nil,
                                       id: hit.id.uuidString, isSaved: hit.isSaved), reply)
        }
        let term = payload.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        if learn, Translator.isDictionaryTerm(term),
           let packed = VocabPack.shared.lookup(term, sourceLanguage: source, targetLanguage: payload.target, sourceIsAutoDetect: false) {
            let stored = record(payload, mode: .learn, result: packed, sourceLanguage: source)
            return json(TranslateReply(text: packed, sourceLanguage: source, card: StructuredCard(packed),
                                       id: stored?.id.uuidString, isSaved: stored?.isSaved ?? false), reply)
        }
        guard let translator = translator() else { return reply(503, "text/plain", Data("API key is not set".utf8)) }
        let fail: @Sendable (Error) -> Void = { error in
            Task { @MainActor in reply(502, "text/plain", Data(error.localizedDescription.utf8)) }
        }
        if payload.mode == "learn" {
            translator.learn(payload.text, sourceLang: "English", targetLang: payload.target) { result in
                switch result {
                case let .success(text):
                    Task { @MainActor in
                        let stored = self.record(payload, mode: .learn, result: text, sourceLanguage: "English")
                        self.json(TranslateReply(text: text, sourceLanguage: "English", card: StructuredCard(text),
                                                 id: stored?.id.uuidString, isSaved: stored?.isSaved ?? false), reply)
                    }
                case let .failure(error): fail(error)
                }
            }
        } else {
            translator.translate(payload.text, sourceLang: payload.source ?? LanguageDetector.autoDetect, targetLang: payload.target, stream: false) { result in
                switch result {
                case let .success(value):
                    Task { @MainActor in
                        let stored = self.record(payload, mode: .translate, result: value.text, sourceLanguage: value.sourceLanguage)
                        self.json(TranslateReply(text: value.text, sourceLanguage: value.sourceLanguage,
                                                 id: stored?.id.uuidString, isSaved: stored?.isSaved ?? false), reply)
                    }
                case let .failure(error): fail(error)
                }
            }
        }
    }

    // MARK: - History and Ask

    private struct HistoryItem: Encodable {
        let id: String
        let source: String
        let result: String
        let mode: String
        let target: String
        let isSaved: Bool
        let date: String
        let card: StructuredCard?

        /// The list skips the card parse and sends a short preview; opening a row fetches it `full`.
        init(_ record: TranslationRecord, full: Bool) {
            let card = record.mode == .learn ? StructuredCard(record.resultText) : nil
            id = record.id.uuidString; source = record.sourceText
            mode = record.mode == .learn ? "learn" : "translate"; target = record.targetLanguage; isSaved = record.isSaved
            date = DateFormatter.localizedString(from: max(record.timestamp, record.openedAt), dateStyle: .medium, timeStyle: .short)
            self.card = full ? card : nil
            let gloss = card?.meanings.map(\.gloss).joined(separator: "; ") ?? ""
            result = full ? record.resultText : String((gloss.isEmpty ? record.resultText : gloss).prefix(160))
        }
    }

    /// Same filter and order as the Mac history window.
    private func history(query: String, savedOnly: Bool) -> [HistoryItem] {
        // ponytail: first 100 matches; search narrows the rest.
        HistoryWindowController.filter(records: store()?.records ?? [], query: query, savedOnly: savedOnly).prefix(100).map { HistoryItem($0, full: false) }
    }

    private func updateRecord(_ body: Data, _ reply: Reply) {
        struct Payload: Decodable { let id: String; let action: String }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body),
              let id = UUID(uuidString: payload.id), let store = store() else {
            return reply(400, "text/plain", Data("Bad request".utf8))
        }
        do {
            switch payload.action {
            case "save": try store.setSaved(true, recordID: id)
            case "unsave": try store.setSaved(false, recordID: id)
            case "delete": try store.remove(recordID: id)
            default: return reply(400, "text/plain", Data("Bad request".utf8))
            }
            json(["ok": true], reply)
        } catch {
            reply(500, "text/plain", Data(error.localizedDescription.utf8))
        }
    }

    /// Follow-up question about a translation, with the same prompt as the Mac Ask pane.
    private func ask(_ body: Data, _ reply: @escaping Reply) {
        struct Turn: Decodable { let question: String; let answer: String }
        struct Payload: Decodable { let question: String; let source: String; let result: String; let target: String; let sourceLang: String?; let history: [Turn] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: body),
              !payload.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return reply(400, "text/plain", Data("Bad request".utf8))
        }
        guard let translator = translator() else { return reply(503, "text/plain", Data("API key is not set".utf8)) }
        translator.ask(payload.question, sourceText: payload.source, translatedText: payload.result,
                       sourceLang: payload.sourceLang ?? "English", targetLang: payload.target,
                       history: payload.history.map { QATurn(question: $0.question, answer: $0.answer) }) { result in
            Task { @MainActor in
                switch result {
                case let .success(text): self.json(["text": text], reply)
                case let .failure(error): reply(502, "text/plain", Data(error.localizedDescription.utf8))
                }
            }
        }
    }

    // MARK: - Images

    /// Two related photos, reusing the Mac's caches: the sense queries the model wrote for this
    /// term, then the image URLs found for them. A term the Mac never showed is searched as is.
    private func images(term: String, _ reply: @escaping Reply) {
        let key = LearnCard.normalizeAnswer(term)
        guard !key.isEmpty else { return json([String](), reply) }
        let senses = (UserDefaults.standard.dictionary(forKey: LearnRelatedImageStrip.rewriteCacheKey) as? [String: String])?[key]
            .map { LearnRelatedImage.senseQueries(from: $0) } ?? []
        let queries = senses.isEmpty ? [key] : senses
        let cacheKey = queries.map(LearnCard.normalizeAnswer).joined(separator: "\n")
        if let cached = (UserDefaults.standard.dictionary(forKey: LearnRelatedImageStrip.urlCacheKey) as? [String: [String]])?[cacheKey], !cached.isEmpty {
            return json(cached, reply)
        }
        // ponytail: one query on a cache miss; the Mac's per-sense rewrite needs the model.
        let task = LearnRelatedImageStrip.lookup(query: queries[0], limit: LearnRelatedImage.thumbnailCount) { urls in
            Task { @MainActor in
                let picks = urls.map(\.absoluteString)
                if !picks.isEmpty {
                    var cache = UserDefaults.standard.dictionary(forKey: LearnRelatedImageStrip.urlCacheKey) as? [String: [String]] ?? [:]
                    if cache.count >= 2000 { cache.removeAll() }
                    cache[LearnCard.normalizeAnswer(queries[0])] = picks
                    UserDefaults.standard.set(cache, forKey: LearnRelatedImageStrip.urlCacheKey)
                }
                self.json(picks, reply)
            }
        }
        if task == nil { json([String](), reply) }
    }

    // MARK: - Audio

    /// Card audio comes from the record when it has some; dialogue lines share the reading cache,
    /// so a line spoken on the Mac plays on the phone for free and the other way round.
    private func audio(text: String, recordID: String?, language: String, _ reply: @escaping Reply) {
        if let recordID, let id = UUID(uuidString: recordID),
           let data = try? store()?.audioData(for: id, kind: .source), SpeechAudioPolicy.isValid(data) {
            return reply(200, "audio/mpeg", data)
        }
        guard !text.isEmpty, let config = config() else { return reply(400, "text/plain", Data()) }
        let model = SpeechModelResolver.model(for: language, config: config)
        if let data = WeaveAudioCache.load(text: text, model: model), SpeechAudioPolicy.isValid(data) {
            return reply(200, "audio/mpeg", data)
        }
        guard let translator = translator() else { return reply(503, "text/plain", Data("No speech engine".utf8)) }
        _ = translator.speak(text, model: model, speed: 1.0) { result in
            Task { @MainActor in
                guard let data = try? result.get(), SpeechAudioPolicy.isValid(data) else {
                    return reply(502, "text/plain", Data("Speech failed".utf8))
                }
                WeaveAudioCache.store(data, text: text, model: model)
                reply(200, "audio/mpeg", data)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
