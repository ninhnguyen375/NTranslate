// Self-check for LearnCard parsing and confusable drill assembly.
//
//   swiftc -parse-as-library Sources/translate/LearnCard.swift Scripts/learn-card-check.swift \
//     -o /tmp/learn-card-check && /tmp/learn-card-check
//
// The review window asks questions built entirely out of stored card text, so a parsing slip
// shows up as a card that silently refuses to quiz. These cases pin the shapes that matter.
import Foundation

private var failures = 0

private func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("ok   \(message)")
    } else {
        failures += 1
        print("FAIL \(message)")
    }
}

private let enrichedCard = """
Từ gốc: abandon
Phiên âm: /əˈbændən/
Mức dùng: neutral · phổ biến · CEFR B2
v. bỏ rơi, từ bỏ

Từ đồng nghĩa: desert, leave
Từ trái nghĩa: keep

Đi kèm thường gặp
- abandon ship: bỏ tàu

Họ từ
- abandonment: n. sự bỏ rơi
- abandoned: adj. bị bỏ rơi
- abandon: v. chính từ gốc

Dễ nhầm với
- desert: rời bỏ nơi hoặc người mình có trách nhiệm
  → They abandon the plan quickly.
- quit: dừng một việc đang làm
  → He quit his job.

Ví dụ
- [dễ] They abandon the car.
  → Họ bỏ lại chiếc xe.
- [trung] The crew had to abandon ship.
  → Thủy thủ đoàn phải bỏ tàu.
- [khó] She abandoned herself to grief.
  → Cô ấy buông mình theo nỗi đau.

Nhớ nhanh
- Gốc "a ban donner": trao đi quyền kiểm soát.

Tự kiểm tra
- The team decided to ___ the project.
- Đáp án: abandon
"""

private let legacyCard = """
Từ gốc: a
Phiên âm: /ə/
art. mạo từ không xác định

Dễ nhầm với: (không có)
Họ từ: (không có)

Ví dụ
- I have a dog.
  → Tôi có một con chó.
- She is a teacher.
  → Cô ấy là một giáo viên.

Tự kiểm tra
- I bought ___ new laptop yesterday.
- Đáp án: a
"""

@main
struct LearnCardCheck {
    static func main() {
        let card = LearnCard.parse(enrichedCard)
        expect(card.headword == "abandon", "headword parsed")
        expect(card.pronunciation == "/əˈbændən/", "pronunciation parsed")
        expect(card.examples.count == 3, "three levelled examples, got \(card.examples.count)")
        expect(card.examples.map(\.level) == [.easy, .medium, .hard], "levels in order")
        expect(card.examples[0].sentence == "They abandon the car.", "level tag stripped from sentence")
        expect(card.examples[0].translation == "Họ bỏ lại chiếc xe.", "translation attached to its example")
        expect(card.confusables.count == 2, "two confusables, got \(card.confusables.count)")
        expect(card.confusables[0].other == "desert", "confusable word parsed")
        expect(card.confusables[0].contrastSentence == "They abandon the plan quickly.", "contrast sentence attached")
        expect(card.wordFamily == ["abandonment", "abandoned"], "word family drops the headword itself")
        expect(card.cloze?.answer == "abandon", "cloze answer parsed")
        expect(card.cloze?.prompt.contains("___") == true, "cloze prompt keeps its blank")

        let legacy = LearnCard.parse(legacyCard)
        expect(legacy.examples.count == 2, "pre-change card still yields examples")
        expect(legacy.examples.allSatisfy { $0.level == .unspecified }, "untagged examples are unspecified")
        expect(legacy.confusables.isEmpty, "(không có) yields no confusable")
        expect(legacy.wordFamily.isEmpty, "(không có) yields no word family")
        expect(legacy.cloze?.answer == "a", "legacy cloze still parses")

        let indentedAnswer = LearnCard.parse("""
        Từ gốc: ability

        Tự kiểm tra
        - He has the ___ to solve it.
          → Đáp án: ability
        """)
        expect(indentedAnswer.cloze?.answer == "ability", "answer written as an indented continuation still parses")

        let noAnswer = LearnCard.parse("Từ gốc: x\n\nTự kiểm tra\n- He ___ it.")
        expect(noAnswer.cloze == nil, "cloze without an answer is dropped")

        expect(LearnCard.parse("").headword.isEmpty, "empty text parses without crashing")
        expect(LearnCard.parse("Từ gốc: solo").headword == "solo", "headword-only card parses")

        let cloze = LearnCard.ClozeQuestion(prompt: "___ it", answer: "Abandon")
        expect(cloze.matches("  abandon "), "answer match ignores case and spacing")
        expect(!cloze.matches("desert"), "a different word is rejected")

        let items = ConfusableDrillItem.build(from: [card])
        expect(items.count == 1, "one drill item per card, got \(items.count)")
        expect(items.first?.sentence == "They ___ the plan quickly.", "headword blanked out")
        expect(items.first?.distractor == "desert", "distractor is the confusable word")

        let unusable = LearnCard.parse("""
        Từ gốc: abandon

        Dễ nhầm với
        - desert: khác nhau ở trách nhiệm
          → He deserted his family.
        """)
        expect(ConfusableDrillItem.build(from: [unusable]).isEmpty, "sentence without the headword is skipped")

        expect(ConfusableDrillItem.blankOut("band", in: "The abandoned band played.") == "The abandoned ___ played.",
               "blank lands on the whole word, not inside a longer one")

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
        print("\nAll checks passed")
    }
}
