import Foundation

enum LanguageDetector {
    static let supportedLanguages = ["Auto detect", "English", "Vietnamese", "Chinese"]

    static func normalizeSource(_ value: String) -> String {
        supportedLanguages.contains(value) ? value : "Auto detect"
    }

    static let targetLanguages = supportedLanguages.filter { $0 != "Auto detect" && $0 != "Chinese" }

    static func normalizeTarget(_ value: String) -> String {
        targetLanguages.contains(value) ? value : "Vietnamese"
    }

    static func looksVietnamese(_ text: String) -> Bool {
        let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        return sample.contains(where: { ($0.value >= 0x00C0 && $0.value <= 0x00FF) || ($0.value >= 0x0102 && $0.value <= 0x1EF9) })
            || text.localizedCaseInsensitiveContains("đ")
    }

    static func looksChinese(_ text: String) -> Bool {
        let sample = text.unicodeScalars.filter { !$0.properties.isWhitespace }
        return sample.contains(where: { $0.value >= 0x4E00 && $0.value <= 0x9FFF })
    }

    static func detectedLanguage(_ text: String) -> String {
        if looksVietnamese(text) { return "Vietnamese" }
        if looksChinese(text) { return "Chinese" }
        return "English"
    }

    /// `recentTargets` is ordered most-recently-used first. On auto detect, we pick the most
    /// recently used target language that differs from the detected source, falling back to
    /// the Vietnamese/English default when nothing in the history qualifies.
    static func resolvedPair(selectedSource: String, selectedTarget: String, text: String, recentTargets: [String] = []) -> (source: String, target: String) {
        let source = normalizeSource(selectedSource)
        var target = normalizeTarget(selectedTarget)
        if source == "Vietnamese" {
            target = "English"
        } else if source == "Auto detect" {
            let detected = detectedLanguage(text)
            target = recentTargets.first(where: { $0 != detected && targetLanguages.contains($0) })
                ?? (detected == "Vietnamese" ? "English" : "Vietnamese")
        }
        if source == target {
            target = source == "English" ? "Vietnamese" : "English"
        }
        return (source, target)
    }
}
