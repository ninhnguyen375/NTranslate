import Foundation

enum LanguageDetector {
    static let supportedLanguages = ["Auto detect", "English", "Vietnamese", "Chinese"]

    static func normalizeSource(_ value: String) -> String {
        supportedLanguages.contains(value) ? value : "Auto detect"
    }

    static func normalizeTarget(_ value: String) -> String {
        supportedLanguages.contains(value) && value != "Auto detect" ? value : "Vietnamese"
    }

    static func looksVietnamese(_ text: String) -> Bool {
        let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        return sample.contains(where: { $0.value >= 0x0102 && $0.value <= 0x1EF9 }) || text.localizedCaseInsensitiveContains("đ")
    }

    static func looksChinese(_ text: String) -> Bool {
        let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        return sample.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF })
    }

    static func resolvedPair(selectedSource: String, selectedTarget: String, text: String) -> (source: String, target: String) {
        let source = normalizeSource(selectedSource)
        var target = normalizeTarget(selectedTarget)
        if source == "Vietnamese" {
            target = "English"
        }
        if source == target {
            target = source == "English" ? "Vietnamese" : "English"
        }
        if source == "Auto detect", looksVietnamese(text) {
            target = "English"
        }
        return (source, target)
    }
}
