// Count plus noun, agreeing in number. The UI is English-only, and every noun it counts
// (card, day, month, year, time) is regular, so a trailing "s" is the whole rule.
import Foundation

enum Plural {
    /// `count(1, "card")` is "1 card"; `count(0, "card")` and `count(2, "card")` are "0 cards"
    /// and "2 cards". English treats zero as plural.
    static func count(_ value: Int, _ singular: String) -> String {
        "\(value) \(noun(value, singular))"
    }

    /// The noun alone, for callers that place the number themselves.
    static func noun(_ value: Int, _ singular: String) -> String {
        value == 1 ? singular : singular + "s"
    }
}
