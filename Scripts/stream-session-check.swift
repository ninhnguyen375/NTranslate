// Self-check for the shared streaming session router: task isolation, map cleanup,
// and SSE bytes split across chunks (including a torn UTF-8 sequence).
// swiftc -parse-as-library Sources/translate/StreamSession.swift \
//   Scripts/stream-session-check.swift -o /tmp/stream-session-check && /tmp/stream-session-check

import Foundation

func sseLine(_ content: String) -> Data {
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    return Data("data: {\"choices\":[{\"delta\":{\"content\":\"\(escaped)\"}}]}\n".utf8)
}

final class Sink: @unchecked Sendable {
    var partials: [String] = []
    var done = false
}

@main
enum StreamSessionCheck {
    static func main() {
        isolationAndCleanup()
        utf8SplitAcrossChunks()
        print("stream-session-check: OK")
    }

    static func isolationAndCleanup() {
        let router = StreamRouter()
        let first = StreamCollector()
        let second = StreamCollector()
        let firstSink = Sink()
        let secondSink = Sink()

        first.onPartial = { firstSink.partials.append($0) }
        second.onPartial = { secondSink.partials.append($0) }
        first.onComplete = { _, _, _ in firstSink.done = true }
        second.onComplete = { _, _, _ in secondSink.done = true }

        router.register(first, for: 1)
        router.register(second, for: 2)
        guard router.entryCount == 2 else {
            FileHandle.standardError.write(Data("expected 2 registered collectors, got \(router.entryCount)\n".utf8))
            exit(1)
        }

        router.receiveData(sseLine("AAA"), for: 1)
        router.receiveData(sseLine("BBB"), for: 2)
        router.receiveData(sseLine("aaa"), for: 1)
        router.receiveData(sseLine("bbb"), for: 2)

        guard first.accumulated == "AAAaaa" else {
            FileHandle.standardError.write(Data("collector 1 mixed or lost data: \(first.accumulated)\n".utf8))
            exit(1)
        }
        guard second.accumulated == "BBBbbb" else {
            FileHandle.standardError.write(Data("collector 2 mixed or lost data: \(second.accumulated)\n".utf8))
            exit(1)
        }
        guard firstSink.partials.last == "AAAaaa", secondSink.partials.last == "BBBbbb" else {
            FileHandle.standardError.write(Data("partial callbacks did not stay on their own task\n".utf8))
            exit(1)
        }

        router.finish(taskIdentifier: 1, response: nil, error: nil)
        guard firstSink.done, !secondSink.done else {
            FileHandle.standardError.write(Data("finish must complete only the matching collector\n".utf8))
            exit(1)
        }
        guard router.entryCount == 1 else {
            FileHandle.standardError.write(Data("finished task must leave the map, got \(router.entryCount)\n".utf8))
            exit(1)
        }

        router.finish(taskIdentifier: 2, response: nil, error: nil)
        guard secondSink.done else {
            FileHandle.standardError.write(Data("collector 2 never completed\n".utf8))
            exit(1)
        }
        guard router.entryCount == 0 else {
            FileHandle.standardError.write(Data("map must be empty after every task finishes, got \(router.entryCount)\n".utf8))
            exit(1)
        }
    }

    static func utf8SplitAcrossChunks() {
        let collector = StreamCollector()
        let cafe = "café"
        let line = sseLine(cafe)
        guard let tornAt = line.firstRange(of: Data([0xC3, 0xA9]))?.lowerBound else {
            FileHandle.standardError.write(Data("fixture must contain UTF-8 é so the split is real\n".utf8))
            exit(1)
        }

        let afterFirstByte = line.index(tornAt, offsetBy: 1)
        collector.receiveData(Data(line[..<afterFirstByte]))
        guard collector.accumulated.isEmpty else {
            FileHandle.standardError.write(Data("a torn UTF-8 byte must not produce a character yet\n".utf8))
            exit(1)
        }

        collector.receiveData(Data(line[afterFirstByte...]))
        collector.finish(response: nil, error: nil)
        guard collector.accumulated == cafe else {
            FileHandle.standardError.write(Data("split UTF-8 must reassemble, got \(collector.accumulated)\n".utf8))
            exit(1)
        }
        guard collector.sawSSE else {
            FileHandle.standardError.write(Data("reassembled SSE line must be recognized as SSE\n".utf8))
            exit(1)
        }
    }
}
