import AVFoundation
import Foundation

/// LLM pronunciation assessment result for one read-aloud line.
struct PronunciationResult: Sendable, Equatable {
    struct Word: Sendable, Equatable {
        let text: String
        /// "Omission" or "Mispronunciation".
        let errorType: String
        /// Free-text feedback: issue and tip from the model.
        var note: String? = nil

        var isOmitted: Bool { errorType == "Omission" }
    }

    let score: Double
    let recognized: String
    let words: [Word]

    var header: String { String(format: "Score %.0f", score) }

    /// Reads the JSON the LLM scoring prompt asks for, from a chat completion response:
    /// {"heard", "score", "errors": [{"word", "heard", "issue", "tip"}]}.
    static func parseLLM(_ data: Data) throws -> PronunciationResult {
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = (response?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
        var content = (message?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Models often wrap JSON in a ```json fence despite being told not to.
        if let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") {
            content = String(content[start...end])
        }
        guard let json = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any],
              let score = (json["score"] as? NSNumber)?.doubleValue
        else { throw error("Unreadable scoring response") }
        let words = (json["errors"] as? [[String: Any]] ?? []).map { item -> Word in
            let heard = (item["heard"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let missing = heard.isEmpty || heard.lowercased().contains("missing")
            let note = [item["issue"] as? String, item["tip"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return Word(
                text: item["word"] as? String ?? "",
                errorType: missing ? "Omission" : "Mispronunciation",
                note: missing ? nil : (note.isEmpty ? "sounded like \"\(heard)\"" : note)
            )
        }
        return PronunciationResult(score: score, recognized: json["heard"] as? String ?? "", words: words)
    }

    /// One line per problem word, e.g. "thought: Sai âm /θ/. Đưa lưỡi ra.".
    var feedbackLines: [String] {
        words.map { word in
            if word.isOmitted { return "\(word.text): missing" }
            return "\(word.text): \(word.note ?? "unclear")"
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "Pronunciation", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Word-to-character mapping for coloring the source line. The model may change case and drop
/// punctuation, so each word is searched case-insensitively from where the previous one ended.
enum PronunciationHighlight {
    static func ranges(of words: [PronunciationResult.Word], in source: String) -> [(NSRange, PronunciationResult.Word)] {
        let text = source as NSString
        var cursor = 0
        var result: [(NSRange, PronunciationResult.Word)] = []
        for word in words where !word.text.isEmpty {
            // Word boundaries stop "he" from matching inside "the".
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word.text) + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let range = regex.firstMatch(in: source, range: NSRange(location: cursor, length: text.length - cursor))?.range
            else { continue }
            result.append((range, word))
            cursor = range.location + range.length
        }
        return result
    }
}

/// Loudness gate before a recording goes out: a near-silent clip only earns a meaningless score.
enum AudioLevel {
    /// Peak below this (about -30 dBFS) means the mic barely heard the speaker. Normal speech on the
    /// built-in mic peaks well above 0.1.
    static let quietPeak: Float = 0.03

    /// Loudest sample in the file, 0...1; nil when the file cannot be read.
    static func peak(of url: URL) -> Float? {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        var peak: Float = 0
        for i in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[i])) }
        return peak
    }

    /// The error to show instead of sending the clip, or nil when it is loud enough (or unreadable,
    /// which the request itself will report).
    static func quietError(_ url: URL) -> NSError? {
        guard let peak = peak(of: url), peak < quietPeak else { return nil }
        return NSError(domain: "Dictation", code: 4, userInfo: [NSLocalizedDescriptionKey: "Recording too quiet. Move closer to the microphone and try again."])
    }
}
