// Self-check for the 9Router judge helpers: URL rewrite, response parsing, and their nil fallbacks.
// Run it with `./Scripts/check-all.sh judge`, which owns the file list it compiles against.
import Foundation

/// Stand-in for the one AppKit helper `AppConfigPrompts` calls, as in build-vocab-pack.swift.
enum SettingsWindowController {
    static func promptNeedsSync(current: String, appDefault: String) -> Bool { false }
}

@main
enum JudgeCheck {
    static func main() {
        var failures = 0
        func expect(_ ok: Bool, _ label: String) {
            print(ok ? "ok   \(label)" : "FAIL \(label)")
            if !ok { failures += 1 }
        }
        expect(Translator.judgeURL(from: "https://host/v1/chat/completions")?.absoluteString == "https://host/v1/systemone",
               "chat completions URL maps to systemone")
        expect(Translator.judgeURL(from: "https://api.example.com/v1/responses") == nil,
               "a non-9Router URL disables the judge")
        let body = #"{"answers":{"q":{"type":"noul","noul":0.99}}}"#.data(using: .utf8)!
        expect(Translator.judgeScore(from: body) == 0.99, "score is read from answers.q.noul")
        expect(Translator.judgeScore(from: Data("{}".utf8)) == nil, "missing answer yields nil")
        expect(!Translator.isTermCandidate("go"), "short words skip the judge")
        expect(Translator.isTermCandidate("go back to square one"), "a 5-word phrase asks the judge")
        expect(!Translator.isTermCandidate("I went home, then slept."), "sentence punctuation skips the judge")
        exit(failures == 0 ? 0 : 1)
    }
}
