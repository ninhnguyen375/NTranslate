// How the saved deck looks right now: one bucket per card, plus the streak numbers the home
// screen draws. Pure Foundation so `Scripts/deck-stats-check.swift` can exercise every rule
// without launching the app.
import Foundation

struct DeckStats: Equatable, Sendable {
    /// Every saved card lands in exactly one bucket. `leech` is tested first: a card that keeps
    /// being missed is a problem to fix, not a review to schedule.
    enum Bucket: String, CaseIterable, Sendable {
        case due, learning, new, mastered, leech

        var label: String {
            switch self {
            case .due: return "Due"
            case .learning: return "Learning"
            case .new: return "New"
            case .mastered: return "Mastered"
            case .leech: return "Leech"
            }
        }

        var detail: String {
            switch self {
            case .due: return "due for review"
            case .learning: return "still learning"
            case .new: return "never reviewed"
            case .mastered: return "already known"
            case .leech: return "missed too often"
            }
        }
    }

    /// An interval this long means the card is holding on its own.
    static let masteredInterval = 21

    var counts: [Bucket: Int] = [:]
    var dueToday = 0
    var dueTomorrow = 0
    var dayStreak = 0
    /// Cards reviewed on each of the last seven days; the last element is today.
    var last7Days: [Int] = Array(repeating: 0, count: 7)
    var totalSaved = 0

    func count(_ bucket: Bucket) -> Int { counts[bucket] ?? 0 }

    static func bucket(
        for record: TranslationRecord,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bucket {
        if ReviewPlanner.isLeech(lapses: record.lapses) { return .leech }
        if record.repetitions == 0 && record.lastReviewedAt == nil { return .new }
        if isDue(record, currentDate: currentDate, calendar: calendar) { return .due }
        return record.interval >= masteredInterval ? .mastered : .learning
    }

    /// Same rule `TranslationHistoryStore.dueReviews()` uses: no due date means due now.
    static func isDue(
        _ record: TranslationRecord,
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let due = record.dueDate else { return true }
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: currentDate) ?? currentDate
        return due <= endOfToday
    }

    static func compute(
        records: [TranslationRecord],
        currentDate: Date = Date(),
        calendar: Calendar = .current
    ) -> DeckStats {
        let saved = records.filter { $0.isSaved }
        var stats = DeckStats()
        stats.totalSaved = saved.count
        for record in saved {
            let bucket = bucket(for: record, currentDate: currentDate, calendar: calendar)
            stats.counts[bucket, default: 0] += 1
            if isDue(record, currentDate: currentDate, calendar: calendar) { stats.dueToday += 1 }
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: currentDate)),
           let dayAfter = calendar.date(byAdding: .day, value: 1, to: tomorrow) {
            stats.dueTomorrow = saved.filter { record in
                guard let due = record.dueDate else { return false }
                return due >= tomorrow && due < dayAfter
            }.count
        }
        let reviewDays = Set(saved.compactMap { $0.lastReviewedAt }.map { calendar.startOfDay(for: $0) })
        stats.dayStreak = streak(reviewDays: reviewDays, currentDate: currentDate, calendar: calendar)
        stats.last7Days = last7Days(
            reviewDates: saved.compactMap { $0.lastReviewedAt },
            currentDate: currentDate,
            calendar: calendar
        )
        return stats
    }

    /// Counts back from today. A day that has not been studied yet does not break the streak,
    /// so opening the app in the morning never shows the chain as already lost.
    static func streak(reviewDays: Set<Date>, currentDate: Date, calendar: Calendar) -> Int {
        var day = calendar.startOfDay(for: currentDate)
        if !reviewDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while reviewDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Only the most recent review of a card is stored, so a day's number is "cards whose last
    /// review landed that day", not every answer given that day.
    static func last7Days(reviewDates: [Date], currentDate: Date, calendar: Calendar) -> [Int] {
        let today = calendar.startOfDay(for: currentDate)
        var days: [Date] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            days.append(day)
        }
        var buckets = [Date: Int]()
        for date in reviewDates {
            buckets[calendar.startOfDay(for: date), default: 0] += 1
        }
        return days.map { buckets[$0] ?? 0 }
    }
}
