// Standalone check for DeckStats. See CLAUDE.md: `swift test` cannot run in this toolchain, so
// non-trivial pure logic gets a check that compiles with swiftc.
//
//   swiftc -parse-as-library Sources/translate/TranslationHistoryStore.swift \
//     Sources/translate/ReviewPlanner.swift Sources/translate/LearnCard.swift Sources/translate/DeckStats.swift \
//     Scripts/deck-stats-check.swift -o /tmp/deck-stats-check && /tmp/deck-stats-check
import Foundation

/// TranslationHistoryStore has one convenience init that mentions AppConfig, and AppConfig drags
/// in AppKit plus the prompt files. The check only needs TranslationRecord, so it stands in with
/// the single property that init reads.
struct AppConfig {
    var historyDirectoryURL: URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
}

private var failures = 0

private func expect(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }
}

private let calendar = Calendar(identifier: .gregorian)
private let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 10))!

private func day(_ offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: now)!
}

private func card(
    _ text: String,
    saved: Bool = true,
    due: Date? = nil,
    interval: Int = 0,
    repetitions: Int = 0,
    lapses: Int = 0,
    reviewed: Date? = nil
) -> TranslationRecord {
    TranslationRecord(
        id: UUID(),
        timestamp: day(-30),
        mode: .learn,
        sourceText: text,
        resultText: "x",
        sourceLanguage: "English",
        targetLanguage: "Vietnamese",
        isSaved: saved,
        dueDate: due,
        interval: interval,
        ease: 2.5,
        repetitions: repetitions,
        lapses: lapses,
        lastReviewedAt: reviewed
    )
}

@main
struct DeckStatsCheck {
    static func main() {
        // A leech outranks every other bucket, even when it also looks due.
        expect(
            DeckStats.bucket(for: card("a", due: day(-1), interval: 5, repetitions: 4, lapses: 8, reviewed: day(-5)),
                             currentDate: now, calendar: calendar) == .leech,
            "8 lapses must read as leech even when due"
        )
        expect(
            DeckStats.bucket(for: card("b", repetitions: 0, lapses: 0),
                             currentDate: now, calendar: calendar) == .new,
            "never reviewed must read as new"
        )
        // Saved without a due date is due immediately, matching dueReviews().
        expect(
            DeckStats.bucket(for: card("c", due: nil, interval: 3, repetitions: 2, lapses: 0, reviewed: day(-3)),
                             currentDate: now, calendar: calendar) == .due,
            "no due date must read as due"
        )
        expect(
            DeckStats.bucket(for: card("d", due: day(3), interval: 4, repetitions: 3, lapses: 0, reviewed: day(-1)),
                             currentDate: now, calendar: calendar) == .learning,
            "short interval not yet due must read as learning"
        )
        expect(
            DeckStats.bucket(for: card("e", due: day(10), interval: 30, repetitions: 8, lapses: 0, reviewed: day(-20)),
                             currentDate: now, calendar: calendar) == .mastered,
            "interval past 21 days not yet due must read as mastered"
        )
        // Later today still counts as today.
        expect(
            DeckStats.isDue(card("f", due: calendar.date(bySettingHour: 22, minute: 0, second: 0, of: now)!),
                            currentDate: now, calendar: calendar),
            "a due time later today must still count as due"
        )
        expect(
            !DeckStats.isDue(card("g", due: day(1)), currentDate: now, calendar: calendar),
            "tomorrow must not count as due today"
        )

        let deck = [
            card("leech", due: day(-2), interval: 2, repetitions: 3, lapses: 9, reviewed: day(-2)),
            card("new"),
            card("due", due: day(-1), interval: 2, repetitions: 1, reviewed: day(-3)),
            card("learning", due: day(2), interval: 5, repetitions: 3, reviewed: day(-1)),
            card("mastered", due: day(9), interval: 40, repetitions: 9, reviewed: day(-2)),
            card("tomorrow", due: day(1), interval: 6, repetitions: 4, reviewed: now),
            card("unsaved", saved: false, due: day(-1))
        ]
        let stats = DeckStats.compute(records: deck, currentDate: now, calendar: calendar)
        expect(stats.totalSaved == 6, "unsaved records must be ignored, got \(stats.totalSaved)")
        expect(stats.count(.leech) == 1, "one leech expected, got \(stats.count(.leech))")
        expect(stats.count(.new) == 1, "one new expected, got \(stats.count(.new))")
        expect(stats.count(.due) == 1, "one due expected, got \(stats.count(.due))")
        expect(stats.count(.learning) == 2, "two learning expected (one due later, one tomorrow), got \(stats.count(.learning))")
        expect(stats.count(.mastered) == 1, "one mastered expected, got \(stats.count(.mastered))")
        let bucketed = DeckStats.Bucket.allCases.reduce(0) { $0 + stats.count($1) }
        expect(bucketed == stats.totalSaved, "every saved card belongs to exactly one bucket")
        // leech + new + due all sit in today's workload.
        expect(stats.dueToday == 3, "three cards due today, got \(stats.dueToday)")
        expect(stats.dueTomorrow == 1, "one card due tomorrow, got \(stats.dueTomorrow)")

        // Streak: nothing today yet, three days back to back before it.
        let quietToday = Set([day(-1), day(-2), day(-3)].map { calendar.startOfDay(for: $0) })
        expect(
            DeckStats.streak(reviewDays: quietToday, currentDate: now, calendar: calendar) == 3,
            "a day not studied yet must not break the streak"
        )
        let studiedToday = quietToday.union([calendar.startOfDay(for: now)])
        expect(
            DeckStats.streak(reviewDays: studiedToday, currentDate: now, calendar: calendar) == 4,
            "studying today must extend the streak"
        )
        // A whole missed day ends it.
        let gap = Set([day(-2), day(-3)].map { calendar.startOfDay(for: $0) })
        expect(
            DeckStats.streak(reviewDays: gap, currentDate: now, calendar: calendar) == 0,
            "a full missed day must end the streak"
        )

        let week = DeckStats.last7Days(
            reviewDates: [now, now, day(-6), day(-8)],
            currentDate: now,
            calendar: calendar
        )
        expect(week.count == 7, "the week must have seven days")
        expect(week.last == 2, "today's column must count both of today's reviews")
        expect(week.first == 1, "six days back is the first column")
        expect(week.reduce(0, +) == 3, "anything older than seven days must be dropped")

        if failures == 0 {
            print("deck-stats-check: all checks passed")
        } else {
            FileHandle.standardError.write(Data("deck-stats-check: \(failures) failure(s)\n".utf8))
            exit(1)
        }
    }
}
