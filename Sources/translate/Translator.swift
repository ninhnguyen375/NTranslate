import Foundation

struct TranslationResult: Equatable, Sendable {
    let text: String
    let sourceLanguage: String
}

final class Translator {
    private struct TranslationResponsePayload: Decodable {
        let translation: String
        let sourceLanguage: String
    }
    let config: AppConfig
    let apiKey: String

    enum ResponseError: Error {
        case invalidSchema
        case emptyContent
    }

    private enum RequestMode {
        case translate(sourceLang: String, targetLang: String)
        case learn(sourceLang: String, targetLang: String)
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
    }

    /// Source and target language are the same: user wants grammar-check, not translation.
    private func renderGrammarPrompt(lang: String) -> String {
        config.grammarPrompt
            .replacingOccurrences(of: "{{lang}}", with: lang)
            .replacingOccurrences(of: "{{config.nativeLang}}", with: config.resolvedNativeLang)
    }

    static func renderLearnPrompt(for text: String, sourceLang: String, targetLang: String, config: AppConfig) -> String {
        let template = text.split(whereSeparator: { $0.isWhitespace }).count == 1
            ? config.learnPrompt
            : config.sentenceLearnPrompt
        return template
            .replacingOccurrences(of: "{{config.sourceLang}}", with: sourceLang)
            .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
    }

    static let imageSearchPrompt = "Return only a short, concrete English query for Google Images. No quotes, no markdown, no filler."
    private static func autoDetectResponseContract(languages: [String]) -> String {
        let allowed = languages.filter { $0 != LanguageDetector.autoDetect }.joined(separator: ", ")
        return """

        Return exactly one JSON object with this shape: {"translation":"<translated text>","sourceLanguage":"<detected source language>"}. sourceLanguage must be one of: \(allowed). No markdown fence, intro, commentary, or extra keys.
        """
    }

    private func request(_ text: String, mode: RequestMode, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: config.apiBaseURL) else {
            completion(.failure(NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid apiBaseURL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let wrappedText = "<selected-text>\(text)</selected-text>"
        let systemPrompt: String
        switch mode {
        case let .translate(sourceLang, targetLang) where sourceLang == targetLang:
            systemPrompt = renderGrammarPrompt(lang: targetLang)
        case let .translate(sourceLang, targetLang):
            systemPrompt = renderSystemPrompt(sourceLang: sourceLang, targetLang: targetLang)
                + (sourceLang == LanguageDetector.autoDetect ? Self.autoDetectResponseContract(languages: config.languages) : "")
        case .imageSearch:
            systemPrompt = Self.imageSearchPrompt
        case let .learn(sourceLang, targetLang):
            systemPrompt = Self.renderLearnPrompt(
                for: text,
                sourceLang: sourceLang,
                targetLang: targetLang,
                config: config
            )
        }
        do {
            req.httpBody = try Self.requestPayload(model: config.model, systemPrompt: systemPrompt, userContent: wrappedText)
        } catch {
            completion(.failure(error))
            return
        }
        perform(req, completion: completion)
    }

    private func perform(_ req: URLRequest, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(NSError(domain: "HTTP", code: 0)))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                return
            }
            do {
                completion(.success(try Self.responseContent(from: data)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    static func requestPayload(model: String, systemPrompt: String, userContent: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ])
    }

    static func imageSystemPrompt(targetLang: String, config: AppConfig) -> String {
        config.systemPrompt
            .replacingOccurrences(of: "{{config.sourceLang}}", with: LanguageDetector.autoDetect)
            .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
    }

    static func imageRequestPayload(pngData: Data, targetLang: String, systemPrompt: String, model: String) throws -> Data {
        let instruction = "Translate all readable text in this image into \(targetLang). Return only the translation."
        return try requestPayload(model: model, systemPrompt: systemPrompt, userContent: [
            ["type": "text", "text": instruction],
            ["type": "image_url", "image_url": ["url": "data:image/png;base64,\(pngData.base64EncodedString())"]]
        ])
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

    func translate(_ text: String, sourceLang: String, targetLang: String, completion: @escaping @Sendable (Result<TranslationResult, Error>) -> Void) {
        request(text, mode: .translate(sourceLang: sourceLang, targetLang: targetLang)) { [config] result in
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

    func learn(_ text: String, sourceLang: String, targetLang: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        request(text, mode: .learn(sourceLang: sourceLang, targetLang: targetLang), completion: completion)
    }

    func imageSearchQuery(_ text: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        request(text, mode: .imageSearch, completion: completion)
    }

    func translateImage(_ pngData: Data, targetLang: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        guard let url = URL(string: config.apiBaseURL) else {
            completion(.failure(NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid apiBaseURL"])))
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            req.httpBody = try Self.imageRequestPayload(
                pngData: pngData,
                targetLang: targetLang,
                systemPrompt: Self.imageSystemPrompt(targetLang: targetLang, config: config),
                model: config.model
            )
        } catch {
            completion(.failure(error))
            return
        }
        perform(req, completion: completion)
    }

    func speak(_ text: String, model: String, completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
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
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model,
            "input": trimmed
        ])
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(error)); return }
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure(NSError(domain: "HTTP", code: 0)))
                return
            }
            guard (200...299).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(NSError(domain: "HTTP", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])))
                return
            }
            completion(.success(data))
        }.resume()
    }
}
