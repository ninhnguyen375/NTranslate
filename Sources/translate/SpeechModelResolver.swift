import Foundation

enum SpeechModelResolver {
    static func model(for language: String, config: AppConfig) -> String {
        switch config.speechProvider {
        case .native:
            // Never falls back to the speech API: the user picked native to stay offline, and a
            // silent network call would also target a URL that Settings hides under this
            // provider. A missing voice surfaces as a "no voice installed" error instead.
            return NativeSpeechEngine.model(for: language)
        case .api:
            return config.speechModels[language] ?? config.speechFallbackModel
        }
    }
}
