// Structured view of one Learn card's plain text.
//
// A Learn card is stored as the model wrote it: plain Vietnamese text with named sections. That
// text already carries a self-test, confusable words, levelled examples and a word family, but
// nothing in the app could read them back. This parser turns the stored string into sections so
// the review window can ask a question instead of just flipping the card over.
//
// Parsing is deliberately tolerant. A card written before a prompt change, a truncated answer, a
// missing section: each degrades to an empty value and the feature that needed it hides itself.
// Nothing here throws, and nothing here touches AppKit or the disk.
import Foundation

struct LearnCard: Equatable, Sendable {
    enum Level: String, Equatable, Sendable {
        case easy = "dễ"
        case medium = "trung"
        case hard = "khó"
        /// Cards generated before levelled examples existed still have usable sentences.
        case unspecified
    }

    struct LeveledExample: Equatable, Sendable {
        var level: Level
        var sentence: String
        var translation: String
    }

    struct Confusable: Equatable, Sendable {
        var other: String
        var difference: String
        var contrastSentence: String
    }

    struct Collocation: Equatable, Sendable {
        var phrase: String
        var meaning: String
    }

    struct FamilyForm: Equatable, Sendable {
        var form: String
        var gloss: String
    }

    struct ClozeQuestion: Equatable, Sendable {
        var prompt: String
        var answer: String

        /// Case and spacing are noise; anything else is a wrong answer.
        func matches(_ input: String) -> Bool {
            LearnCard.normalizeAnswer(input) == LearnCard.normalizeAnswer(answer)
        }

        /// The prompt with the bare "___" replaced by the answer's shape: first letter, then one
        /// underscore per remaining character. A blank of unknown length is a guessing game.
        var hintedPrompt: String {
            guard prompt.contains("___"), !answer.isEmpty else { return prompt }
            return prompt.replacingOccurrences(of: "___", with: Self.hint(for: answer))
        }

        static func hint(for answer: String) -> String {
            answer.split(separator: " ").map { word -> String in
                guard let first = word.first else { return "" }
                let rest = word.dropFirst().map { $0.isLetter || $0.isNumber ? "_" : String($0) }
                return ([String(first)] + rest).joined(separator: " ")
            }.joined(separator: "   ")
        }
    }

    var headword: String = ""
    var pronunciation: String = ""
    var examples: [LeveledExample] = []
    var confusables: [Confusable] = []
    var familyForms: [FamilyForm] = []
    var collocations: [Collocation] = []
    var cloze: ClozeQuestion?
    /// The "n. ..." / "v. ..." lines, i.e. what the word means without naming it.
    var meanings: [String] = []

    /// Derived forms only, so existing call sites that just need the spelling keep working.
    var wordFamily: [String] { familyForms.map(\.form) }

    /// The reverse question: the meaning is shown and the headword itself is the answer.
    var recall: ClozeQuestion? {
        guard !headword.isEmpty, !meanings.isEmpty else { return nil }
        return ClozeQuestion(prompt: meanings.joined(separator: "\n"), answer: headword)
    }

    /// Meaning → the whole pairing. A collocation that is just the headword is not a pairing.
    var collocationQuiz: ClozeQuestion? {
        collocations.first { pair in
            !pair.phrase.isEmpty
                && !pair.meaning.isEmpty
                && Self.normalizeAnswer(pair.phrase) != Self.normalizeAnswer(headword)
        }.map { ClozeQuestion(prompt: $0.meaning, answer: $0.phrase) }
    }

    /// Gloss → one derived form. The prompt names the relationship so the blank is not a guess.
    var familyQuiz: ClozeQuestion? {
        familyForms.first { !$0.form.isEmpty && !$0.gloss.isEmpty }
            .map { ClozeQuestion(prompt: "Related form — \($0.gloss)", answer: $0.form) }
    }

    /// Blanks the headword in the sentence the learner actually met, not a model-written example.
    func minedCloze(from sentence: String) -> ClozeQuestion? {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !headword.isEmpty, !trimmed.isEmpty,
              let hit = ConfusableDrillItem.blankOutInflected(headword, in: trimmed)
        else { return nil }
        return ClozeQuestion(prompt: hit.blanked, answer: hit.form)
    }

    /// An encounter sentence is better practice than the card's generated cloze, when it can be blanked.
    func preferredCloze(encounterSentence: String?) -> ClozeQuestion? {
        if let sentence = encounterSentence, let mined = minedCloze(from: sentence) {
            return mined
        }
        return cloze
    }

    /// How a Learn record keeps the term and the sentence it was taken from, without a new field.
    enum Encounter {
        static let marker = " (context: "

        static func encode(term: String, context: String?) -> String {
            let term = term.trimmingCharacters(in: .whitespacesAndNewlines)
            let context = context?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !term.isEmpty else { return context }
            guard !context.isEmpty, LearnCard.normalizeAnswer(context) != LearnCard.normalizeAnswer(term) else { return term }
            return "\(term)\(marker)\(context))"
        }

        static func split(_ sourceText: String) -> (term: String, context: String?) {
            let sourceText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let range = sourceText.range(of: marker) else { return (sourceText, nil) }
            var context = String(sourceText[range.upperBound...])
            if context.hasSuffix(")") { context = String(context.dropLast()) }
            let term = String(sourceText[..<range.lowerBound])
            return (term, context.isEmpty ? nil : context)
        }

        /// When Learn ran on a sentence, the card's headword is the term and the sentence is context.
        static func storedSource(selection: String, headword: String) -> String {
            let selection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            let headword = headword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !headword.isEmpty else { return selection }
            guard !selection.isEmpty else { return headword }
            if LearnCard.normalizeAnswer(selection) == LearnCard.normalizeAnswer(headword) { return selection }
            return encode(term: headword, context: selection)
        }

        static func matches(_ stored: String, selection: String) -> Bool {
            let stored = stored.trimmingCharacters(in: .whitespacesAndNewlines)
            let selection = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            if stored == selection { return true }
            // The original sentence looks up the encoded card. The bare term does not, so two
            // encounters of the same word stay two cards.
            return split(stored).context == selection
        }
    }

    /// Same rule the pack lookup uses, so an answer typed with odd spacing still matches.
    static func normalizeAnswer(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private enum Section {
        case none, examples, confusables, family, collocations, cloze, ignored
    }

    private static let headings: [String: Section] = [
        "Ví dụ": .examples,
        "Dễ nhầm với": .confusables,
        "Họ từ": .family,
        "Đi kèm thường gặp": .collocations,
        "Tự kiểm tra": .cloze,
        "Nhớ nhanh": .ignored,
    ]

    static func parse(_ text: String) -> LearnCard {
        var card = LearnCard()
        var section: Section = .none
        var clozePrompt: String?
        var clozeAnswer: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if let (name, inlineValue) = headingParts(line), let next = headings[name] {
                // "Dễ nhầm với: (không có)" is a heading and its own empty content on one line.
                section = (inlineValue == nil) ? next : .none
                continue
            }

            if line.hasPrefix("- ") {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                switch section {
                case .examples:
                    if let example = parseExample(item) { card.examples.append(example) }
                case .confusables:
                    if let confusable = parseConfusable(item) { card.confusables.append(confusable) }
                case .family:
                    if let form = parseFamilyForm(item) { card.familyForms.append(form) }
                case .collocations:
                    if let pair = parseCollocation(item) { card.collocations.append(pair) }
                case .cloze:
                    if let answer = value(of: "Đáp án", in: item) {
                        clozeAnswer = answer
                    } else if item.contains("___") {
                        clozePrompt = item
                    }
                case .none, .ignored:
                    break
                }
                continue
            }

            if line.hasPrefix("→") {
                let continuation = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                switch section {
                case .examples:
                    if !card.examples.isEmpty { card.examples[card.examples.count - 1].translation = continuation }
                case .confusables:
                    if !card.confusables.isEmpty { card.confusables[card.confusables.count - 1].contrastSentence = continuation }
                case .cloze:
                    // Some cards indent the answer as a continuation instead of its own item.
                    if let answer = value(of: "Đáp án", in: continuation) { clozeAnswer = answer }
                default:
                    break
                }
                continue
            }

            if section == .none, isMeaningLine(line) {
                card.meanings.append(line)
                continue
            }

            if card.headword.isEmpty, let value = value(of: "Từ gốc", in: line) {
                card.headword = value
            } else if card.pronunciation.isEmpty, let value = value(of: "Phiên âm", in: line) {
                card.pronunciation = value
            }
        }

        if let prompt = clozePrompt, let answer = clozeAnswer, !answer.isEmpty, !isEmptyMarker(answer) {
            card.cloze = ClozeQuestion(prompt: prompt, answer: answer)
        }
        // Word family that just echoes the headword teaches nothing.
        card.familyForms.removeAll { normalizeAnswer($0.form) == normalizeAnswer(card.headword) }
        return card
    }

    private static let partsOfSpeech = ["n.", "v.", "adj.", "adv.", "prep.", "conj.", "pron.", "int.", "phr.", "num."]

    /// A meaning line names its part of speech first: "n. thiết bị phát ra chùm tia sáng".
    private static func isMeaningLine(_ line: String) -> Bool {
        guard let space = line.firstIndex(of: " ") else { return false }
        let head = String(line[line.startIndex..<space]).lowercased()
        guard partsOfSpeech.contains(head) else { return false }
        return line[space...].trimmingCharacters(in: .whitespaces).count > 1
    }

    /// The model writes "(không có)" wherever a section has nothing to say.
    private static func isEmptyMarker(_ text: String) -> Bool {
        let stripped = text.trimmingCharacters(in: CharacterSet(charactersIn: "()").union(.whitespaces)).lowercased()
        return stripped == "không có"
    }

    /// Splits "Ví dụ" and "Dễ nhầm với: (không có)" alike: the name, plus any inline value.
    private static func headingParts(_ line: String) -> (name: String, value: String?)? {
        if headings[line] != nil { return (line, nil) }
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        guard headings[name] != nil else { return nil }
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (name, value.isEmpty ? nil : value)
    }

    private static func value(of key: String, in line: String) -> String? {
        guard line.hasPrefix(key) else { return nil }
        let rest = line.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        guard rest.hasPrefix(":") else { return nil }
        return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func parseExample(_ item: String) -> LeveledExample? {
        var sentence = item
        var level = Level.unspecified
        if sentence.hasPrefix("["), let close = sentence.firstIndex(of: "]") {
            let tag = String(sentence[sentence.index(after: sentence.startIndex)..<close])
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            if let parsed = Level(rawValue: tag) {
                level = parsed
                sentence = String(sentence[sentence.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !sentence.isEmpty, !isEmptyMarker(sentence) else { return nil }
        return LeveledExample(level: level, sentence: sentence, translation: "")
    }

    private static func parseConfusable(_ item: String) -> Confusable? {
        guard !isEmptyMarker(item) else { return nil }
        guard let colon = item.firstIndex(of: ":") else { return nil }
        let other = String(item[item.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        let difference = String(item[item.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !other.isEmpty else { return nil }
        return Confusable(other: other, difference: difference, contrastSentence: "")
    }

    private static func parseFamilyForm(_ item: String) -> FamilyForm? {
        guard !isEmptyMarker(item) else { return nil }
        let parts = item.split(separator: ":", maxSplits: 1)
        let form = parts.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !form.isEmpty else { return nil }
        let gloss = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        return FamilyForm(form: form, gloss: isEmptyMarker(gloss) ? "" : gloss)
    }

    private static func parseCollocation(_ item: String) -> Collocation? {
        guard !isEmptyMarker(item) else { return nil }
        guard let colon = item.firstIndex(of: ":") else { return nil }
        let phrase = String(item[item.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        let meaning = String(item[item.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty, !isEmptyMarker(meaning) else { return nil }
        return Collocation(phrase: phrase, meaning: meaning)
    }
}

/// One "which word fits here" question, built from a card's own contrast sentence.
struct ConfusableDrillItem: Equatable, Sendable {
    var sentence: String
    var correct: String
    var distractor: String
    var explanation: String

    /// Only cards whose contrast sentence actually contains the headword can be blanked. A blank
    /// punched in the wrong place asks a question with no right answer, so those are skipped.
    static func build(from cards: [LearnCard]) -> [ConfusableDrillItem] {
        var items: [ConfusableDrillItem] = []
        for card in cards where !card.headword.isEmpty {
            for confusable in card.confusables {
                guard !confusable.contrastSentence.isEmpty,
                      confusable.other.caseInsensitiveCompare(card.headword) != .orderedSame,
                      let hit = blankOutInflected(card.headword, in: confusable.contrastSentence)
                else { continue }
                items.append(ConfusableDrillItem(
                    sentence: hit.blanked,
                    correct: hit.form,
                    distractor: matchInflection(of: confusable.other, headword: card.headword, form: hit.form),
                    explanation: confusable.difference
                ))
                break
            }
        }
        return items
    }

    /// English sentences rarely use the dictionary form of the headword: a card for "amplifiers"
    /// gets an example about one amplifier. Trying the usual inflections keeps those cards
    /// drillable instead of silently dropping them back to a plain flip.
    static func inflections(of word: String) -> [String] {
        let base = word.trimmingCharacters(in: .whitespaces)
        guard !base.isEmpty, !base.contains(" ") else { return [base] }
        let lower = base.lowercased()
        var forms = [base]

        func add(_ form: String) {
            guard !form.isEmpty, !forms.contains(where: { $0.caseInsensitiveCompare(form) == .orderedSame }) else { return }
            forms.append(form)
        }

        // Singular/base forms, for a headword that was saved inflected.
        if lower.hasSuffix("ies"), base.count > 4 { add(String(base.dropLast(3)) + "y") }
        if lower.hasSuffix("ied"), base.count > 4 { add(String(base.dropLast(3)) + "y") }
        if lower.hasSuffix("es"), base.count > 3 { add(String(base.dropLast(2))) }
        if lower.hasSuffix("s"), !lower.hasSuffix("ss"), base.count > 3 { add(String(base.dropLast())) }
        if lower.hasSuffix("ing"), base.count > 5 {
            add(String(base.dropLast(3)))
            add(String(base.dropLast(3)) + "e")
        }
        if lower.hasSuffix("ed"), base.count > 4 {
            add(String(base.dropLast(2)))
            add(String(base.dropLast()))
        }

        // Inflected forms, for a headword saved in its dictionary form.
        for stem in forms {
            let s = stem.lowercased()
            // Consonant + y flips to i: amplify -> amplifies, amplified. Writing "amplifyed"
            // instead would drop every such card out of the drill.
            if s.hasSuffix("y"), stem.count > 2, !isVowel(Array(s)[s.count - 2]) {
                let root = String(stem.dropLast())
                add(root + "ies")
                add(root + "ied")
                add(stem + "ing")
                continue
            }
            if s.hasSuffix("s") || s.hasSuffix("x") || s.hasSuffix("ch") || s.hasSuffix("sh") {
                add(stem + "es")
            } else {
                add(stem + "s")
            }
            if s.hasSuffix("e") {
                add(stem + "d")
                add(String(stem.dropLast()) + "ing")
            } else {
                add(stem + "ed")
                add(stem + "ing")
            }
        }
        return forms
    }

    private static func isVowel(_ character: Character) -> Bool {
        "aeiou".contains(character)
    }

    /// Blanks the headword in whichever form the sentence actually uses, and reports that form so
    /// the two choices offered to the learner agree in number and tense.
    static func blankOutInflected(_ word: String, in sentence: String) -> (blanked: String, form: String)? {
        // Longest first: "amplifiers" must win over "amplifier" inside the same sentence.
        for form in inflections(of: word).sorted(by: { $0.count > $1.count }) {
            if let blanked = blankOut(form, in: sentence) { return (blanked, form) }
        }
        return nil
    }

    /// When the headword was blanked as a plural, the wrong answer has to be plural too, or the
    /// grammar alone gives the question away.
    static func matchInflection(of distractor: String, headword: String, form: String) -> String {
        guard distractor.count > 2, !distractor.contains(" ") else { return distractor }
        let head = headword.lowercased()
        let used = form.lowercased()
        guard used != head else { return distractor }
        for suffix in ["ies", "es", "s", "ing", "ed"] where used == head + suffix || used.hasSuffix(suffix) {
            guard !distractor.lowercased().hasSuffix(suffix) else { return distractor }
            let inflected = inflections(of: distractor).first { $0.lowercased().hasSuffix(suffix) }
            return inflected ?? distractor
        }
        return distractor
    }

    /// Replaces the first whole-word occurrence of `word` with a blank, or returns nil when the
    /// word only appears inside a longer word (or not at all).
    static func blankOut(_ word: String, in sentence: String) -> String? {
        let lowerSentence = Array(sentence.lowercased())
        let lowerWord = Array(word.lowercased())
        guard !lowerWord.isEmpty, lowerSentence.count >= lowerWord.count else { return nil }
        let characters = Array(sentence)
        for start in 0...(lowerSentence.count - lowerWord.count) {
            let end = start + lowerWord.count
            guard Array(lowerSentence[start..<end]) == lowerWord else { continue }
            let beforeOK = start == 0 || !isWordCharacter(lowerSentence[start - 1])
            let afterOK = end == lowerSentence.count || !isWordCharacter(lowerSentence[end])
            guard beforeOK, afterOK else { continue }
            return String(characters[0..<start]) + "___" + String(characters[end...])
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "-"
    }
}
