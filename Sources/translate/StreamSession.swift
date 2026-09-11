import Foundation

/// Per-request SSE parse state. Not a URLSession delegate: a shared router owns the session
/// callbacks and looks this up by `taskIdentifier`.
final class StreamCollector: @unchecked Sendable {
    var onPartial: (@Sendable (String) -> Void)?
    var onComplete: (@Sendable (Data, URLResponse?, Error?) -> Void)?
    private(set) var accumulated = ""
    private(set) var sawSSE = false
    private var buffer = Data()
    private var pendingBytes = Data()
    private var lineRemainder = ""
    private var response: URLResponse?
    private let lock = NSLock()

    func receiveResponse(_ response: URLResponse) {
        lock.lock()
        self.response = response
        lock.unlock()
    }

    func receiveData(_ data: Data) {
        lock.lock()
        buffer.append(data)
        pendingBytes.append(data)
        let partial = consumePendingBytes(flushIncompleteLine: false)
        let callback = onPartial
        lock.unlock()
        if let partial { callback?(partial) }
    }

    func finish(response: URLResponse?, error: Error?) {
        lock.lock()
        consumePendingBytes(flushIncompleteLine: true)
        let complete = onComplete
        let body = buffer
        let captured = self.response ?? response
        lock.unlock()
        complete?(body, captured, error)
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
            if let delta = Self.sseDeltaContent(from: String(payload)) {
                accumulated += delta
                latest = accumulated
            }
        }
        return latest
    }
}

/// Routes one shared URLSession's callbacks to the collector for that task.
final class StreamRouter: @unchecked Sendable {
    private let lock = NSLock()
    private var collectors: [Int: StreamCollector] = [:]

    /// Exposed for the standalone check; production never reads this.
    var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return collectors.count
    }

    func register(_ collector: StreamCollector, for taskIdentifier: Int) {
        lock.lock()
        collectors[taskIdentifier] = collector
        lock.unlock()
    }

    func receiveResponse(_ response: URLResponse, for taskIdentifier: Int) {
        collector(for: taskIdentifier)?.receiveResponse(response)
    }

    func receiveData(_ data: Data, for taskIdentifier: Int) {
        collector(for: taskIdentifier)?.receiveData(data)
    }

    func finish(taskIdentifier: Int, response: URLResponse?, error: Error?) {
        let collector = unregister(taskIdentifier)
        collector?.finish(response: response, error: error)
    }

    private func collector(for taskIdentifier: Int) -> StreamCollector? {
        lock.lock()
        defer { lock.unlock() }
        return collectors[taskIdentifier]
    }

    private func unregister(_ taskIdentifier: Int) -> StreamCollector? {
        lock.lock()
        defer { lock.unlock() }
        return collectors.removeValue(forKey: taskIdentifier)
    }
}

/// Thin URLSession delegate that only looks up the collector and forwards bytes.
final class StreamSessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let router: StreamRouter

    init(router: StreamRouter) {
        self.router = router
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        router.receiveResponse(response, for: dataTask.taskIdentifier)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        router.receiveData(data, for: dataTask.taskIdentifier)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        router.finish(taskIdentifier: task.taskIdentifier, response: task.response, error: error)
    }
}

/// One long-lived streaming session so TCP/TLS stay warm across translate requests.
enum StreamingHTTP {
    static let router = StreamRouter()
    private static let delegate = StreamSessionDelegate(router: router)
    static let session: URLSession = {
        URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }()
}
