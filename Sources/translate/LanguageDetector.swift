import Foundation

enum LanguageDetector {
    static let autoDetect = "Auto detect"
    static let defaultLanguages = AppConfig.defaultLanguages
    static let defaultTargetLanguages = AppConfig.defaultTargetLanguages

    /// Kept for call sites / tests that don't pass an explicit list.
    static var supportedLanguages: [String] { defaultLanguages }
    static var targetLanguages: [String] { defaultTargetLanguages }

    static func normalizeSource(_ value: String, languages: [String] = defaultLanguages) -> String {
        if languages.contains(value) { return value }
        if languages.contains(autoDetect) { return autoDetect }
        return languages.first ?? autoDetect
    }

    static func normalizeTarget(
        _ value: String,
        targetLanguages: [String] = defaultTargetLanguages,
        fallback: String = "Vietnamese"
    ) -> String {
        if targetLanguages.contains(value) { return value }
        if targetLanguages.contains(fallback) { return fallback }
        return targetLanguages.first ?? fallback
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

    static func canonicalLanguage(_ candidate: String, supportedLanguages: [String]) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return supportedLanguages.first {
            $0 != autoDetect && $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    /// `recentTargets` is ordered most-recently-used first. On auto detect, we pick the most
    /// recently used target language that differs from the detected source, falling back to
    /// the configured native/other default when nothing in the history qualifies.
    /// When the user explicitly picks the same source and target language (only possible via
    /// manual selection, not auto-detect), that's honored as-is — it triggers grammar-check mode
    /// instead of translation (see `Translator`).
    static func resolvedPair(
        selectedSource: String,
        selectedTarget: String,
        text: String,
        recentTargets: [String] = [],
        languages: [String] = defaultLanguages,
        targetLanguages: [String] = defaultTargetLanguages,
        nativeLang: String = "Vietnamese"
    ) -> (source: String, target: String) {
        let source = normalizeSource(selectedSource, languages: languages)
        var target = normalizeTarget(selectedTarget, targetLanguages: targetLanguages, fallback: nativeLang)
        if source == autoDetect {
            let detected = detectedLanguage(text)
            target = recentTargets.first(where: { $0 != detected && targetLanguages.contains($0) })
                ?? fallbackTarget(detected: detected, targetLanguages: targetLanguages, nativeLang: nativeLang)
        }
        return (source, target)
    }

    static func swappedPair(
        selectedSource: String,
        selectedTarget: String,
        text: String,
        languages: [String] = defaultLanguages,
        targetLanguages: [String] = defaultTargetLanguages,
        nativeLang: String = "Vietnamese"
    ) -> (source: String, target: String) {
        let source = normalizeSource(selectedSource, languages: languages)
        let target = normalizeTarget(selectedTarget, targetLanguages: targetLanguages, fallback: nativeLang)
        let newSource = normalizeSource(target, languages: languages)
        let newTarget = source == autoDetect
            ? detectedLanguage(text)
            : normalizeTarget(source, targetLanguages: targetLanguages, fallback: nativeLang)
        return (newSource, newTarget)
    }

    static func fallbackTarget(detected: String, targetLanguages: [String], nativeLang: String) -> String {
        if detected == nativeLang {
            return targetLanguages.first { $0 != nativeLang } ?? "English"
        }
        if targetLanguages.contains(nativeLang) { return nativeLang }
        return targetLanguages.first ?? nativeLang
    }
}
