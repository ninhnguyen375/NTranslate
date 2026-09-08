// Passages written before scenarios were kept must still decode, and a passage carrying a scenario
// must round-trip it.
import Foundation

@main
struct WeaveScenarioCheck {
    static func main() throws {
        let legacy = Data("""
        {"words":["latte"],"text":"Topic: X","promptVersion":"7","generatedAt":810546216.0}
        """.utf8)
        let old = try JSONDecoder().decode(WeavePassage.self, from: legacy)
        assert(old.scenario == nil, "legacy passage must decode with no scenario")
        assert(old.words == ["latte"])

        let fresh = WeavePassage(
            words: [], text: "Topic: X", promptVersion: "8", generatedAt: Date(),
            scenario: "Two friends at a Starbucks counter"
        )
        let round = try JSONDecoder().decode(WeavePassage.self, from: JSONEncoder().encode(fresh))
        assert(round.scenario == "Two friends at a Starbucks counter", "scenario must survive a round trip")

        print("weave-scenario-check: ok")
    }
}
