// Standalone check for the review logic that has no UI: which question a card asks, how an answer
// grades itself, how the schedule advances, and how a session is ordered.
//
//   swiftc -parse-as-library Sources/translate/LearnCard.swift Sources/translate/ReviewPlanner.swift \
//     Scripts/review-planner-check.swift -o /tmp/review-planner-check && /tmp/review-planner-check
import Foundation

private var failures = 0

private func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("ok   - \(message)")
    } else {
        failures += 1
        print("FAIL - \(message)")
    }
}

@main
struct ReviewPlannerCheck {
    static let all: Set<ReviewPlanner.QuestionKind> = Set(ReviewPlanner.QuestionKind.allCases)

    static func main() {
        checkAutoKind()
        checkResolve()
        checkGrading()
        checkSchedule()
        checkPractice()
        checkSession()
        checkInflection()

        if failures == 0 {
            print("\nAll review planner checks passed.")
        } else {
            print("\n\(failures) check(s) failed.")
            exit(1)
        }
    }

    // MARK: - Question choice

    static func checkAutoKind() {
        expect(ReviewPlanner.autoKind(interval: 0, repetitions: 0, available: all) == .flip,
               "a brand new card only has to be recognised")
        expect(ReviewPlanner.autoKind(interval: 2, repetitions: 1, available: all) == .cloze,
               "a young card gets a cloze")
        expect(ReviewPlanner.autoKind(interval: 6, repetitions: 3, available: all) == .contrast,
               "a settling card gets a contrast")
        expect(ReviewPlanner.autoKind(interval: 14, repetitions: 5, available: all) == .recall,
               "a mature card has to be produced from its meaning")
        expect(ReviewPlanner.autoKind(interval: 40, repetitions: 8, available: all) == .listen,
               "a well known card is asked by ear")
        expect(ReviewPlanner.autoKind(interval: 40, repetitions: 8, available: [.flip, .cloze]) == .cloze,
               "the ladder skips what the card cannot ask")
        expect(ReviewPlanner.autoKind(interval: 40, repetitions: 8, available: [.flip]) == .flip,
               "a card with no data still flips")
        expect(ReviewPlanner.autoKind(interval: 2, repetitions: 1, available: [.collocation, .flip]) == .collocation,
               "a young card with no cloze still practises the pairing")
        expect(ReviewPlanner.autoKind(interval: 14, repetitions: 5, available: [.family, .flip]) == .family,
               "a mature card with no recall still produces a related form")
    }

    static func checkResolve() {
        let forced = ReviewPlanner.resolve(requested: .contrast, interval: 0, repetitions: 0, available: [.flip, .contrast])
        expect(forced.kind == .contrast && forced.note == nil, "a supported forced mode is honoured silently")

        let denied = ReviewPlanner.resolve(requested: .contrast, interval: 0, repetitions: 0, available: [.flip])
        expect(denied.kind == .flip, "an unsupported forced mode falls back to flip")
        expect(denied.note?.contains("contrast") == true, "the fallback says why, instead of failing silently")

        let auto = ReviewPlanner.resolve(requested: nil, interval: 2, repetitions: 1, available: all)
        expect(auto.kind == .cloze && auto.note == nil, "auto picks by maturity with nothing to explain")
    }

    // MARK: - Grading

    static func checkGrading() {
        expect(ReviewPlanner.autoGrade(correct: false, nearMiss: false, elapsed: 1) == .again,
               "a wrong answer is a lapse regardless of speed")
        expect(ReviewPlanner.autoGrade(correct: true, nearMiss: false, elapsed: 2) == .easy,
               "a fast right answer is easy")
        expect(ReviewPlanner.autoGrade(correct: true, nearMiss: false, elapsed: 20) == .hard,
               "a slow right answer is hard")
        expect(ReviewPlanner.autoGrade(correct: true, nearMiss: true, elapsed: 1) == .hard,
               "a typo costs the easy grade but not the card")

        expect(ReviewPlanner.isNearMiss(typed: "amplifer", answer: "amplifier"), "one missing letter is a typo")
        expect(ReviewPlanner.isNearMiss(typed: "Amplifier ", answer: "amplifier") == false,
               "case and spacing already count as correct, not as a typo")
        expect(ReviewPlanner.isNearMiss(typed: "cut", answer: "cat") == false,
               "short words are different words, not typos")
        expect(ReviewPlanner.isNearMiss(typed: "speaker", answer: "amplifier") == false,
               "a different word is not a typo")
        expect(ReviewPlanner.editDistance([], Array("word"), limit: 9) == 4,
               "an empty answer measures as its own length instead of trapping")
        expect(ReviewPlanner.editDistance(Array("word"), [], limit: 9) == 4,
               "an empty guess measures the same way round")
    }

    // MARK: - Schedule

    static func checkSchedule() {
        let again = ReviewPlanner.nextSchedule(grade: .again, interval: 30, ease: 2.5)
        expect(again.interval == 1 && again.ease < 2.5, "a lapse restarts the interval and lowers ease")

        let easy = ReviewPlanner.nextSchedule(grade: .easy, interval: 10, ease: 2.5, fuzz: 1.0)
        expect(easy.interval == 25 && easy.ease > 2.5, "an easy answer multiplies by ease")

        let capped = ReviewPlanner.nextSchedule(grade: .easy, interval: 300, ease: 2.5, fuzz: 1.0)
        expect(capped.interval == ReviewPlanner.maxIntervalDays, "intervals never run past a year")

        let low = ReviewPlanner.nextSchedule(grade: .easy, interval: 10, ease: 2.5, fuzz: 0.85)
        let high = ReviewPlanner.nextSchedule(grade: .easy, interval: 10, ease: 2.5, fuzz: 1.15)
        expect(low.interval < easy.interval && high.interval > easy.interval,
               "fuzz spreads a day's reviews in both directions")

        let short = ReviewPlanner.nextSchedule(grade: .hard, interval: 1, ease: 2.5, fuzz: 0.85)
        expect(short.interval == 2, "short intervals are left alone, fuzz would round them to nothing")

        let floored = ReviewPlanner.nextSchedule(grade: .easy, interval: 1, ease: 1.3, fuzz: 0.85)
        expect(floored.interval >= 1, "no schedule ever lands on zero days")

        expect(ReviewPlanner.isLeech(lapses: 8) && !ReviewPlanner.isLeech(lapses: 7),
               "a leech is flagged at eight lapses")
    }

    // MARK: - Practice

    static func checkPractice() {
        expect(ReviewPlanner.writesSchedule(isPractice: true) == false,
               "Review All does not move the SM-2 schedule")
        expect(ReviewPlanner.writesSchedule(isPractice: false),
               "Start Review writes the schedule")
        expect(ReviewPlanner.gradeIntervalCaption(isPractice: true, scheduled: "2 days").isEmpty,
               "practice grade buttons do not promise a due date")
        expect(ReviewPlanner.gradeIntervalCaption(isPractice: false, scheduled: "2 days") == "2 days",
               "a real review still shows the interval the grade would schedule")
    }

    // MARK: - Session order

    static func checkSession() {
        expect(ReviewPlanner.requeueIndex(currentIndex: 0, count: 20) == 11,
               "a missed card comes back after the gap, not immediately")
        expect(ReviewPlanner.requeueIndex(currentIndex: 18, count: 20) == 20,
               "near the end it goes last instead of past the end")

        let ordered = ["amplify", "amplitude", "banana", "cherry"]
        let spread = ReviewPlanner.interleave(ordered) { $0 }
        expect(spread[0] == "amplify" && spread[1] != "amplitude",
               "same-family neighbours are pulled apart")
        expect(Set(spread) == Set(ordered) && spread.count == ordered.count,
               "interleaving keeps every card exactly once")

        let unavoidable = ["amplify", "amplitude"]
        expect(ReviewPlanner.interleave(unavoidable) { $0 } == unavoidable,
               "with nothing to swap in, the order is left as it is")
    }

    // MARK: - Inflected blanks

    static func checkInflection() {
        let plural = ConfusableDrillItem.blankOutInflected("amplifier", in: "The amplifiers boosted the signal.")
        expect(plural?.blanked == "The ___ boosted the signal.", "a plural in the sentence is still blanked")
        expect(plural?.form == "amplifiers", "the blank reports the form the sentence used")

        let singular = ConfusableDrillItem.blankOutInflected("amplifiers", in: "The amplifier boosted the signal.")
        expect(singular?.form == "amplifier", "a plural headword matches its singular too")

        expect(ConfusableDrillItem.blankOutInflected("amplifier", in: "The speakers blew out.") == nil,
               "a sentence without the headword is still skipped")

        expect(ConfusableDrillItem.matchInflection(of: "speaker", headword: "amplifier", form: "amplifiers") == "speakers",
               "the wrong answer is inflected to match, or grammar gives it away")
        expect(ConfusableDrillItem.matchInflection(of: "speaker", headword: "amplifier", form: "amplifier") == "speaker",
               "an uninflected blank leaves the distractor alone")

        // Consonant + y is the single most common English verb ending; getting it wrong drops
        // every amplify/verify/classify card out of the drill.
        let past = ConfusableDrillItem.blankOutInflected("amplify", in: "The signal was amplified before transmission.")
        expect(past?.form == "amplified", "a consonant+y verb is found in its -ied past tense")
        expect(ConfusableDrillItem.blankOutInflected("amplify", in: "It amplifies the signal.")?.form == "amplifies",
               "and in its -ies present tense")
        expect(ConfusableDrillItem.blankOutInflected("amplified", in: "This amplify circuit is old.")?.form == "amplify",
               "an -ied headword reduces back to its base form")
        expect(ConfusableDrillItem.inflections(of: "amplify").contains("amplifyed") == false,
               "no non-word inflections are offered")
        expect(ConfusableDrillItem.matchInflection(of: "diversify", headword: "amplify", form: "amplified") == "diversified",
               "the distractor follows the same spelling rule")

        let card = LearnCard.parse("""
        Từ gốc: amplifier
        n. thiết bị khuếch đại tín hiệu âm thanh

        Dễ nhầm với
        - speaker: speaker phát ra âm thanh, amplifier chỉ khuếch đại tín hiệu
          → The amplifiers boosted the weak guitar signal.
        """)
        let drill = ConfusableDrillItem.build(from: [card]).first
        expect(drill?.sentence == "The ___ boosted the weak guitar signal.", "the drill blanks the inflected headword")
        expect(drill?.correct == "amplifiers" && drill?.distractor == "speakers", "both choices agree in number")
        expect(card.recall?.answer == "amplifier", "the meaning line powers the reverse question")
        expect(card.recall?.prompt.contains("khuếch đại") == true, "the reverse question shows the meaning, not the word")
    }
}
