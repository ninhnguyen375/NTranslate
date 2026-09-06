import AppKit

/// Underlines, in the woven passage, the words the passage was built from, so the learner can see
/// which of their own terms are in play.
enum ReadingHighlight {
    /// Ranges of `words` inside `text`, matched case-insensitively on whole words only.
    static func ranges(in text: String, words: [String]) -> [NSRange] {
        matches(in: text, words: words).map(\.range)
    }

    /// Same matching, but each hit keeps the word from `words` it came from, so a click on an
    /// inflected form can still be traced back to the card that owns it.
    /// Longer words win an overlap, so "book" inside "notebook" never steals the underline.
    static func matches(in text: String, words: [String]) -> [(range: NSRange, word: String)] {
        let ns = text as NSString
        var found: [(range: NSRange, word: String)] = []
        for word in words.sorted(by: { $0.count > $1.count }) {
            let term = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { continue }
            // Only a word long enough to stem safely is allowed to match a longer form.
            let root = stem(of: term)
            let tail = term.count >= 5 ? "\\w*" : ""
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: root) + tail + "\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if found.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) { continue }
                found.append((match.range, term))
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// Marks the card word behind an underlined term. A `.link` cannot be used for this: AppKit
    /// hands a link click to LaunchServices before the label ever sees the mouse, and macOS then
    /// offers to find an app for the URL.
    static let wordAttribute = NSAttributedString.Key("ntranslateWord")

    /// The text with those ranges underlined, ready for a label. With `linked` on, each underlined
    /// word also carries the word attribute, which is how a click on it reaches the card behind it.
    @MainActor
    static func attributed(
        _ text: String,
        words: [String],
        font: NSFont,
        color: NSColor,
        linked: Bool = false
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
        for match in matches(in: text, words: words) {
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: match.range)
            if linked {
                attributed.addAttribute(wordAttribute, value: match.word, range: match.range)
            }
        }
        return attributed
    }

    /// "cultivates" also has to match "cultivating", so the search drops a common ending and lets
    /// the rest of the word run on. Short words keep their exact form: trimming "act" would match
    /// half the passage.
    private static func stem(of word: String) -> String {
        guard word.count >= 5 else { return word }
        for ending in ["ies", "ing", "ed", "es", "s", "e"] where word.hasSuffix(ending) {
            let trimmed = String(word.dropLast(ending.count))
            if trimmed.count >= 4 { return ending == "ies" ? trimmed + "y" : trimmed }
        }
        return word
    }
}
