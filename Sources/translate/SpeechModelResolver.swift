import Foundation

enum SpeechModelResolver {
    static func model(for language: String, config: AppConfig) -> String {
        switch language {
        case "Vietnamese":
            return config.speechTargetModel
        case "Chinese":
            return config.speechSourceModelChinese
        default:
            return config.speechSourceModel
        }
    }
}
