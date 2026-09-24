import Foundation

/// Ask with web tools: OpenAI-compatible function calling where the model decides whether to call
/// `web_search` / `web_fetch`. Both tools hit the same gateway as chat (`/v1/search`,
/// `/v1/web/fetch` on the `apiBaseURL` host) with the same API key.
// ponytail: hand-rolled loop (~100 lines) instead of an agent SDK; no Swift harness is lighter than this.
extension Translator {
    nonisolated(unsafe) static let askTools: [[String: Any]] = [
        [
            "type": "function",
            "function": [
                "name": "web_search",
                "description": "Search the web for current or factual information. Returns titles, URLs and snippets.",
                "parameters": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Search query"],
                        "max_results": ["type": "integer", "description": "Number of results, 1-10 (default 5)"],
                    ],
                    "required": ["query"],
                ],
            ],
        ],
        [
            "type": "function",
            "function": [
                "name": "web_fetch",
                "description": "Fetch a web page as markdown. Use when search snippets are not enough.",
                "parameters": [
                    "type": "object",
                    "properties": ["url": ["type": "string", "description": "Absolute http(s) URL"]],
                    "required": ["url"],
                ],
            ],
        ],
    ]

    /// Max model rounds before giving up, so a model that keeps calling tools cannot loop forever.
    static let askToolMaxRounds = 6
    /// Tool output handed back to the model is capped; a full page can blow the context window.
    static let askToolResultLimit = 20_000

    /// `images` are PNG data attached to the latest question only; history stays text.
    /// `onStatus` reports tool activity ("Searching: ..."); the final answer arrives in `completion`.
    @discardableResult
    func chatWithTools(
        _ question: String,
        images: [Data],
        history: [QATurn],
        model: String?,
        webTools: Bool,
        onStatus: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) -> RequestHandle {
        var messages: [[String: Any]] = history.flatMap {
            [["role": "user", "content": $0.question], ["role": "assistant", "content": $0.answer]]
        }
        messages.append(["role": "user", "content": Self.userContent(question, images: images)])
        let loop = ToolLoop(
            translator: self,
            model: model ?? (config.askModel.isEmpty ? config.model : config.askModel),
            messages: messages,
            webTools: webTools,
            onStatus: onStatus,
            completion: completion
        )
        loop.step(round: 0)
        return loop.handle
    }

    static func userContent(_ text: String, images: [Data]) -> Any {
        guard !images.isEmpty else { return text }
        return [["type": "text", "text": text]] + images.map {
            ["type": "image_url", "image_url": ["url": "data:image/png;base64,\($0.base64EncodedString())"]]
        }
    }

    /// `/v1/chat/completions` on the same host becomes `/v1/search` or `/v1/web/fetch`.
    func gatewayURL(_ path: String) -> URL? {
        guard let base = URL(string: config.apiBaseURL) else { return nil }
        return URL(string: path, relativeTo: base)?.absoluteURL
    }

    func jsonRequest(_ url: URL, body: [String: Any]) throws -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = Self.requestTimeoutInterval
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }
}

/// State of one Ask exchange across tool rounds. Rounds run strictly one after another, so the
/// mutable `messages` is never touched concurrently.
private final class ToolLoop: @unchecked Sendable {
    let handle = RequestHandle()
    private let translator: Translator
    private let model: String
    private var messages: [[String: Any]]
    private let webTools: Bool
    private let onStatus: @Sendable (String) -> Void
    private let completion: @Sendable (Result<String, Error>) -> Void

    init(
        translator: Translator, model: String, messages: [[String: Any]], webTools: Bool,
        onStatus: @escaping @Sendable (String) -> Void,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        self.translator = translator
        self.model = model
        self.messages = messages
        self.webTools = webTools
        self.onStatus = onStatus
        self.completion = completion
    }

    func step(round: Int) {
        guard let url = URL(string: translator.config.apiBaseURL) else {
            return fail("Invalid API base URL")
        }
        var body: [String: Any] = ["model": model, "stream": false, "messages": messages]
        // Last round: no tools offered, so the model has to answer with what it has.
        if webTools, round < Translator.askToolMaxRounds - 1 { body["tools"] = Translator.askTools }
        send(url, body) { [self] result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(object):
                guard let message = (object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any] else {
                    return completion(.failure(Translator.ResponseError.invalidSchema))
                }
                let calls = message["tool_calls"] as? [[String: Any]] ?? []
                if calls.isEmpty {
                    let text = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    return completion(text.isEmpty ? .failure(Translator.ResponseError.emptyContent) : .success(text))
                }
                var assistant = message
                assistant["content"] = message["content"] as? String ?? ""
                messages.append(assistant)
                runTools(calls, index: 0) { [self] in step(round: round + 1) }
            }
        }
    }

    private func runTools(_ calls: [[String: Any]], index: Int, done: @escaping @Sendable () -> Void) {
        guard index < calls.count else { return done() }
        let call = calls[index]
        let id = call["id"] as? String ?? "call_\(index)"
        let function = call["function"] as? [String: Any] ?? [:]
        let name = function["name"] as? String ?? ""
        let args = (function["arguments"] as? String).flatMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        } ?? [:]

        let path: String
        var body: [String: Any] = ["model": "exa"]
        switch name {
        case "web_search":
            let query = args["query"] as? String ?? ""
            onStatus("Searching: \(query)")
            path = "/v1/search"
            body["query"] = query
            body["search_type"] = "news"
            body["max_results"] = min(max(args["max_results"] as? Int ?? 5, 1), 10)
        case "web_fetch":
            let target = args["url"] as? String ?? ""
            onStatus("Reading: \(target)")
            path = "/v1/web/fetch"
            body["url"] = target
            body["format"] = "markdown"
            body["max_characters"] = Translator.askToolResultLimit
        default:
            appendToolResult(id, "Unknown tool \(name)")
            return runTools(calls, index: index + 1, done: done)
        }
        guard let url = translator.gatewayURL(path) else { return fail("Invalid API base URL") }
        nonisolated(unsafe) let calls = calls
        send(url, body, raw: true) { [self] result in
            let output: String
            switch result {
            case let .success(object): output = object["raw"] as? String ?? ""
            case let .failure(error):
                if (error as NSError).code == NSURLErrorCancelled { return completion(.failure(error)) }
                output = "Tool error: \(error.localizedDescription)"
            }
            appendToolResult(id, String(output.prefix(Translator.askToolResultLimit)))
            runTools(calls, index: index + 1, done: done)
        }
    }

    private func appendToolResult(_ id: String, _ content: String) {
        messages.append(["role": "tool", "tool_call_id": id, "content": content])
    }

    /// Posts JSON; `raw` hands back the body text under `"raw"` (tool results go to the model as-is).
    private func send(
        _ url: URL, _ body: [String: Any], raw: Bool = false,
        then: @escaping @Sendable (Result<[String: Any], Error>) -> Void
    ) {
        let req: URLRequest
        do { req = try translator.jsonRequest(url, body: body) } catch { return then(.failure(error)) }
        let task = URLSession.shared.dataTask(with: req) { [handle] data, response, error in
            handle.clear()
            if let error { return then(.failure(error)) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200...299).contains(status), let data else {
                return then(.failure(NSError(domain: "HTTP", code: status, userInfo: [
                    NSLocalizedDescriptionKey: Translator.httpErrorDescription(status: status),
                ])))
            }
            if raw { return then(.success(["raw": String(decoding: data, as: UTF8.self)])) }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return then(.failure(Translator.ResponseError.invalidSchema))
            }
            then(.success(object))
        }
        handle.adopt(task)
        task.resume()
    }

    private func fail(_ message: String) {
        completion(.failure(NSError(domain: "Config", code: 1, userInfo: [NSLocalizedDescriptionKey: message])))
    }
}
