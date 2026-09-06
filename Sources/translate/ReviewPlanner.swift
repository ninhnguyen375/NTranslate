// Pure review logic: what a card should ask, how an answer grades itself, and when the card
// comes back. Nothing here touches AppKit, the store, or the disk, so every rule below can be
// exercised by `Scripts/review-planner-check.swift` without launching the app.
import Foundation

enum SRSGrade: Int, Sendable {
    case again = 0 // Lại
    case hard = 1  // Khó
    case easy = 2  // Dễ
}

enum ReviewPlanner {
    /// How a card asks its question. `flip` is the original show-then-reveal card; the rest build
    /// a real question out of text the card already carries, so none of them costs a request.
    enum QuestionKind: Int, CaseIterable, Sendable {
        case flip = 0
        case cloze = 1
        case contrast = 2
        case recall = 3
        case listen = 4

        var label: String {
            switch self {
            case .flip: return "Flip"
            case .cloze: return "Cloze"
            case .contrast: return "Contrast"
            case .recall: return "Recall"
            case .listen: return "Listen"
            }
        }
    }

    // MARK: - Picking the question

    /// Harder questions as the memory gets older: a brand new card only has to be recognised,
    /// a card that already survived a few reviews has to be produced from meaning or sound.
    static func autoKind(interval: Int, repetitions: Int, available: Set<QuestionKind>) -> QuestionKind {
        let ladder: [QuestionKind]
        switch (interval, repetitions) {
        case let (i, r) where i == 0 || r == 0:
            ladder = [.flip]
        case let (i, _) where i < 4:
            ladder = [.cloze, .flip]
        case let (i, _) where i < 10:
            ladder = [.contrast, .cloze, .flip]
        case let (i, _) where i < 21:
            ladder = [.recall, .contrast, .cloze, .flip]
        default:
            ladder = [.listen, .recall, .contrast, .cloze, .flip]
        }
        return ladder.first(where: available.contains) ?? .flip
    }

    /// What the card will actually ask, plus the note to show when the wish could not be granted.
    /// A forced mode that the card cannot support used to fall back in silence, which read as a
    /// broken button.
    static func resolve(
        requested: QuestionKind?,
        interval: Int,
        repetitions: Int,
        available: Set<QuestionKind>
    ) -> (kind: QuestionKind, note: String?) {
        guard let requested else {
            return (autoKind(interval: interval, repetitions: repetitions, available: available), nil)
        }
        if requested == .flip || available.contains(requested) { return (requested, nil) }
        return (.flip, "This card has no \(requested.label.lowercased()) data, showing Flip.")
    }

    // MARK: - Grading an answer

    /// A question mode already knows whether the answer was right, so the learner should not have
    /// to grade the same recall twice. Speed separates "knew it" from "worked it out".
    static let fastAnswerSeconds: TimeInterval = 6

    static func autoGrade(correct: Bool, nearMiss: Bool, elapsed: TimeInterval) -> SRSGrade {
        if !correct { return .again }
        if nearMiss { return .hard }
        return elapsed <= fastAnswerSeconds ? .easy : .hard
    }

    /// One typo should not cost a full lapse, so a single-character slip counts as a hard hit
    /// instead of a miss. Short words are excluded: "cat" vs "cut" is a different word, not a typo.
    static func isNearMiss(typed: String, answer: String) -> Bool {
        let a = LearnCard.normalizeAnswer(typed)
        let b = LearnCard.normalizeAnswer(answer)
        guard a != b, b.count >= 4 else { return false }
        return editDistance(Array(a), Array(b), limit: 1) <= 1
    }

    /// Levenshtein distance, abandoned as soon as it passes `limit`.
    static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = previous
        for i in 1...a.count {
            current[0] = i
            var rowBest = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > limit { return limit + 1 }
            previous = current
        }
        return previous[b.count]
    }

    // MARK: - Scheduling

    static let maxIntervalDays = 365
    /// Anki's own threshold: a card missed this often is fighting the learner, not teaching them.
    static let leechLapses = 8

    static func isLeech(lapses: Int) -> Bool { lapses >= leechLapses }

    /// SM-2 with two guards: intervals never run past a year, and anything longer than a couple of
    /// days is spread by `fuzz` so a big day of reviews does not rebuild itself every cycle.
    static func nextSchedule(
        grade: SRSGrade,
        interval: Int,
        ease: Double,
        fuzz: Double = 1.0
    ) -> (interval: Int, ease: Double) {
        let currentEase = ease > 1.3 ? ease : 2.5
        var next: Int
        var nextEase: Double

        switch grade {
        case .again:
            next = 1
            nextEase = max(1.3, currentEase - 0.2)
        case .hard:
            next = interval <= 1 ? 2 : Int(Double(interval) * 1.2)
            nextEase = max(1.3, currentEase - 0.15)
        case .easy:
            if interval == 0 {
                next = 1
            } else if interval == 1 {
                next = 3
            } else {
                next = max(interval + 1, Int(Double(interval) * currentEase))
            }
            nextEase = currentEase + 0.1
        }

        if next >= 3 {
            next = max(3, Int((Double(next) * fuzz).rounded()))
        }
        next = min(max(1, next), maxIntervalDays)
        return (next, nextEase)
    }

    static func randomFuzz() -> Double { Double.random(in: 0.85...1.15) }

    // MARK: - Session order

    /// A missed card comes back later in the same session instead of waiting for tomorrow: the
    /// first successful recall after a miss is what actually fixes the memory.
    static let relearnGap = 10
    static let maxRelearnPerCard = 2

    static func requeueIndex(currentIndex: Int, count: Int, gap: Int = relearnGap) -> Int {
        min(count, currentIndex + gap + 1)
    }

    /// Pulls apart neighbours from the same word family ("amplify" next to "amplitude"), which
    /// otherwise prime each other and make the recall look stronger than it is.
    static func interleave<T>(_ items: [T], key: (T) -> String) -> [T] {
        guard items.count > 2 else { return items }
        var result = items
        for index in 1..<result.count where sharesStem(key(result[index - 1]), key(result[index])) {
            // Take the nearest later card that clashes with neither side of the gap it fills.
            guard let swap = (index + 1..<result.count).first(where: { candidate in
                !sharesStem(key(result[index - 1]), key(result[candidate]))
                    && !sharesStem(key(result[candidate]), result[safe: index + 1].map(key))
            }) else { continue }
            result.swapAt(index, swap)
        }
        return result
    }

    static func sharesStem(_ lhs: String, _ rhs: String?) -> Bool {
        guard let rhs else { return false }
        let a = lhs.lowercased()
        let b = rhs.lowercased()
        guard a.count >= 4, b.count >= 4 else { return a == b && !a.isEmpty }
        return a.prefix(4) == b.prefix(4)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
