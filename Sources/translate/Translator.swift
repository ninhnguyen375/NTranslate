import Foundation

final class Translator {
    let config: AppConfig
    let apiKey: String

    private enum RequestMode {
        case translate(sourceLang: String, targetLang: String)
        case learn(sourceLang: String, targetLang: String)
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

    private func renderLearnPrompt(sourceLang: String, targetLang: String) -> String {
        config.learnPrompt
            .replacingOccurrences(of: "{{config.sourceLang}}", with: sourceLang)
            .replacingOccurrences(of: "{{config.targetLang}}", with: targetLang)
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
        case let .learn(sourceLang, targetLang):
            systemPrompt = renderLearnPrompt(sourceLang: sourceLang, targetLang: targetLang)
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": config.model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": wrappedText]
            ]
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
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let content = (((obj?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
            completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
        }.resume()
    }

    func translate(_ text: String, sourceLang: String, targetLang: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        request(text, mode: .translate(sourceLang: sourceLang, targetLang: targetLang), completion: completion)
    }

    func learn(_ text: String, sourceLang: String, targetLang: String, completion: @escaping @Sendable (Result<String, Error>) -> Void) {
        request(text, mode: .learn(sourceLang: sourceLang, targetLang: targetLang), completion: completion)
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
