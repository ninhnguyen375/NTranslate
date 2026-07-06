import Foundation

struct AppConfig: Codable {
    struct Hotkey: Codable {
        var key: String
        var option: Bool
        var command: Bool
        var control: Bool
        var shift: Bool
    }

    struct UI: Codable {
        var width: Double
        var height: Double
        var autoCopy: Bool
        var simulateCopy: Bool

        init(width: Double, height: Double, autoCopy: Bool, simulateCopy: Bool = false) {
            self.width = width
            self.height = height
            self.autoCopy = autoCopy
            self.simulateCopy = simulateCopy
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            width = try container.decode(Double.self, forKey: .width)
            height = try container.decode(Double.self, forKey: .height)
            autoCopy = try container.decode(Bool.self, forKey: .autoCopy)
            simulateCopy = try container.decodeIfPresent(Bool.self, forKey: .simulateCopy) ?? false
        }
    }

    var apiBaseURL: String
    var apiKey: String
    var model: String
    var sourceLang: String
    var targetLang: String
    var systemPrompt: String
    var speechSourceModel: String
    var speechSourceModelVietnamese: String
    var speechSourceModelChinese: String
    var speechTargetModel: String
    var hotkey: Hotkey
    var ui: UI

    static let configPath = NSString(string: "~/Code/MacOS/translate/config.json").expandingTildeInPath

    static let `default` = AppConfig(
        apiBaseURL: "http://localhost:20128/v1/chat/completions",
        apiKey: "",
        model: "9r-gemini-low",
        sourceLang: "Auto detect",
        targetLang: "Vietnamese",
        systemPrompt: "You are a translation system. Translate the selected text from {{config.sourceLang}} to {{config.targetLang}}. If source is Auto detect, detect it first. Return only the final replacement text as valid markdown, with no explanations. Preserve meaning, tone, names, numbers, URLs, line breaks, and formatting where possible. Use markdown for emphasis, lists, and structure only when it improves readability and stays faithful to the source. The output will directly replace the user's selected text.",
        speechSourceModel: "edge-tts/en-US-AvaMultilingualNeural",
        speechSourceModelVietnamese: "edge-tts/vi-VN-HoaiMyNeural",
        speechSourceModelChinese: "edge-tts/zh-CN-XiaoxiaoNeural",
        speechTargetModel: "edge-tts/vi-VN-HoaiMyNeural",
        hotkey: .init(key: "D", option: true, command: false, control: false, shift: false),
        ui: .init(width: 480, height: 320, autoCopy: false, simulateCopy: false)
    )

    enum LoadOutcome {
        case loaded(AppConfig)
        case missingFile(AppConfig)
        case failed(AppConfig, String)

        var config: AppConfig {
            switch self {
            case let .loaded(config), let .missingFile(config), let .failed(config, _): config
            }
        }

        var message: String? {
            switch self {
            case .loaded, .missingFile:
                return nil
            case let .failed(_, message):
                return message
            }
        }
    }

    static func decodeOutcome(data: Data) -> LoadOutcome {
        do {
            return .loaded(try JSONDecoder().decode(AppConfig.self, from: data))
        } catch {
            return .failed(.default, error.localizedDescription)
        }
    }

    static func loadOutcome() -> LoadOutcome {
        do {
            return decodeOutcome(data: try Data(contentsOf: URL(fileURLWithPath: configPath)))
        } catch CocoaError.fileReadNoSuchFile {
            return .missingFile(.default)
        } catch {
            return .failed(.default, error.localizedDescription)
        }
    }

    static func load() -> AppConfig {
        loadOutcome().config
    }

    var resolvedSourceLang: String {
        sourceLang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Auto detect" : sourceLang
    }

    var resolvedTargetLang: String {
        targetLang.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Vietnamese" : targetLang
    }

    var speechURL: String {
        apiBaseURL.replacingOccurrences(of: "/chat/completions", with: "/audio/speech")
    }
}
