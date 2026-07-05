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

    private func renderLearnPrompt(sourceLang: String, targetLang: String) -> String {
        """
        You are an English learning assistant for a Vietnamese learner.
        Explain the selected text in concise Vietnamese.
        If the selected text is not a single English word, extract the most useful English word or short phrase to learn.

        Return plain text only. No markdown. No intro. No commentary. No code fences.
        Follow this format exactly. Keep every item on its own line:

        IPA: /.../
        n. ...
        v. ...
        adj. ...

        Ví dụ
        - Example sentence.
          → Bản dịch tiếng Việt.
        - Example sentence.
          → Bản dịch tiếng Việt.

        Nhớ nhanh
        - ...
        - ...
        - ...

        Hard rules:
        - Omit any part of speech that does not fit.
        - Keep each meaning very short.
        - Examples must be natural and useful.
        - Each example sentence MUST start with "- " on its own line.
        - Each Vietnamese translation MUST be on the next line and start with "  → ".
        - Do not put meanings and examples on the same line.
        - Do not merge two examples into one paragraph.
        - Do not put any text after a meaning on the same line.
        - Put exactly one blank line between sections.
        - "Ví dụ" and "Nhớ nhanh" must each be on their own line.
        - In "Nhớ nhanh", explain the fastest way to grasp and remember the word.
        - Preserve line breaks exactly.
        - Output plain text only. Do not use markdown formatting such as **, *, #, _, [], or code fences.
        - Target learner language: Vietnamese.
        - Source language hint: \(sourceLang). Target language hint: \(targetLang).

        Good output example:
        IPA: /ˈɡræfɪks/
        n. đồ họa; hình ảnh máy tính.

        Ví dụ
        - High-quality graphics make the game look realistic.
          → Đồ họa chất lượng cao làm cho trò chơi trông chân thực.
        - The company specializes in computer graphics.
          → Công ty chuyên về đồ họa máy tính.

        Nhớ nhanh
        - Gốc liên tưởng: graph = vẽ, viết.
        - graphics = phần hình ảnh nhìn thấy trên màn hình.
        - Nhấn âm đầu: GRA-.
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

    func speak(_ text: String, model: String, completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(NSError(domain: "Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty text"])))
            return
        }
        guard let url = URL(string: config.speechURL) else {
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
            do {
                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("translate-speech-\(UUID().uuidString)")
                    .appendingPathExtension("mp3")
                try data.write(to: outputURL, options: .atomic)
                completion(.success(outputURL))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
