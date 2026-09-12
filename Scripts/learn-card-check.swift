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
        expect(card.familyForms.map(\.gloss) == ["n. sự bỏ rơi", "adj. bị bỏ rơi"],
               "word family keeps the gloss the review question will show")
        expect(card.collocations.count == 1, "one collocation, got \(card.collocations.count)")
        expect(card.collocations.first?.phrase == "abandon ship", "collocation phrase parsed")
        expect(card.collocations.first?.meaning == "bỏ tàu", "collocation meaning parsed")
        expect(card.collocationQuiz?.answer == "abandon ship", "collocation quiz asks for the whole pairing")
        expect(card.collocationQuiz?.prompt == "bỏ tàu", "collocation quiz shows the meaning, not the phrase")
        expect(card.familyQuiz?.answer == "abandonment", "family quiz asks for the derived form")
        expect(card.familyQuiz?.prompt.contains("n. sự bỏ rơi") == true, "family quiz shows the gloss")
        expect(card.cloze?.answer == "abandon", "cloze answer parsed")
        expect(card.cloze?.prompt.contains("___") == true, "cloze prompt keeps its blank")
        expect(card.cloze?.hintedPrompt.contains("a______") == true,
               "cloze blank becomes a first letter plus one underscore per remaining character")
        expect(card.synonyms.map(\.form) == ["desert", "leave"], "synonyms parsed from Từ đồng nghĩa")
        expect(card.antonyms.map(\.form) == ["keep"], "antonyms parsed from Từ trái nghĩa")
        expect(card.synonyms.allSatisfy { $0.gloss.isEmpty }, "plain synonyms have no gloss")

        let glossedRelated = LearnCard.parse("""
        Từ gốc: takeoff
        Phiên âm: /ˈteɪkɒf/
        n. sự cất cánh
        Từ đồng nghĩa: departure (chuyến khởi hành), launch (sự phóng)
        Từ trái nghĩa: landing: hạ cánh
        """)
        expect(glossedRelated.synonyms.map(\.form) == ["departure", "launch"],
               "glossed synonyms keep the English word")
        expect(glossedRelated.synonyms.map(\.gloss) == ["chuyến khởi hành", "sự phóng"],
               "parenthetical synonym gloss is kept")
        expect(glossedRelated.antonyms.first?.form == "landing", "colon antonym keeps the word")
        expect(glossedRelated.antonyms.first?.gloss == "hạ cánh", "colon antonym keeps the gloss")
        expect(card.mnemonic.contains("a ban donner"),
               "Nhớ nhanh is kept as mnemonic, got \(card.mnemonic)")
        expect(LearnCard.ClozeQuestion.hint(for: "give up") == "g___ u_", "multi-word hint keeps word boundaries")
        expect(LearnCard.ClozeQuestion.hint(for: "well-known") == "w___-_____", "punctuation stays visible")

        let legacy = LearnCard.parse(legacyCard)
        expect(legacy.examples.count == 2, "pre-change card still yields examples")
        expect(legacy.examples.allSatisfy { $0.level == .unspecified }, "untagged examples are unspecified")
        expect(legacy.confusables.isEmpty, "(không có) yields no confusable")
        expect(legacy.wordFamily.isEmpty, "(không có) yields no word family")
        expect(legacy.collocations.isEmpty, "a card with no collocation section yields none")
        expect(legacy.cloze?.answer == "a", "legacy cloze still parses")
        expect(legacy.mnemonic.isEmpty, "a card without Nhớ nhanh yields an empty mnemonic")

        let emptyMnemonic = LearnCard.parse("""
        Từ gốc: solo
        Phiên âm: /ˈsəʊləʊ/
        n. độc tấu
        Nhớ nhanh: (không có)
        """)
        expect(emptyMnemonic.mnemonic.isEmpty, "Nhớ nhanh: (không có) yields an empty mnemonic")

        let inlineMnemonic = LearnCard.parse("""
        Từ gốc: resilient
        Phiên âm: /rɪˈzɪliənt/
        adj. kiên cường
        Nhớ nhanh: gốc re + salire, nhảy lại
        """)
        expect(inlineMnemonic.mnemonic == "gốc re + salire, nhảy lại",
               "an inline Nhớ nhanh value is kept, got \(inlineMnemonic.mnemonic)")

        let emptyCollocation = LearnCard.parse("""
        Từ gốc: solo
        Đi kèm thường gặp: (không có)
        Họ từ: (không có)
        """)
        expect(emptyCollocation.collocations.isEmpty, "(không có) yields no collocation")
        expect(emptyCollocation.collocationQuiz == nil, "no pairing means no collocation quiz")
        expect(emptyCollocation.familyQuiz == nil, "no family means no family quiz")

        let emptyRelated = LearnCard.parse("""
        Từ gốc: solo
        Phiên âm: /ˈsəʊləʊ/
        n. độc tấu
        Từ đồng nghĩa: (không có)
        Từ trái nghĩa: (không có)
        """)
        expect(emptyRelated.synonyms.isEmpty, "(không có) yields no synonyms")
        expect(emptyRelated.antonyms.isEmpty, "(không có) yields no antonyms")

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

        let mined = card.minedCloze(from: "The crew had to abandon ship.")
        expect(mined?.prompt == "The crew had to ___ ship.", "the encounter sentence is blanked on the headword")
        expect(mined?.answer == "abandon", "the mined cloze answer is the form the sentence used")
        expect(card.preferredCloze(encounterSentence: "The crew had to abandon ship.")?.prompt
                == "The crew had to ___ ship.",
               "a mined sentence wins over the model's tự kiểm tra cloze")
        expect(card.preferredCloze(encounterSentence: nil)?.answer == "abandon",
               "without an encounter sentence the model's cloze is still used")
        expect(card.minedCloze(from: "Nothing to see here.") == nil,
               "a sentence without the headword cannot be mined")

        let encoded = LearnCard.Encounter.encode(term: "abandon", context: "The crew had to abandon ship.")
        expect(encoded == "abandon (context: The crew had to abandon ship.)", "term plus sentence encode in the stored shape")
        expect(LearnCard.Encounter.encode(term: "abandon", context: "abandon") == "abandon",
               "a context that is just the term is not stored twice")
        expect(LearnCard.Encounter.encode(term: "abandon", context: "  ") == "abandon",
               "blank context is omitted")
        let parts = LearnCard.Encounter.split(encoded)
        expect(parts.term == "abandon" && parts.context == "The crew had to abandon ship.",
               "the stored shape splits back into term and sentence")
        expect(LearnCard.Encounter.split("abandon").context == nil, "a bare term has no encounter sentence")
        expect(LearnCard.Encounter.storedSource(selection: "The crew had to abandon ship.", headword: "abandon")
                == encoded,
               "learning a sentence stores the headword and keeps the sentence as context")
        expect(LearnCard.Encounter.storedSource(selection: "abandon", headword: "abandon") == "abandon",
               "learning the word alone stays a bare term")
        expect(LearnCard.Encounter.matches(encoded, selection: "The crew had to abandon ship."),
               "looking up the original sentence finds the encoded card")
        expect(LearnCard.Encounter.matches(encoded, selection: encoded),
               "looking up the stored source finds the same card")
        expect(LearnCard.Encounter.matches("abandon", selection: "abandon"),
               "a bare term still matches itself")
        expect(!LearnCard.Encounter.matches(encoded, selection: "desert"),
               "a different word does not match an encoded card")

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
        print("\nAll checks passed")
    }
}
