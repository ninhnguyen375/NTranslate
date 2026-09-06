import Foundation

@main
struct ReadingDialogueCheck {
    static func main() {
        let topical = """
        Topic: Two coworkers talk about a failed deployment.

        A: Hey, you got a minute?
        B: Yeah, quick one.

        A: Này, cậu rảnh một phút không?
        B: Ừ, nhanh thôi.
        """
        assert(ReadingDialogue.parse(topical)?.topic == "Two coworkers talk about a failed deployment.")
        assert(ReadingDialogue.parse(topical)?.turns.count == 2, "the topic line must not become a turn")

        let text = """
        A: Hey, you got a minute?
        B: Yeah, quick one.
        A: The deployment failed again.

        A: Này, cậu rảnh một phút không?
        B: Ừ, nhanh thôi.
        A: Vụ triển khai lại hỏng rồi.
        """
        let dialogue = ReadingDialogue.parse(text)
        assert(dialogue?.turns.count == 3, "expected 3 turns, got \(dialogue?.turns.count ?? -1)")
        assert(dialogue?.turns[0].isFirstSpeaker == true)
        assert(dialogue?.turns[1].isFirstSpeaker == false)
        assert(dialogue?.turns[2].translation == "Vụ triển khai lại hỏng rồi.")
        // A passage generated before the prompt asked for a topic still parses, without one.
        assert(dialogue?.topic == "")

        // A plain passage has no speaker labels, so the caller keeps its old rendering.
        assert(ReadingDialogue.parse("A radio commentator sat in his room.\n\nMột bình luận viên.") == nil)
        assert(ReadingDialogue.parse("Generating a passage from 12 words…") == nil)

        // A sentence carrying a colon is not a speaker label.
        assert(ReadingDialogue.parse("Note: this is prose.\nAnother line here.") == nil)

        // A translation broken into extra paragraphs still lines up turn by turn.
        let split = """
        A: One.
        B: Two.

        A: Một.

        B: Hai.
        """
        assert(ReadingDialogue.parse(split)?.turns[1].translation == "Hai.")

        // A missing translation block leaves the turns without one instead of failing.
        let onlySource = "A: One.\nB: Two."
        assert(ReadingDialogue.parse(onlySource)?.turns.allSatisfy { $0.translation.isEmpty } == true)
        print("reading-dialogue-check ok")
    }
}
