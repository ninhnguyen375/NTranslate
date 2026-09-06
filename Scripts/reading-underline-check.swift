import Foundation

@main
struct ReadingUnderlineCheck {
    static func main() {
        let text = "The notebook is new. I book a room, and the books are on the desk."
        let ranges = ReadingHighlight.ranges(in: text, words: ["book", "books"])
        let matched = ranges.map { (text as NSString).substring(with: $0) }
        assert(matched == ["book", "books"], "expected whole-word matches, got \(matched)")

        let caseText = "Serendipity again: SERENDIPITY."
        let caseHits = ReadingHighlight.ranges(in: caseText, words: ["serendipity"])
        assert(caseHits.count == 2, "case-insensitive match failed: \(caseHits.count)")

        let overlap = ReadingHighlight.ranges(in: "take off now", words: ["take off", "take"])
        assert(overlap.count == 1, "overlapping terms should not double-underline: \(overlap.count)")

        // An inflected form still counts as the word being practised.
        let inflected = "The team cultivates habits, and the deployments keep failing."
        let stems = ReadingHighlight.ranges(in: inflected, words: ["cultivate", "deployment"])
        let stemHits = stems.map { (inflected as NSString).substring(with: $0) }
        assert(stemHits == ["cultivates", "deployments"], "inflected forms missed: \(stemHits)")

        // Short words keep their exact form, or "act" would swallow "actually".
        assert(ReadingHighlight.ranges(in: "I act, actually.", words: ["act"]).count == 1)

        assert(ReadingHighlight.ranges(in: "nothing here", words: ["", "  "]).isEmpty)

        // A click lands on an inflected form, so the match has to name the card's own word.
        let owners = ReadingHighlight.matches(in: inflected, words: ["cultivate", "deployment"]).map(\.word)
        assert(owners == ["cultivate", "deployment"], "match words wrong: \(owners)")

        // The attribute a click reads back names the card word, not the inflected form on screen.
        let marked = ReadingHighlight.attributed(
            inflected,
            words: ["cultivate"],
            font: .systemFont(ofSize: 13),
            color: .labelColor,
            linked: true
        )
        let hit = marked.attribute(ReadingHighlight.wordAttribute, at: 9, effectiveRange: nil) as? String
        assert(hit == "cultivate", "word attribute missing: \(hit ?? "nil")")
        print("reading-underline-check ok")
    }
}
