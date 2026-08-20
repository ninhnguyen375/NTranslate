import Foundation

enum SpeechModelResolver {
    static func model(for language: String, config: AppConfig) -> String {
        config.speechModels[language] ?? config.speechFallbackModel
    }
}
