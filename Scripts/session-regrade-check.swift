// Standalone check: re-grading a card inside one session replaces the earlier grade instead of
// stacking on it. Mirrors ReviewWindowController.applyGrade, which rewinds to the session
// baseline before writing. See CLAUDE.md, `swift test` cannot run in this toolchain.
//
//   swiftc -parse-as-library Sources/translate/TranslationHistoryStore.swift \
//     Sources/translate/ReviewPlanner.swift Sources/translate/LearnCard.swift \
//     Scripts/session-regrade-check.swift -o /tmp/session-regrade-check && /tmp/session-regrade-check
import Foundation

/// AppConfig drags in AppKit; the convenience init only reads this property.
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

private func card() -> TranslationRecord {
    TranslationRecord(
        id: UUID(),
        timestamp: Date(),
        mode: .learn,
        sourceText: "amplify",
        resultText: "khuech dai",
        sourceLanguage: "English",
        targetLanguage: "Vietnamese",
        isSaved: true
    )
}

/// The rewind ReviewWindowController performs through `store.restoreSRS(from:)`.
private func rewind(_ record: inout TranslationRecord, to baseline: TranslationRecord) {
    record.dueDate = baseline.dueDate
    record.interval = baseline.interval
    record.ease = baseline.ease
    record.repetitions = baseline.repetitions
    record.lapses = baseline.lapses
    record.lastReviewedAt = baseline.lastReviewedAt
}

@main
struct SessionRegradeCheck {
    static func main() {
        let now = Date()

        var once = card()
        once.applySRSGrade(.again, currentDate: now)

        var repeated = card()
        let baseline = repeated
        for _ in 0..<3 {
            rewind(&repeated, to: baseline)
            repeated.applySRSGrade(.again, currentDate: now)
        }
        expect(repeated.lapses == once.lapses, "three Again taps wrote \(repeated.lapses) lapses, expected \(once.lapses)")
        expect(repeated.ease == once.ease, "ease drifted: \(repeated.ease) vs \(once.ease)")
        expect(repeated.repetitions == once.repetitions, "repetitions drifted")

        // Changing the mind mid-session lands on the last grade, as if it were the only one.
        var changed = card()
        let changedBaseline = changed
        changed.applySRSGrade(.again, currentDate: now)
        rewind(&changed, to: changedBaseline)
        changed.applySRSGrade(.easy, currentDate: now)

        var easyOnly = card()
        easyOnly.applySRSGrade(.easy, currentDate: now)
        expect(changed.interval == easyOnly.interval, "final grade did not win: \(changed.interval) vs \(easyOnly.interval)")
        expect(changed.lapses == easyOnly.lapses, "stale lapse survived the change of mind")

        // Without the rewind the old behaviour must still look wrong, or the check proves nothing.
        var stacked = card()
        for _ in 0..<3 { stacked.applySRSGrade(.again, currentDate: now) }
        expect(stacked.lapses > once.lapses, "check is blind: stacking no longer differs")

        if failures > 0 {
            FileHandle.standardError.write(Data("session-regrade-check: \(failures) failure(s)\n".utf8))
            exit(1)
        }
        print("session-regrade-check OK")
    }
}
