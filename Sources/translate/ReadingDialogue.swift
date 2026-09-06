import Foundation

/// The woven passage as the model returns it: a topic line, an English conversation, a blank line,
/// then the same conversation in the learner's language. Parsing it into turns is what lets the
/// reading screen show one bubble per line with its own translation.
struct ReadingDialogue: Equatable {
    struct Turn: Equatable {
        let speaker: String
        let source: String
        let translation: String

        /// The first speaker in the passage sits on the left, everyone else on the right.
        var isFirstSpeaker: Bool { speaker.uppercased() == "A" }
    }

    let turns: [Turn]
    /// One sentence naming the situation, so a saved passage can be recognised in a list. Empty for
    /// a passage generated before the prompt asked for one.
    let topic: String

    /// nil when the text is not a two-block dialogue: a plain passage, an error message, or the
    /// "generating…" placeholder. The caller then falls back to showing the text as it is.
    static func parse(_ text: String) -> ReadingDialogue? {
        var blocks = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // The topic is its own block and would otherwise parse as a speaker called "Topic".
        var topic = ""
        if let first = blocks.first, !first.contains("\n"), first.lowercased().hasPrefix("topic:") {
            topic = String(first.dropFirst("topic:".count)).trimmingCharacters(in: .whitespaces)
            blocks.removeFirst()
        }
        guard let sourceBlock = blocks.first else { return nil }

        let sourceLines = speakerLines(in: sourceBlock)
        guard sourceLines.count >= 2 else { return nil }

        // Everything after the first block is the translation: the model sometimes breaks it into
        // paragraphs of its own, and joining them back keeps the turns lined up.
        let translationLines = blocks.dropFirst().flatMap { speakerLines(in: $0) }

        let turns = sourceLines.enumerated().map { index, line in
            Turn(
                speaker: line.speaker,
                source: line.text,
                translation: index < translationLines.count ? translationLines[index].text : ""
            )
        }
        return ReadingDialogue(turns: turns, topic: topic)
    }

    private static func speakerLines(in block: String) -> [(speaker: String, text: String)] {
        block.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let speaker = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            // A speaker label is a short name, not a sentence that happens to hold a colon.
            guard !speaker.isEmpty, speaker.count <= 12,
                  speaker.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " })
            else { return nil }
            let text = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            return (speaker, text)
        }
    }
}
