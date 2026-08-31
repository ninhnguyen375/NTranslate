import Foundation
import NaturalLanguage

enum LanguageDetector {
    static let autoDetect = "Auto detect"
    static let defaultLanguages = AppConfig.defaultLanguages
    static let defaultTargetLanguages = AppConfig.defaultTargetLanguages

    /// Kept for call sites / tests that don't pass an explicit list.
    static var supportedLanguages: [String] { defaultLanguages }
    static var targetLanguages: [String] { defaultTargetLanguages }

    /// Compact button label: "Auto detect" -> "Auto", "Vietnamese" -> "VI".
    static func shortCode(_ language: String) -> String {
        if language == autoDetect { return "Auto" }
        if let cached = shortCodeCache[language] { return cached }
        let english = Locale(identifier: "en_US")
        let match = Locale.LanguageCode.isoLanguageCodes.first {
            english.localizedString(forLanguageCode: $0.identifier)?
                .caseInsensitiveCompare(language) == .orderedSame
        }
        let code = (match?.identifier ?? String(language.prefix(2))).uppercased()
        shortCodeCache[language] = code
        return code
    }

    private nonisolated(unsafe) static var shortCodeCache: [String: String] = [:]

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

    /// Language of a short selected phrase, independent of the pane's own language. Script
    /// heuristics settle Vietnamese/Chinese; for plain-latin text NLLanguageRecognizer breaks the
    /// English/Vietnamese-without-diacritics tie. Returns nil when the text is too short or the
    /// detected language is not in `candidates`, so callers can keep their pane language.
    static func detectedPhraseLanguage(_ text: String, candidates: [String] = defaultLanguages) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if looksVietnamese(trimmed) { return "Vietnamese" }
        if looksChinese(trimmed) { return "Chinese" }
        // ponytail: single short token is noise for the recognizer; let the pane language win.
        guard trimmed.count >= 4 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(trimmed)
        guard let code = recognizer.dominantLanguage?.rawValue,
              let display = Locale(identifier: "en_US").localizedString(forLanguageCode: code)
        else { return nil }
        return candidates.first { $0 != autoDetect && $0.caseInsensitiveCompare(display) == .orderedSame }
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
    /// When `respectSelectedTarget` is true and `selectedTarget` is a real language (not Auto
    /// or empty), that target is kept even if it equals the detected source.
    static func resolvedPair(
        selectedSource: String,
        selectedTarget: String,
        text: String,
        recentTargets: [String] = [],
        languages: [String] = defaultLanguages,
        targetLanguages: [String] = defaultTargetLanguages,
        nativeLang: String = "Vietnamese",
        respectSelectedTarget: Bool = false
    ) -> (source: String, target: String) {
        let source = normalizeSource(selectedSource, languages: languages)
        var target = normalizeTarget(selectedTarget, targetLanguages: targetLanguages, fallback: nativeLang)
        if source == autoDetect {
            let explicit = selectedTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            let keepSelected = respectSelectedTarget && !explicit.isEmpty && explicit != autoDetect
            if !keepSelected {
                let detected = detectedLanguage(text)
                target = recentTargets.first(where: { $0 != detected && targetLanguages.contains($0) })
                    ?? fallbackTarget(detected: detected, targetLanguages: targetLanguages, nativeLang: nativeLang)
            }
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
