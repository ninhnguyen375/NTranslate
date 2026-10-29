import Foundation

@main
struct ReviewAnswerTranslationCheck {
    static func main() throws {
        var card = LearnCard()
        card.headword = "sales reps"
        card.confusables = [.init(other: "sales rep", difference: "Different roles", contrastSentence: "The sales reps visit clients.")]
        assert(ConfusableDrillItem.build(from: [card]).isEmpty, "Inflected identical choices must be rejected")
        card.headword = "sales rep"
        card.confusables = [.init(other: "shop assistant", difference: "A sales rep represents a business; a shop assistant serves customers in a shop.", contrastSentence: "The sales rep visits clients.")]
        let drills = ConfusableDrillItem.build(from: [card])
        assert(drills.count == 1)
        assert(drills[0].correct != drills[0].distractor)
        let source = try String(contentsOfFile: "Sources/translate/ReviewWindowController.swift", encoding: .utf8)
        assert(source.contains("showResultTranslation()"))
        assert(source.contains("self.resultSentence == sentence"))
        assert(source.contains("self.recordsToReview[self.currentIndex].id == record.id"))
        assert(!source.contains("\"\\(drill.correct): \\(drill.explanation)\""))
        print("review-answer-translation-check: ok")
    }
}
