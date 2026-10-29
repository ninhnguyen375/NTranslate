import Foundation

@main
struct StudyResultTranslationCheck {
    static func main() throws {
        let source = try String(contentsOfFile: "Sources/translate/ReviewWindowController.swift", encoding: .utf8)
        let start = source.range(of: "private func showAnswerResult(")!.lowerBound
        let end = source.range(of: "private static func filledSentence", range: start..<source.endIndex)!.lowerBound
        let result = String(source[start..<end])
        assert(result.contains("showResultTranslation()"))
        assert(result.contains("card.examples.first(where:"))
        assert(result.contains("targetLang: \"Vietnamese\""))
        assert(result.contains("self.resultSentence == sentence"))
        assert(result.contains("self.recordsToReview[self.currentIndex].id == record.id"))
        assert(result.contains("!self.isAnswerRevealed"))
        assert(result.contains("case .failure:"))
        print("Study result translation checks passed")
    }
}
