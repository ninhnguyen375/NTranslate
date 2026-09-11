// Self-check for Plural. Run with:
//   swiftc -parse-as-library Sources/translate/Plural.swift Scripts/plural-check.swift \
//     -o /tmp/plural-check && /tmp/plural-check
import Foundation

@main
enum PluralCheck {
    static var failures = 0

    static func expect(_ actual: String, _ expected: String, _ label: String) {
        if actual == expected {
            print("ok   \(label)")
        } else {
            print("FAIL \(label): expected \(expected), got \(actual)")
            failures += 1
        }
    }

    static func main() {
        expect(Plural.count(1, "card"), "1 card", "one stays singular")
        expect(Plural.count(2, "card"), "2 cards", "two is plural")
        // English counts zero as plural, which is what the review summary needs.
        expect(Plural.count(0, "card"), "0 cards", "zero is plural")
        expect(Plural.count(-1, "card"), "-1 cards", "a negative count does not read as singular")

        // The nouns the review screens actually count.
        expect(Plural.count(1, "day"), "1 day", "day singular")
        expect(Plural.count(30, "day"), "30 days", "day plural")
        expect(Plural.count(1, "month"), "1 month", "month singular")
        expect(Plural.count(1, "year"), "1 year", "year singular")
        expect(Plural.count(1, "time"), "1 time", "time singular")
        expect(Plural.count(8, "time"), "8 times", "time plural")

        // Multi-word nouns pluralize on the head word because it sits last.
        expect(Plural.count(1, "missed card"), "1 missed card", "multi-word singular")
        expect(Plural.count(3, "missed card"), "3 missed cards", "multi-word plural")

        expect(Plural.noun(1, "card"), "card", "noun alone, singular")
        expect(Plural.noun(4, "card"), "cards", "noun alone, plural")

        if failures > 0 {
            print("\n\(failures) check(s) failed.")
            exit(1)
        }
        print("\nAll plural checks passed.")
    }
}
