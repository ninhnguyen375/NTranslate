import Foundation

struct TranslationResult: Equatable, Sendable {
    let text: String
    let sourceLanguage: String
}

/// One earlier question/answer pair in a Q&A conversation.
struct QATurn: Equatable, Sendable {
    let question: String
    let answer: String
}

/// One earlier translation handed to the model as reference context.
struct ContextPair: Equatable, Sendable {
    let source: String
    let target: String
}

final class Translator: @unchecked Sendable {
    private struct TranslationResponsePayload: Decodable {
        let translation: String
        let sourceLanguage: String
    }
    let config: AppConfig
    let apiKey: String
    private let lock = NSLock()
    private(set) var inFlightTask: URLSessionTask?
    private var streamSession: URLSession?
    private var streamDelegate: StreamCollector?

    enum ResponseError: Error {
        case invalidSchema
        case emptyContent
    }

    func cancelInFlight() {
        lock.lock()
        let task = inFlightTask
        inFlightTask = nil
        lock.unlock()
        task?.cancel()
    }

    private enum RequestMode {
        case translate(sourceLang: String, targetLang: String, context: [ContextPair], parentContext: String?)
        case learn(sourceLang: String, targetLang: String, parentContext: String?)
        case proofread(lang: String)
        case ask(question: String, sourceText: String, translatedText: String, sourceLang: String, targetLang: String, history: [QATurn], parentContext: String?)
        case imageSearch
    }

    init(config: AppConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    private func renderSystemPrompt(sourceLang: String, targetLang: String) -> String {
        config.systemPrompt
            .replacingOccurrences(of: "{{config.sourceLang}}", with: sourceLang)
            .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
            .replacingOccurrences(of: "{{config.nativeLang}}", with: config.resolvedNativeLang)
    }

    /// Proofread mode: grammar-check the text in its own language instead of translating it.
    private func renderGrammarPrompt(lang: String) -> String {
        config.grammarPrompt
            .replacingOccurrences(of: "{{lang}}", with: lang)
            .replacingOccurrences(of: "{{config.nativeLang}}", with: config.resolvedNativeLang)
    }

    private func renderQAPrompt(sourceText: String, translatedText: String, sourceLang: String, targetLang: String) -> String {
        config.qaPrompt
            .replacingOccurrences(of: "{{sourceText}}", with: sourceText)
            .replacingOccurrences(of: "{{translatedText}}", with: translatedText)
            .replacingOccurrences(of: "{{config.sourceLang}}", with: sourceLang)
            .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
    }

    /// Earlier Q&A turns, so a follow-up question can refer back to them.
    static func qaHistoryBlock(_ history: [QATurn]) -> String {
        guard !history.isEmpty else { return "" }
        let lines = history.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
        return """

        <earlier-qa>
        \(lines)
        </earlier-qa>

        The block above is this same conversation's earlier questions and your answers. Use it to resolve references in the new question ("that word", "the second one", "why not?") and do not repeat what you already said.
        """
    }

    static let dictionaryTermCharacterLimit = 40
    static let requestTimeoutInterval: TimeInterval = 30

    /// ASCII plus CJK sentence punctuation. A Chinese sentence has no spaces, so word-count
    /// alone would treat it as a single dictionary term.
    private static let dictionaryTermPunctuation = CharacterSet(charactersIn: ".?!,;:。，、？！；：「」『』（）")

    /// Dictionary-card routing: a short Latin word/compound, or a short CJK term without sentence punctuation.
    static func isDictionaryTerm(_ text: String) -> Bool {
        guard text.count <= dictionaryTermCharacterLimit else { return false }
        guard !text.contains(where: { $0.isNewline }) else { return false }
        guard text.unicodeScalars.allSatisfy({ !dictionaryTermPunctuation.contains($0) }) else { return false }
        let words = text.split(whereSeparator: { $0.isWhitespace })
        return words.count >= 1 && words.count <= 3
    }

    static func renderLearnPrompt(for text: String, sourceLang: String, targetLang: String, config: AppConfig) -> String {
        let template = isDictionaryTerm(text) ? config.learnPrompt : config.sentenceLearnPrompt
        return template
            .replacingOccurrences(of: "{{config.sourceLang}}", with: sourceLang)
            .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
    }

    /// Each side is capped so a long history can't crowd out the actual instructions.
    static let contextEntryCharacterLimit = 200

    /// Reference block appended to the translate system prompt. Empty when there is no history.
    static func contextBlock(_ pairs: [ContextPair]) -> String {
        guard !pairs.isEmpty else { return "" }
        let lines = pairs.enumerated().map { index, pair in
            "\(index + 1). \(truncate(pair.source)) => \(truncate(pair.target))"
        }.joined(separator: "\n")
        return """


        <translation-context>
        \(lines)
        </translation-context>

        The block above lists earlier translations from this same session, oldest meaning last. It is REFERENCE ONLY — it is not part of the text to translate.
        Use it to keep terminology, named entities, register, tone, and forms of address consistent with those earlier translations, so this translation reads naturally as a continuation of the same material.
        Never translate, quote, summarize, or otherwise include any content from this block in your output. Translate only the text inside <selected-text>. If the context conflicts with the selected text, the selected text wins.
        """
    }

    private static func truncate(_ text: String) -> String {
        let flattened = text
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > contextEntryCharacterLimit else { return flattened }
        return flattened.prefix(contextEntryCharacterLimit) + "…"
    }

    static let imageSearchPrompt = "Return only a short, concrete English query for Google Images. No quotes, no markdown, no filler."
    private static func autoDetectResponseContract(languages: [String]) -> String {
        let allowed = languages.filter { $0 != LanguageDetector.autoDetect }.joined(separator: ", ")
        return """

        Return exactly one JSON object with this shape: {"translation":"<translated text>","sourceLanguage":"<detected source language>"}. sourceLanguage must be one of: \(allowed). No markdown fence, intro, commentary, or extra keys.
        """
    }

    /// Subtranslate context block when translating a sub-phrase from a larger parent text.
    static func parentContextBlock(_ parentText: String?) -> String {
        guard let parent = parentText?.trimmingCharacters(in: .whitespacesAndNewlines), !parent.isEmpty else { return "" }
        return """


        <full-context-sentence>
        \(parent)
        </full-context-sentence>

        The text to translate (<selected-text>) is a specific phrase or word excerpted from the full sentence/paragraph above (<full-context-sentence>).
        Translate only the text inside <selected-text>, but select the precise meaning, nuance, and terminology that fits its role and context in <full-context-sentence>.
        """
    }

    /// Surrounding main-pane translation when the question is about a sub-excerpt.
    static func qaParentContextBlock(_ parentText: String?) -> String {
        guard let parent = parentText?.trimmingCharacters(in: .whitespacesAndNewlines), !parent.isEmpty else { return "" }
        return """


        <parent-translation>
        \(parent)
        </parent-translation>

        The question is about the excerpt in the source/translation fields below. Use <parent-translation> as the surrounding sentence or paragraph from the main pane.
        """
    }

    private func request(
        _ text: String,
        mode: RequestMode,
        stream: Bool = true,
        replaceInFlight: Bool = true,
        onPartial: (@Sendable (String) -> Void)? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        guard let url = URL(string: config.apiBaseURL) else {
            completion(.failure(NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid API base URL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.requestTimeoutInterval
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let wrappedText = "<selected-text>\(text)</selected-text>"
        let systemPrompt: String
        switch mode {
        case let .proofread(lang):
            systemPrompt = renderGrammarPrompt(lang: lang)
        case let .translate(sourceLang, targetLang, context, parentContext):
            systemPrompt = renderSystemPrompt(sourceLang: sourceLang, targetLang: targetLang)
                + (sourceLang == LanguageDetector.autoDetect ? Self.autoDetectResponseContract(languages: config.languages) : "")
                + Self.contextBlock(context)
                + Self.parentContextBlock(parentContext)
        case .imageSearch:
            systemPrompt = Self.imageSearchPrompt
        case let .ask(_, sourceText, translatedText, sourceLang, targetLang, history, parentContext):
            systemPrompt = renderQAPrompt(
                sourceText: sourceText,
                translatedText: translatedText,
                sourceLang: sourceLang,
                targetLang: targetLang
            ) + Self.qaParentContextBlock(parentContext) + Self.qaHistoryBlock(history)
        case let .learn(sourceLang, targetLang, parentContext):
            systemPrompt = Self.renderLearnPrompt(
                for: text,
                sourceLang: sourceLang,
                targetLang: targetLang,
                config: config
            ) + Self.parentContextBlock(parentContext)
        }
        do {
            req.httpBody = try Self.requestPayload(
                model: config.model,
                systemPrompt: systemPrompt,
                userContent: wrappedText,
                stream: stream
            )
        } catch {
            completion(.failure(error))
            return
        }
        perform(req, stream: stream, replaceInFlight: replaceInFlight, onPartial: onPartial, completion: completion)
    }

    private func perform(
        _ req: URLRequest,
        stream: Bool,
        replaceInFlight: Bool = true,
        onPartial: (@Sendable (String) -> Void)? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        if replaceInFlight { cancelInFlight() }
        if stream {
            performStream(req, onPartial: onPartial, completion: completion)
        } else {
            performData(req, replaceInFlight: replaceInFlight, completion: completion)
        }
    }

    private func performData(
        _ req: URLRequest,
        replaceInFlight: Bool = true,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        final class TaskBox: @unchecked Sendable {
            var task: URLSessionTask?
        }
        let box = TaskBox()
        let task = URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            if replaceInFlight, let current = box.task {
                self?.clearTaskIfCurrent(current)
            }
            Self.finishHTTP(data: data, response: response, error: error, completion: completion)
        }
        box.task = task
        if replaceInFlight {
            lock.lock()
            inFlightTask = task
            lock.unlock()
        }
        task.resume()
    }

    /// OpenAI-compat SSE (`data:` lines). If the body is a one-shot JSON object, fall back to `responseContent`.
    private func performStream(
        _ req: URLRequest,
        onPartial: (@Sendable (String) -> Void)?,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        let collector = StreamCollector()
        let session = URLSession(configuration: .default, delegate: collector, delegateQueue: nil)
        let task = session.dataTask(with: req)
        lock.lock()
        streamDelegate = collector
        streamSession = session
        inFlightTask = task
        lock.unlock()
        collector.onComplete = { [weak self] data, response, error in
            session.finishTasksAndInvalidate()
            self?.clearTaskIfCurrent(task)
            if let self {
                self.lock.lock()
                if self.streamSession === session {
                    self.streamSession = nil
                    self.streamDelegate = nil
                }
                self.lock.unlock()
            }
            if let error {
                completion(.failure(error))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "HTTP", code: 0)))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                completion(.failure(Self.httpError(status: http.statusCode, body: data)))
                return
            }
            if collector.sawSSE {
                let trimmed = collector.accumulated.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    completion(.failure(ResponseError.emptyContent))
                    return
                }
                completion(.success(trimmed))
                return
            }
            do {
                completion(.success(try Self.responseContent(from: data)))
            } catch {
                completion(.failure(error))
            }
        }
        collector.onPartial = onPartial
        task.resume()
    }

    private func clearTaskIfCurrent(_ task: URLSessionTask) {
        lock.lock()
        if inFlightTask === task {
            inFlightTask = nil
        }
        lock.unlock()
    }

    static func requestPayload(model: String, systemPrompt: String, userContent: Any, stream: Bool = true) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": stream,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ])
    }

    static func httpErrorDescription(status: Int) -> String {
        switch status {
        case 401: return "API key was rejected. Open Settings and check the key."
        case 403: return "The API refused this request."
        case 429: return "The API rate limit was reached. Try again in a moment."
        case 500...599: return "The translation service is unavailable (HTTP \(status))."
        default: return "The request failed (HTTP \(status))."
        }
    }

    private static func httpError(status: Int, body: Data) -> NSError {
        NSError(domain: "HTTP", code: status, userInfo: [NSLocalizedDescriptionKey: httpErrorDescription(status: status)])
    }

    private static func finishHTTP(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        if let error { completion(.failure(error)); return }
        guard let http = response as? HTTPURLResponse, let data else {
            completion(.failure(NSError(domain: "HTTP", code: 0)))
            return
        }
        guard (200...299).contains(http.statusCode) else {
            completion(.failure(httpError(status: http.statusCode, body: data)))
            return
        }
        do {
            completion(.success(try responseContent(from: data)))
        } catch {
            completion(.failure(error))
        }
    }

    static func sseDeltaContent(from jsonLine: String) -> String? {
        guard let data = jsonLine.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String
        else { return nil }
        return content
    }

    /// Image mode has its own prompt (`config.imagePrompt`): `config.systemPrompt` ends with "return
    /// only the replacement text", which contradicts the JSON contract and made the model flip
    /// between the two formats.
    static func imageSystemPrompt(targetLang: String, alternateLang: String, config: AppConfig) -> String {
        config.imagePrompt
            .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
            .replacingOccurrences(of: "{{config.alternateLang}}", with: alternateLang)
            .replacingOccurrences(of: "{{config.sourceLang}}", with: LanguageDetector.autoDetect)
            .replacingOccurrences(of: "{{config.nativeLang}}", with: config.resolvedNativeLang)
    }

    static let imageResponseContract = """
        Return exactly one JSON object with this shape, newlines inside the strings escaped as \\n:
        {"sourceLanguage":"<language of the transcription>","sourceText":"<verbatim transcription>","targetLanguage":"<language you translated into>","translation":"<the translation>"}
        """

    /// Image mode returns the transcription alongside the translation, so the source pane can be
    /// filled with real text and reuse the text-mode features (speak, subtranslate, Q&A, history).
    struct ImageTranslation: Equatable, Sendable {
        let sourceLanguage: String
        let sourceText: String
        let targetLanguage: String
        let translation: String
    }

    private struct ImageTranslationPayload: Decodable {
        let sourceLanguage: String?
        let sourceText: String
        let targetLanguage: String?
        let translation: String
    }

    static func imageTranslation(from content: String, supportedLanguages: [String] = LanguageDetector.defaultLanguages) throws -> ImageTranslation {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ResponseError.emptyContent }
        var payloadText = trimmed
        if payloadText.hasPrefix("```") {
            guard payloadText.hasSuffix("```") else { throw ResponseError.invalidSchema }
            payloadText.removeFirst(3)
            payloadText.removeLast(3)
            payloadText = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
            if payloadText.lowercased().hasPrefix("json") {
                payloadText.removeFirst(4)
                payloadText = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        // Older/cheaper models ignore the JSON contract; keep their plain text as the translation.
        guard payloadText.hasPrefix("{"),
              let data = payloadText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ImageTranslationPayload.self, from: data)
        else { return ImageTranslation(sourceLanguage: "", sourceText: "", targetLanguage: "", translation: trimmed) }
        let translation = payload.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = payload.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { throw ResponseError.emptyContent }
        return ImageTranslation(
            sourceLanguage: canonical(payload.sourceLanguage, fallbackFor: sourceText, supportedLanguages: supportedLanguages),
            sourceText: sourceText,
            targetLanguage: LanguageDetector.canonicalLanguage(payload.targetLanguage ?? "", supportedLanguages: supportedLanguages) ?? "",
            translation: translation
        )
    }

    private static func canonical(_ language: String?, fallbackFor text: String, supportedLanguages: [String]) -> String {
        LanguageDetector.canonicalLanguage(language ?? "", supportedLanguages: supportedLanguages)
            ?? (text.isEmpty ? "" : LanguageDetector.detectedLanguage(text))
    }

    static func imageRequestPayload(pngData: Data, targetLang: String, systemPrompt: String, model: String) throws -> Data {
        let instruction = "Transcribe this image, then translate the transcription. Requested target language: \(targetLang).\n\n" + imageResponseContract
        return try requestPayload(model: model, systemPrompt: systemPrompt, userContent: [
            ["type": "text", "text": instruction],
            ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(pngData.base64EncodedString())"]]
        ], stream: false)
    }

    static func responseContent(from data: Data) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw ResponseError.invalidSchema }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ResponseError.emptyContent }
        return trimmed
    }

    static func translationResult(
        from content: String,
        requestedSource: String,
        inputText: String,
        supportedLanguages: [String]
    ) throws -> TranslationResult {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ResponseError.emptyContent }
        if requestedSource != LanguageDetector.autoDetect {
            let source = LanguageDetector.canonicalLanguage(requestedSource, supportedLanguages: supportedLanguages)
                ?? requestedSource
            return TranslationResult(text: trimmed, sourceLanguage: source)
        }

        var payloadText = trimmed
        let fenced = payloadText.hasPrefix("```")
        if fenced {
            guard payloadText.hasSuffix("```") else { throw ResponseError.invalidSchema }
            payloadText.removeFirst(3)
            payloadText.removeLast(3)
            payloadText = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
            if payloadText.lowercased().hasPrefix("json") {
                payloadText.removeFirst(4)
                payloadText = payloadText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let isJSON = payloadText.data(using: .utf8).map {
            (try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed)) != nil
        } ?? false
        guard payloadText.first == "{" else {
            if fenced || isJSON || payloadText.first == "[" || payloadText.first == "\"" {
                throw ResponseError.invalidSchema
            }
            return TranslationResult(text: trimmed, sourceLanguage: LanguageDetector.detectedLanguage(inputText))
        }
        guard let data = payloadText.data(using: .utf8),
              let payload = try? JSONDecoder().decode(TranslationResponsePayload.self, from: data)
        else { throw ResponseError.invalidSchema }
        let translation = payload.translation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translation.isEmpty else { throw ResponseError.emptyContent }
        let source = LanguageDetector.canonicalLanguage(payload.sourceLanguage, supportedLanguages: supportedLanguages)
            ?? LanguageDetector.detectedLanguage(inputText)
        return TranslationResult(text: translation, sourceLanguage: source)
    }

    func translate(
        _ text: String,
        sourceLang: String,
        targetLang: String,
        context: [ContextPair] = [],
        parentContext: String? = nil,
        stream: Bool = true,
        replaceInFlight: Bool = true,
        onPartial: (@Sendable (String) -> Void)? = nil,
        completion: @escaping @Sendable (Result<TranslationResult, Error>) -> Void
    ) {
        request(
            text,
            mode: .translate(sourceLang: sourceLang, targetLang: targetLang, context: context, parentContext: parentContext),
            stream: stream,
            replaceInFlight: replaceInFlight,
            onPartial: onPartial
        ) { [config] result in
            completion(result.flatMap { content in
                Result {
                    try Self.translationResult(
                        from: content,
                        requestedSource: sourceLang,
                        inputText: text,
                        supportedLanguages: config.languages
                    )
                }
            })
        }
    }

    func learn(
        _ text: String,
        sourceLang: String,
        targetLang: String,
        parentContext: String? = nil,
        onPartial: (@Sendable (String) -> Void)? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        request(
            text,
            mode: .learn(sourceLang: sourceLang, targetLang: targetLang, parentContext: parentContext),
            onPartial: onPartial,
            completion: completion
        )
    }

    func proofread(
        _ text: String,
        lang: String,
        onPartial: (@Sendable (String) -> Void)? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        request(text, mode: .proofread(lang: lang), onPartial: onPartial, completion: completion)
    }

    func ask(
        _ question: String,
        sourceText: String,
        translatedText: String,
        sourceLang: String,
        targetLang: String,
        history: [QATurn] = [],
        parentContext: String? = nil,
        onPartial: (@Sendable (String) -> Void)? = nil,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        request(
            question,
            mode: .ask(
                question: question,
                sourceText: sourceText,
                translatedText: translatedText,
                sourceLang: sourceLang,
                targetLang: targetLang,
                history: history,
                parentContext: parentContext
            ),
            onPartial: onPartial,
            completion: completion
        )
    }

    func imageSearchQuery(_ text: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        request(text, mode: .imageSearch, stream: false, replaceInFlight: false, completion: completion)
    }

    func testConnection(completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        request("Reply with the single word OK.", mode: .imageSearch, stream: false) { result in
            completion(result.map { _ in () })
        }
    }

    func translateImage(_ pngData: Data, targetLang: String, completion: @escaping @Sendable (Result<ImageTranslation, Error>) -> Void) {
        guard let url = URL(string: config.apiBaseURL) else {
            completion(.failure(NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid apiBaseURL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.requestTimeoutInterval
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            req.httpBody = try Self.imageRequestPayload(
                pngData: pngData,
                targetLang: targetLang,
                systemPrompt: Self.imageSystemPrompt(
                    targetLang: targetLang,
                    alternateLang: LanguageDetector.fallbackTarget(
                        detected: targetLang,
                        targetLanguages: config.targetLanguages,
                        nativeLang: config.resolvedNativeLang
                    ),
                    config: config
                ),
                model: config.model
            )
        } catch {
            completion(.failure(error))
            return
        }
        perform(req, stream: false) { [config] result in
            completion(result.flatMap { content in
                Result { try Self.imageTranslation(from: content, supportedLanguages: config.languages) }
            })
        }
    }

    func speak(_ text: String, model: String, speed: Float? = nil, completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty text"])))
            return
        }
        guard let url = URL(string: config.apiSpeechURL) else {
            completion(.failure(NSError(domain: "Config", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid speech URL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.requestTimeoutInterval
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        var jsonPayload: [String: Any] = [
            "model": model,
            "input": trimmed
        ]
        if let speed {
            jsonPayload["speed"] = speed
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: jsonPayload)
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(NSError(domain: "HTTP", code: 0)))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                completion(.failure(Self.httpError(status: http.statusCode, body: data)))
                return
            }
            completion(.success(data))
        }.resume()
    }
}

/// Incremental SSE collector. Kept as a named type so the session delegate outlives the request.
private final class StreamCollector: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    var onPartial: (@Sendable (String) -> Void)?
    var onComplete: (@Sendable (Data, URLResponse?, Error?) -> Void)?
    private(set) var accumulated = ""
    private(set) var sawSSE = false
    private var buffer = Data()
    private var pendingBytes = Data()
    private var lineRemainder = ""
    private var response: URLResponse?
    private let lock = NSLock()

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        lock.lock()
        self.response = response
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        buffer.append(data)
        pendingBytes.append(data)
        let partial = consumePendingBytes(flushIncompleteLine: false)
        let callback = onPartial
        lock.unlock()
        if let partial { callback?(partial) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        consumePendingBytes(flushIncompleteLine: true)
        let complete = onComplete
        let body = buffer
        let captured = response ?? task.response
        lock.unlock()
        complete?(body, captured, error)
    }

    /// Decode a UTF-8 prefix, leaving an incomplete trailing sequence in `pendingBytes` so a
    /// multi-byte character split across TCP chunks is not dropped.
    /// Caller must hold `lock`. Returns the latest accumulated text when a new SSE delta arrived.
    @discardableResult
    private func consumePendingBytes(flushIncompleteLine: Bool) -> String? {
        let decoded: String
        if let whole = String(data: pendingBytes, encoding: .utf8) {
            decoded = whole
            pendingBytes = Data()
        } else {
            var prefix: String?
            var remainder = Data()
            for drop in 1...min(3, pendingBytes.count) {
                let head = pendingBytes.dropLast(drop)
                if let text = String(data: head, encoding: .utf8) {
                    prefix = text
                    remainder = Data(pendingBytes.suffix(drop))
                    break
                }
            }
            guard let text = prefix else { return nil }
            decoded = text
            pendingBytes = remainder
        }
        guard !decoded.isEmpty || flushIncompleteLine else { return nil }
        lineRemainder += decoded
        let lines = lineRemainder.split(separator: "\n", omittingEmptySubsequences: false)
        let endsWithNewline = lineRemainder.hasSuffix("\n")
        if flushIncompleteLine || endsWithNewline {
            lineRemainder = ""
        } else if let last = lines.last {
            lineRemainder = String(last)
        } else {
            lineRemainder = ""
        }
        let complete = (flushIncompleteLine || endsWithNewline) ? lines : lines.dropLast()
        var latest: String?
        for raw in complete {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("data:") else { continue }
            sawSSE = true
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { continue }
            if let delta = Translator.sseDeltaContent(from: payload) {
                accumulated += delta
                latest = accumulated
            }
        }
        return latest
    }
}
