import Foundation

enum PopoverFeedback {
    static let emptySelectionGuidance =
        "No text selected. Select text and press the hotkey, or type here then Translate."
    static let textTooLong = "Text is too long to translate."
    static let emptyInputHint = "Enter or paste text, then Translate."
    static let translating = "Translating..."
    static let learning = "Learning..."

    enum ResultStyle: Equatable {
        case normal
        case loading
        case error
    }

    static func resultStyle(for text: String) -> ResultStyle {
        if text == translating || text == learning
            || text == emptySelectionGuidance || text == emptyInputHint
        {
            return .loading
        }
        if text == textTooLong || text.hasPrefix("Error:") {
            return .error
        }
        return .normal
    }

    static func isStale(resultGeneration: Int, currentGeneration: Int) -> Bool {
        resultGeneration != currentGeneration
    }

    static func isCopyableResult(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch trimmed {
        case translating, learning, emptySelectionGuidance, emptyInputHint, textTooLong:
            return false
        default:
            return !trimmed.hasPrefix("Error:")
        }
    }

    static func accessibilityFallbackNote(source: TranslatableTextSource) -> String {
        let sourceName = source == .simulatedCopy ? "simulated copy" : "clipboard"
        return "Used \(sourceName) (selection read failed)"
    }
}
