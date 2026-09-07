import Foundation

enum PopoverFeedback {
    static let emptySelectionGuidance =
        "No text selected. Select text and press the hotkey, or type here then Translate."
    static let accessibilityRequired =
        "Grant Accessibility access in System Settings > Privacy & Security > Accessibility, then quit and reopen NTranslate."
    static let textTooLong = "Text is too long to translate."
    static let emptyInputHint = "Enter or paste text, then Translate."
    static let translating = "Translating..."
    static let learning = "Learning..."
    static let proofreading = "Proofreading..."
    static let stopped = "Stopped"
    static let setupNeedsAPIKey = "Add your API key in Settings to start translating."
    static let setupNeedsAccessibility = "Grant Accessibility access so NTranslate can read the selected text."

    static func emptySelectionGuidance(hotkey: String) -> String {
        "No text selected. Select text and press \(hotkey), or type here then Translate."
    }

    enum ResultStyle: Equatable {
        case normal
        case loading
        case error
    }

    static func resultStyle(for text: String) -> ResultStyle {
        if text == translating || text == learning || text == proofreading || text == stopped
            || text == emptySelectionGuidance || text == emptyInputHint
            || text.hasPrefix("No text selected.")
        {
            return .loading
        }
        if text == textTooLong
            || text == accessibilityRequired
            || text == setupNeedsAPIKey
            || text == setupNeedsAccessibility
            || text.hasPrefix("Error:")
            || text.hasPrefix("Config load error:")
        {
            return .error
        }
        return .normal
    }

    static func isStale(resultGeneration: Int, currentGeneration: Int) -> Bool {
        resultGeneration != currentGeneration
    }

    static func isCopyableResult(_ text: String, isStreaming: Bool = false) -> Bool {
        if isStreaming { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch trimmed {
        case translating, learning, proofreading, stopped, emptySelectionGuidance, emptyInputHint, textTooLong,
             setupNeedsAPIKey, setupNeedsAccessibility:
            return false
        default:
            if trimmed.hasPrefix("No text selected.") { return false }
            return resultStyle(for: trimmed) != .error
        }
    }

    static func userFacingError(_ error: Error) -> String {
        if error is CancellationError { return stopped }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled:
                return stopped
            case NSURLErrorTimedOut:
                return "The request timed out. Check your connection and try again."
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "Network error (\(ns.code)). Check your connection and try again."
            default:
                // The bare wording hid which failure it was, which made a one-off host or TLS
                // problem indistinguishable from a real outage.
                return "Network error (\(ns.code)): \(ns.localizedDescription)"
            }
        }
        if ns.domain == "HTTP" {
            return Translator.httpErrorDescription(status: ns.code)
        }
        if let response = error as? Translator.ResponseError {
            switch response {
            case .invalidSchema:
                return "The translation could not be parsed. Try again."
            case .emptyContent:
                return "The translation service returned an empty reply."
            }
        }
        let raw = ns.localizedDescription
        if raw.count > 180 || raw.contains("Bearer ") || raw.contains("sk-") || raw.contains("api_key") {
            return "The translation service returned an error. Try again."
        }
        return raw
    }

    /// Tooltip body for the context indicator: one `source → target` line per reference pair, each
    /// side clipped so a long paragraph can't blow the tooltip up.
    static func contextTooltip(_ pairs: [(source: String, target: String)], sideLimit: Int = 60) -> String? {
        guard !pairs.isEmpty else { return nil }
        let lines = pairs.map { "• \(clip($0.source, sideLimit)) → \(clip($0.target, sideLimit))" }
        return "Context sent with Translate (\(pairs.count)):\n" + lines.joined(separator: "\n")
    }

    private static func clip(_ text: String, _ limit: Int) -> String {
        let flat = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return flat.count <= limit ? flat : String(flat.prefix(limit)) + "…"
    }

    static func accessibilityFallbackNote(source: TranslatableTextSource) -> String {
        let sourceName = source == .simulatedCopy ? "simulated copy" : "clipboard"
        return "Used \(sourceName) (selection read failed)"
    }
}
