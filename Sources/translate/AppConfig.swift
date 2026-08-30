import Foundation

struct AppConfig: Codable {
    struct Hotkey: Codable, Equatable {
        var key: String
        var option: Bool
        var command: Bool
        var control: Bool
        var shift: Bool

        static func isSameCombination(_ lhs: Hotkey, _ rhs: Hotkey) -> Bool {
            lhs.key.caseInsensitiveCompare(rhs.key) == .orderedSame
                && lhs.option == rhs.option
                && lhs.command == rhs.command
                && lhs.control == rhs.control
                && lhs.shift == rhs.shift
        }

        /// Compact modifier-symbol form for display in button labels, e.g. "⌥L".
        var displayString: String {
            var symbols = ""
            if control { symbols += "⌃" }
            if option { symbols += "⌥" }
            if shift { symbols += "⇧" }
            if command { symbols += "⌘" }
            return symbols + key.uppercased()
        }
    }

    struct UI: Codable {
        var width: Double
        var height: Double
        var autoCopy: Bool
        var simulateCopy: Bool

        init(
            width: Double,
            height: Double,
            autoCopy: Bool,
            simulateCopy: Bool = false
        ) {
            self.width = width
            self.height = height
            self.autoCopy = autoCopy
            self.simulateCopy = simulateCopy
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = AppConfig.default.ui
            width = try container.decodeIfPresent(Double.self, forKey: .width) ?? defaults.width
            height = try container.decodeIfPresent(Double.self, forKey: .height) ?? defaults.height
            autoCopy = try container.decodeIfPresent(Bool.self, forKey: .autoCopy) ?? defaults.autoCopy
            simulateCopy = try container.decodeIfPresent(Bool.self, forKey: .simulateCopy) ?? defaults.simulateCopy
        }
    }

    struct LearningSettings: Codable {
        var dailyReviewLimit: Int

        init(dailyReviewLimit: Int = 12) {
            self.dailyReviewLimit = max(1, dailyReviewLimit)
        }

        private enum CodingKeys: String, CodingKey {
            case dailyReviewLimit
            case dailyNewWordLimit // legacy key kept so existing config.json values survive
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let stored = try container.decodeIfPresent(Int.self, forKey: .dailyReviewLimit)
                ?? container.decodeIfPresent(Int.self, forKey: .dailyNewWordLimit)
                ?? 12
            dailyReviewLimit = max(1, stored)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(dailyReviewLimit, forKey: .dailyReviewLimit)
        }
    }

    var apiBaseURL: String
    var apiSpeechURL: String
    var model: String
    var sourceLang: String
    var targetLang: String
    var nativeLang: String
    var languages: [String]
    var targetLanguages: [String]
    var maxTranslateLength: Int
    var systemPrompt: String
    var learnPrompt: String
    var sentenceLearnPrompt: String
    var grammarPrompt: String
    var imagePrompt: String
    var qaPrompt: String
    var autoPrefetchSpeech: Bool
    var theme: AppTheme
    /// Speech model per language name, e.g. ["English": "edge-tts/en-US-AvaMultilingualNeural"].
    var speechModels: [String: String]
    /// Used for languages that have no entry in `speechModels`.
    var speechFallbackModel: String
    var historyDirectory: String?
    var hotkey: Hotkey
    var copyTranslateHotkey: Hotkey
    var learnHotkey: Hotkey
    var proofreadHotkey: Hotkey
    var ui: UI
    var learning: LearningSettings

    static let defaultCopyTranslateHotkey = Hotkey(key: "D", option: true, command: false, control: true, shift: false)
    static let defaultLearnHotkey = Hotkey(key: "L", option: true, command: false, control: false, shift: false)
    static let defaultProofreadHotkey = Hotkey(key: "P", option: true, command: false, control: false, shift: false)

    var historyDirectoryURL: URL {
        if let historyDirectory, !historyDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let expanded = NSString(string: historyDirectory).expandingTildeInPath
            return URL(fileURLWithPath: expanded).standardizedFileURL
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NTranslate", isDirectory: true).standardizedFileURL
    }

    /// Runtime config lives in Application Support.
    /// Created automatically on first launch if missing; `install-app.sh` can also seed/overwrite it.
    static let configPath =
        NSString(string: "~/Library/Application Support/NTranslate/config.json").expandingTildeInPath

    static let defaultLanguages = ["Auto detect", "English", "Vietnamese", "Chinese"]
    static let defaultTargetLanguages = ["English", "Vietnamese"]


    static let `default` = AppConfig(
        apiBaseURL: "http://localhost:20128/v1/chat/completions",
        apiSpeechURL: "http://localhost:20128/v1/audio/speech",
        model: "9r-gemini-low",
        sourceLang: "Auto detect",
        targetLang: "Vietnamese",
        nativeLang: "Vietnamese",
        languages: defaultLanguages,
        targetLanguages: defaultTargetLanguages,
        maxTranslateLength: 5000,
        systemPrompt: defaultSystemPrompt,
        learnPrompt: defaultLearnPrompt,
        sentenceLearnPrompt: defaultSentenceLearnPrompt,
        grammarPrompt: defaultGrammarPrompt,
        imagePrompt: defaultImagePrompt,
        qaPrompt: defaultQAPrompt,
        autoPrefetchSpeech: true,
        theme: .system,
        speechModels: [
            "English": "edge-tts/en-US-AvaMultilingualNeural",
            "Vietnamese": "edge-tts/vi-VN-HoaiMyNeural",
            "Chinese": "edge-tts/zh-CN-XiaoxiaoNeural",
        ],
        speechFallbackModel: "edge-tts/en-US-AvaMultilingualNeural",
        hotkey: .init(key: "D", option: true, command: false, control: false, shift: false),
        copyTranslateHotkey: .init(key: "D", option: true, command: false, control: true, shift: false),
        learnHotkey: .init(key: "L", option: true, command: false, control: false, shift: false),
        proofreadHotkey: defaultProofreadHotkey,
        ui: .init(width: 820, height: 320, autoCopy: false, simulateCopy: false),
        learning: LearningSettings()
    )

    init(
        apiBaseURL: String,
        apiSpeechURL: String,
        model: String,
        sourceLang: String,
        targetLang: String,
        nativeLang: String,
        languages: [String],
        targetLanguages: [String],
        maxTranslateLength: Int,
        systemPrompt: String,
        learnPrompt: String,
        sentenceLearnPrompt: String,
        grammarPrompt: String,
        imagePrompt: String = defaultImagePrompt,
        qaPrompt: String = defaultQAPrompt,
        autoPrefetchSpeech: Bool,
        theme: AppTheme = .system,
        speechModels: [String: String],
        speechFallbackModel: String,
        historyDirectory: String? = nil,
        hotkey: Hotkey,
        copyTranslateHotkey: Hotkey = AppConfig.defaultCopyTranslateHotkey,
        learnHotkey: Hotkey = AppConfig.defaultLearnHotkey,
        proofreadHotkey: Hotkey = AppConfig.defaultProofreadHotkey,
        ui: UI,
        learning: LearningSettings = LearningSettings()
    ) {
        self.apiBaseURL = apiBaseURL
        self.apiSpeechURL = apiSpeechURL
        self.model = model
        self.sourceLang = sourceLang
        self.targetLang = targetLang
        self.nativeLang = nativeLang
        self.languages = languages
        self.targetLanguages = targetLanguages
        self.maxTranslateLength = maxTranslateLength
        self.systemPrompt = systemPrompt
        self.learnPrompt = learnPrompt
        self.sentenceLearnPrompt = sentenceLearnPrompt
        self.grammarPrompt = grammarPrompt
        self.imagePrompt = imagePrompt
        self.qaPrompt = qaPrompt
        self.autoPrefetchSpeech = autoPrefetchSpeech
        self.theme = theme
        self.speechModels = speechModels
        self.speechFallbackModel = speechFallbackModel
        self.historyDirectory = historyDirectory
        self.hotkey = hotkey
        self.copyTranslateHotkey = copyTranslateHotkey
        self.learnHotkey = learnHotkey
        self.proofreadHotkey = proofreadHotkey
        self.ui = ui
        self.learning = learning
    }

    private enum LegacySpeechKeys: String, CodingKey {
        case speechURL
        case speechSourceModel
        case speechSourceModelVietnamese
        case speechSourceModelChinese
        case speechTargetModel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        apiBaseURL = try container.decode(String.self, forKey: .apiBaseURL)
        model = try container.decode(String.self, forKey: .model)
        sourceLang = try container.decode(String.self, forKey: .sourceLang)
        targetLang = try container.decode(String.self, forKey: .targetLang)
        nativeLang = try container.decodeIfPresent(String.self, forKey: .nativeLang) ?? "Vietnamese"
        languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? Self.defaultLanguages
        targetLanguages = try container.decodeIfPresent([String].self, forKey: .targetLanguages) ?? Self.defaultTargetLanguages
        maxTranslateLength = try container.decodeIfPresent(Int.self, forKey: .maxTranslateLength) ?? 5000
        systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
        learnPrompt = try container.decodeIfPresent(String.self, forKey: .learnPrompt) ?? Self.defaultLearnPrompt
        sentenceLearnPrompt = try container.decodeIfPresent(String.self, forKey: .sentenceLearnPrompt) ?? Self.defaultSentenceLearnPrompt
        grammarPrompt = try container.decodeIfPresent(String.self, forKey: .grammarPrompt) ?? Self.defaultGrammarPrompt
        imagePrompt = try container.decodeIfPresent(String.self, forKey: .imagePrompt) ?? Self.defaultImagePrompt
        qaPrompt = try container.decodeIfPresent(String.self, forKey: .qaPrompt) ?? Self.defaultQAPrompt
        autoPrefetchSpeech = try container.decodeIfPresent(Bool.self, forKey: .autoPrefetchSpeech) ?? true
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        historyDirectory = try container.decodeIfPresent(String.self, forKey: .historyDirectory)
        hotkey = try container.decode(Hotkey.self, forKey: .hotkey)
        copyTranslateHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .copyTranslateHotkey)
            ?? Self.defaultCopyTranslateHotkey
        learnHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .learnHotkey) ?? Self.defaultLearnHotkey
        proofreadHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .proofreadHotkey) ?? Self.defaultProofreadHotkey
        ui = try container.decodeIfPresent(UI.self, forKey: .ui) ?? Self.default.ui
        learning = try container.decodeIfPresent(LearningSettings.self, forKey: .learning) ?? LearningSettings()
        let legacy = try decoder.container(keyedBy: LegacySpeechKeys.self)
        // Pre-1.3 configs stored speech models per role; map them onto the per-language dictionary.
        let legacySource = try legacy.decodeIfPresent(String.self, forKey: .speechSourceModel)
        if let models = try container.decodeIfPresent([String: String].self, forKey: .speechModels), !models.isEmpty {
            speechModels = models
            speechFallbackModel = try container.decodeIfPresent(String.self, forKey: .speechFallbackModel)
                ?? legacySource
                ?? Self.default.speechFallbackModel
        } else {
            var migrated: [String: String] = [:]
            migrated["English"] = legacySource
            migrated["Vietnamese"] = try legacy.decodeIfPresent(String.self, forKey: .speechTargetModel)
            migrated["Chinese"] = try legacy.decodeIfPresent(String.self, forKey: .speechSourceModelChinese)
            speechModels = migrated.isEmpty ? Self.default.speechModels : migrated
            speechFallbackModel = try container.decodeIfPresent(String.self, forKey: .speechFallbackModel)
                ?? legacySource
                ?? Self.default.speechFallbackModel
        }
        if let explicit = try container.decodeIfPresent(String.self, forKey: .apiSpeechURL),
           !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            apiSpeechURL = explicit
        } else if let legacyURL = try legacy.decodeIfPresent(String.self, forKey: .speechURL),
                  !legacyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            apiSpeechURL = legacyURL
        } else {
            apiSpeechURL = Self.derivedSpeechURL(from: apiBaseURL)
        }
    }

    static func derivedSpeechURL(from apiBaseURL: String) -> String {
        apiBaseURL.replacingOccurrences(of: "/chat/completions", with: "/audio/speech")
    }

    enum LoadOutcome {
        case loaded(AppConfig)
        case seeded(AppConfig)
        case missingFile(AppConfig)
        case failed(AppConfig, String)

        var config: AppConfig {
            switch self {
            case let .loaded(config), let .seeded(config), let .missingFile(config), let .failed(config, _):
                config
            }
        }

        var message: String? {
            switch self {
            case .loaded, .seeded, .missingFile:
                return nil
            case let .failed(_, message):
                return message
            }
        }

        var didSeedConfig: Bool {
            if case .seeded = self { return true }
            return false
        }
    }

    enum SeedResult: Equatable {
        case alreadyExists
        case created
        case failed(String)
    }

    static func encodePrettyJSON(_ config: AppConfig = .default) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(config)
    }

    static func write(
        _ config: AppConfig,
        at path: String = configPath,
        fileManager: FileManager = .default
    ) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try encodePrettyJSON(config).write(to: URL(fileURLWithPath: path), options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    @discardableResult
    static func migrateLegacyAPIKey(
        at path: String = configPath,
        fileManager: FileManager = .default,
        keyStore: APIKeyStore = .shared
    ) throws -> Bool {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return false
        }

        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object.keys.contains("apiKey")
        else { return false }

        let legacyKey = (object["apiKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if try keyStore.load() == nil, !legacyKey.isEmpty {
            try keyStore.save(legacyKey)
        }

        object.removeValue(forKey: "apiKey")
        let sanitized = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try sanitized.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        return true
    }

    /// Creates `~/Library/Application Support/NTranslate/config.json` when missing.
    static func seedConfigFileIfMissing(
        at path: String = configPath,
        fileManager: FileManager = .default,
        config: AppConfig = .default
    ) -> SeedResult {
        if fileManager.fileExists(atPath: path) {
            return .alreadyExists
        }
        do {
            let directory = (path as NSString).deletingLastPathComponent
            try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try write(config, at: path, fileManager: fileManager)
            return .created
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func decodeOutcome(data: Data) -> LoadOutcome {
        do {
            return .loaded(try JSONDecoder().decode(AppConfig.self, from: data))
        } catch {
            return .failed(.default, error.localizedDescription)
        }
    }

    static func loadOutcome(at path: String = configPath, fileManager: FileManager = .default) -> LoadOutcome {
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let outcome = decodeOutcome(data: data)
            if case let .loaded(config) = outcome {
                // If historyDirectory key is missing in config file, backfill it with default ""
                if let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   jsonObject["historyDirectory"] == nil {
                    var updatedConfig = config
                    updatedConfig.historyDirectory = config.historyDirectory ?? ""
                    try? write(updatedConfig, at: path, fileManager: fileManager)
                    return .loaded(updatedConfig)
                }
            }
            return outcome
        } catch CocoaError.fileReadNoSuchFile {
            switch seedConfigFileIfMissing(at: path, fileManager: fileManager) {
            case .alreadyExists:
                do {
                    return decodeOutcome(data: try Data(contentsOf: URL(fileURLWithPath: path)))
                } catch {
                    return .failed(.default, error.localizedDescription)
                }
            case .created:
                do {
                    let seeded = decodeOutcome(data: try Data(contentsOf: URL(fileURLWithPath: path)))
                    if case let .loaded(config) = seeded {
                        return .seeded(config)
                    }
                    return seeded
                } catch {
                    return .failed(.default, "Created config at \(path) but could not read it: \(error.localizedDescription)")
                }
            case let .failed(message):
                return .failed(
                    .default,
                    "Missing config and could not create \(path): \(message)"
                )
            }
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

    func validationIssues() -> [String] {
        var issues: [String] = []
        for (name, value) in [("API base URL", apiBaseURL), ("Speech URL", apiSpeechURL)] {
            guard let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil
            else {
                issues.append("\(name) must be a valid http:// or https:// URL.")
                continue
            }
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("Model cannot be empty.")
        }
        if languages.isEmpty { issues.append("Languages cannot be empty.") }
        if targetLanguages.isEmpty { issues.append("Target languages cannot be empty.") }
        if Set(languages).count != languages.count { issues.append("Languages contain duplicates.") }
        if Set(targetLanguages).count != targetLanguages.count { issues.append("Target languages contain duplicates.") }
        if !languages.contains(sourceLang) { issues.append("Source language must exist in Languages.") }
        if !targetLanguages.contains(targetLang) { issues.append("Target language must exist in Target Languages.") }
        if maxTranslateLength <= 0 { issues.append("Maximum translation length must be greater than zero.") }
        if ui.width <= 0 || ui.height <= 0 { issues.append("Panel width and height must be greater than zero.") }
        if learning.dailyReviewLimit < 1 { issues.append("Daily reviews must be at least 1.") }
        let named: [(String, Hotkey)] = [
            ("Global hotkey", hotkey),
            ("Copy & Translate hotkey", copyTranslateHotkey),
            ("Learn hotkey", learnHotkey),
            ("Proofread hotkey", proofreadHotkey),
        ]
        for (name, entry) in named {
            let key = entry.key.uppercased()
            if key.count != 1 || !key.unicodeScalars.allSatisfy({ (65...90).contains(Int($0.value)) }) {
                issues.append("\(name) must be one letter from A to Z.")
            }
            if !entry.option && !entry.command && !entry.control && !entry.shift {
                issues.append("\(name) requires at least one modifier.")
            }
        }
        for (index, lhs) in named.enumerated() {
            for rhs in named.dropFirst(index + 1) where Hotkey.isSameCombination(lhs.1, rhs.1) {
                issues.append("\(lhs.0) and \(rhs.0) use the same key combination.")
            }
        }
        return issues
    }

    /// User-facing setup problems that block translation (empty key, bad URLs, missing Accessibility).
    func setupIssues(apiKey: String, loadMessage: String? = nil, accessibilityTrusted: Bool) -> [String] {
        var issues: [String] = []
        if let loadMessage {
            let trimmed = loadMessage.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                issues.append(trimmed)
            }
        }
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("API key is empty. Menu → Settings…, enter your 9router API key, then Save.")
        }
        if apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || URL(string: apiBaseURL) == nil {
            issues.append("apiBaseURL is invalid: \(apiBaseURL)")
        }
        if apiSpeechURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || URL(string: apiSpeechURL) == nil {
            issues.append("apiSpeechURL is invalid: \(apiSpeechURL)")
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append("model is empty.")
        }
        if !accessibilityTrusted {
            issues.append("Accessibility permission is missing. Menu → Grant Accessibility Access (needed to read selected text).")
        }
        return issues
    }

    static func formatSetupIssues(_ issues: [String]) -> String {
        issues.map { issue in
            let trimmed = issue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("Error:") { return trimmed }
            return "Error: \(trimmed)"
        }.joined(separator: "\n\n")
    }
}
