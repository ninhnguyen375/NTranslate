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
    var speechURL: String
    var apiKey: String
    var model: String
    var sourceLang: String
    var targetLang: String
    var nativeLang: String
    var languages: [String]
    var targetLanguages: [String]
    var maxTranslateLength: Int
    var systemPrompt: String
    var learnPrompt: String
    var grammarPrompt: String
    var speechSourceModel: String
    var speechSourceModelVietnamese: String
    var speechSourceModelChinese: String
    var speechTargetModel: String
    var hotkey: Hotkey
    var ui: UI

    /// Runtime config lives in Application Support. Seeded by `install-app.sh` (not by the app).
    static let configPath =
        NSString(string: "~/Library/Application Support/NTranslate/config.json").expandingTildeInPath

    static let defaultLanguages = ["Auto detect", "English", "Vietnamese", "Chinese"]
    static let defaultTargetLanguages = ["English", "Vietnamese"]

    static let defaultGrammarPrompt = """
    You are a {{lang}} grammar checker for a language learner. The learner's native language is {{config.nativeLang}}.
    Correct grammar, spelling, and word-choice mistakes in the selected text. If it is already correct, return it unchanged with no correction lines below.

    Return plain text only. No markdown. No intro. No commentary. No code fences.
    Follow this format exactly:

    <corrected text, same language, same meaning>
    - Correct: <wrong part> -> <right part> (<giải thích ngắn gọn bằng tiếng Việt>)
    - Correct: <wrong part> -> <right part> (<giải thích ngắn gọn bằng tiếng Việt>)

    Hard rules:
    - First line is always the fully corrected text, nothing else on that line.
    - One "- Correct: ..." line per mistake fixed, in the order they appear. Omit this section entirely if there were no mistakes.
    - Each explanation is short, plain Vietnamese, no jargon.
    - Preserve original meaning, tone, names, numbers, URLs, and line breaks.
    - Output plain text only. Do not use markdown formatting **, *, #, _, [], code fences.

    Good output example:
    My name is Ninh.
    - Correct: are -> is (chia động từ "to be" theo chủ ngữ số ít "my name")
    """

    static let defaultLearnPrompt = """
    You are an English learning assistant for a Vietnamese learner.
    Explain the selected text in concise Vietnamese.
    If the selected text is not a single English word, extract the most useful English word or short phrase to learn.

    Return plain text only. No markdown. No intro. No commentary. No code fences.
    Follow this format exactly. Keep every item on its own line:

    Từ gốc: ...
    IPA: /.../
    n. ...
    v. ...
    adj. ...

    Từ đồng nghĩa: ..., ...
    Từ trái nghĩa: ..., ...

    Ví dụ
    - Example sentence.
      → Bản dịch tiếng Việt.
    - Example sentence.
      → Bản dịch tiếng Việt.

    Nhớ nhanh
    - ...
    - ...
    - ...

    Hard rules:
    - "Từ gốc:" is the exact word or phrase being explained, always the first line.
    - Omit any part of speech that does not fit.
    - Keep each meaning very short.
    - Examples must be natural and useful.
    - Each example sentence MUST start with "- " on its own line.
    - Each Vietnamese translation MUST be on the next line and start with "  → ".
    - Do not put meanings and examples on the same line.
    - Do not merge two examples into one paragraph.
    - Do not put any text after a meaning on the same line.
    - Put exactly one blank line between sections.
    - "Ví dụ" and "Nhớ nhanh" must each be on their own line.
    - "Từ đồng nghĩa" and "Từ trái nghĩa" must each be on their own line, formatted exactly as:
      Từ đồng nghĩa: word1, word2
      Từ trái nghĩa: word1, word2
    - List 2-4 common English synonyms and 1-3 common English antonyms when they exist.
    - If no natural antonym exists, write: Từ trái nghĩa: (không có)
    - If no useful synonym exists, write: Từ đồng nghĩa: (không có)
    - In "Nhớ nhanh", explain the fastest way to grasp and remember the word.
    - Preserve line breaks exactly.
    - Output plain text only. Do not use markdown formatting such as **, *, #, _, [], or code fences.
    - Target learner language: Vietnamese.
    - Source language hint: {{config.sourceLang}}. Target language hint: {{config.targetLang}}.

    Good output example:
    Từ gốc: graphics
    IPA: /ˈɡræfɪks/
    n. đồ họa; hình ảnh máy tính.

    Từ đồng nghĩa: visuals, imagery, illustrations
    Từ trái nghĩa: text, audio

    Ví dụ
    - High-quality graphics make the game look realistic.
      → Đồ họa chất lượng cao làm cho trò chơi trông chân thực.
    - The company specializes in computer graphics.
      → Công ty chuyên về đồ họa máy tính.

    Nhớ nhanh
    - Gốc liên tưởng: graph = vẽ, viết.
    - graphics = phần hình ảnh nhìn thấy trên màn hình.
    - Nhấn âm đầu: GRA-.
    """

    static let `default` = AppConfig(
        apiBaseURL: "http://localhost:20128/v1/chat/completions",
        speechURL: "http://localhost:20128/v1/audio/speech",
        apiKey: "",
        model: "9r-gemini-low",
        sourceLang: "Auto detect",
        targetLang: "Vietnamese",
        nativeLang: "Vietnamese",
        languages: defaultLanguages,
        targetLanguages: defaultTargetLanguages,
        maxTranslateLength: 5000,
        systemPrompt: "You are a translation system. Translate the selected text from {{config.sourceLang}} to {{config.targetLang}}. If source is Auto detect, detect it first. Return only the final replacement text as valid markdown, with no explanations. Preserve meaning, tone, names, numbers, URLs, line breaks, and formatting where possible. Use markdown for emphasis, lists, and structure only when it improves readability and stays faithful to the source. The output will directly replace the user's selected text.",
        learnPrompt: defaultLearnPrompt,
        grammarPrompt: defaultGrammarPrompt,
        speechSourceModel: "edge-tts/en-US-AvaMultilingualNeural",
        speechSourceModelVietnamese: "edge-tts/vi-VN-HoaiMyNeural",
        speechSourceModelChinese: "edge-tts/zh-CN-XiaoxiaoNeural",
        speechTargetModel: "edge-tts/vi-VN-HoaiMyNeural",
        hotkey: .init(key: "D", option: true, command: false, control: false, shift: false),
        ui: .init(width: 630, height: 320, autoCopy: false, simulateCopy: false)
    )

    init(
        apiBaseURL: String,
        speechURL: String,
        apiKey: String,
        model: String,
        sourceLang: String,
        targetLang: String,
        nativeLang: String,
        languages: [String],
        targetLanguages: [String],
        maxTranslateLength: Int,
        systemPrompt: String,
        learnPrompt: String,
        grammarPrompt: String,
        speechSourceModel: String,
        speechSourceModelVietnamese: String,
        speechSourceModelChinese: String,
        speechTargetModel: String,
        hotkey: Hotkey,
        ui: UI
    ) {
        self.apiBaseURL = apiBaseURL
        self.speechURL = speechURL
        self.apiKey = apiKey
        self.model = model
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.nativeLang = nativeLang
        self.languages = languages
        self.targetLanguages = targetLanguages
        self.maxTranslateLength = maxTranslateLength
        self.systemPrompt = systemPrompt
        self.learnPrompt = learnPrompt
        self.grammarPrompt = grammarPrompt
        self.speechSourceModel = speechSourceModel
        self.speechSourceModelVietnamese = speechSourceModelVietnamese
        self.speechSourceModelChinese = speechSourceModelChinese
        self.speechTargetModel = speechTargetModel
        self.hotkey = hotkey
        self.ui = ui
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiBaseURL = try container.decode(String.self, forKey: .apiBaseURL)
        apiKey = try container.decode(String.self, forKey: .apiKey)
        model = try container.decode(String.self, forKey: .model)
        sourceLang = try container.decode(String.self, forKey: .sourceLang)
        targetLang = try container.decode(String.self, forKey: .targetLang)
        nativeLang = try container.decodeIfPresent(String.self, forKey: .nativeLang) ?? "Vietnamese"
        languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? Self.defaultLanguages
        targetLanguages = try container.decodeIfPresent([String].self, forKey: .targetLanguages) ?? Self.defaultTargetLanguages
        maxTranslateLength = try container.decodeIfPresent(Int.self, forKey: .maxTranslateLength) ?? 5000
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        learnPrompt = try container.decodeIfPresent(String.self, forKey: .learnPrompt) ?? Self.defaultLearnPrompt
        grammarPrompt = try container.decodeIfPresent(String.self, forKey: .grammarPrompt) ?? Self.defaultGrammarPrompt
        speechSourceModel = try container.decode(String.self, forKey: .speechSourceModel)
        speechSourceModelVietnamese = try container.decode(String.self, forKey: .speechSourceModelVietnamese)
        speechSourceModelChinese = try container.decode(String.self, forKey: .speechSourceModelChinese)
        speechTargetModel = try container.decode(String.self, forKey: .speechTargetModel)
        hotkey = try container.decode(Hotkey.self, forKey: .hotkey)
        ui = try container.decode(UI.self, forKey: .ui)
        if let explicit = try container.decodeIfPresent(String.self, forKey: .speechURL),
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            speechURL = explicit
        } else {
            speechURL = Self.derivedSpeechURL(from: apiBaseURL)
        }
    }

    static func derivedSpeechURL(from apiBaseURL: String) -> String {
        apiBaseURL.replacingOccurrences(of: "/chat/completions", with: "/audio/speech")
    }

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
        let trimmed = sourceLang.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Auto detect" : trimmed
    }

    var resolvedTargetLang: String {
        let trimmed = targetLang.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nativeLang : trimmed
    }

    var resolvedNativeLang: String {
        let trimmed = nativeLang.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Vietnamese" : trimmed
    }
}
