// Self-check for LanguageDetector.confidentSourceLanguage, the rule that decides when an Auto
// source is sent to the model as a concrete language.
// Run it with `./Scripts/check-all.sh`, which owns the file list it compiles against.
import Foundation

/// LanguageDetector only reads the default lists from AppConfig; this stands in for it so the
/// check doesn't have to compile the whole config graph.
enum AppConfig {
    static let defaultLanguages = ["Auto detect", "English", "Vietnamese"]
    static let defaultTargetLanguages = ["English", "Vietnamese"]
}

@main
enum LanguageDetectorCheck {
    static var failures = 0
    static let languages = ["Auto detect", "English", "Vietnamese", "Chinese", "Japanese"]

    static func expect(_ actual: String?, _ expected: String?, _ label: String) {
        if actual == expected {
            print("ok   \(label)")
        } else {
            print("FAIL \(label): expected \(expected ?? "nil"), got \(actual ?? "nil")")
            failures += 1
        }
    }

    static func detect(_ text: String, target: String = "Vietnamese") -> String? {
        LanguageDetector.confidentSourceLanguage(text, target: target, candidates: languages)
    }

    static func main() {
        expect(detect("The committee postponed the vote until next week."), "English",
               "a clear English sentence is sent as English")
        expect(detect("Hôm nay trời mưa to nên tôi ở nhà đọc sách.", target: "English"), "Vietnamese",
               "a clear Vietnamese sentence is sent as Vietnamese")
        expect(detect("Short text."), nil, "text under 20 characters keeps Auto")
        expect(detect("The committee postponed the vote until next week.", target: "English"), nil,
               "a source equal to the target keeps Auto")
        expect(LanguageDetector.confidentSourceLanguage(
            "Der Ausschuss hat die Abstimmung auf nächste Woche verschoben.",
            target: "Vietnamese", candidates: languages
        ), nil, "a language outside the configured list keeps Auto")
        if failures > 0 { exit(1) }
    }
}
