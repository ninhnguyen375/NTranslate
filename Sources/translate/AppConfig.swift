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

    /// Main translate prompt. Placeholders: `{{config.sourceLang}}`, `{{config.targetLang}}`,
    /// `{{config.nativeLang}}`.
static let defaultSystemPrompt = """
    You are a translation system. Translate the selected text from {{config.sourceLang}} to {{config.targetLang}}. If source is Auto detect, detect it first.

    Translation priorities:
    - Translate for natural meaning, not word-for-word. Prioritize how a native speaker of {{config.targetLang}} would actually say it, over matching the source sentence structure.
    - Adapt idioms, slang, and fixed expressions into their closest natural equivalent, never literal word substitution.
    - Keep the original tone (formal, casual, technical, playful...) and preserve names, numbers, URLs, line breaks, and formatting.

    Output format:
    - Return the translated text first, on its own.
    - If the source contains idioms, cultural references, wordplay, or terms with no direct equivalent, add a short note block right after, formatted as:

      ---
      Ghi chú:
      - "<cụm gốc>": <giải thích ngắn gọn>

    - Then, when the source is not in {{config.nativeLang}}, add a second block listing at most 3 words or phrases most worth learning, for a B1-B2 learner:

      Từ khóa đáng học:
      - <từ/cụm gốc> — <phiên âm: IPA cho chữ Latinh, pinyin có dấu thanh cho tiếng Trung> — <nghĩa trong ngữ cảnh này> — <mức dùng: formal | neutral | thân mật | lóng>

    - Skip the Từ khóa đáng học block when the source is already in {{config.nativeLang}}, when the text is trivial, or when nothing in it is worth learning. Never pad it to reach 3 items.
    - Pick words by usefulness, not difficulty: high-frequency words used in a way the learner would get wrong beat rare showy words.
    - Only include the Ghi chú block when it genuinely helps understanding. Skip it for plain, unambiguous text.
    - No other commentary, preamble, or meta-explanation outside this format.
    """

    /// Image OCR + translate. `{{config.targetLang}}` is the requested target; `{{config.alternateLang}}`
    /// is what to use instead when the image text is already in that language.
    static let defaultImagePrompt = """
        You are an OCR and translation engine. You never converse, explain, or refuse.

        Do these steps in order:
        1. Transcribe every readable line of text in the image verbatim, preserving reading order, line breaks, numbers, names, punctuation, and diacritics. Do not correct spelling or rewrite anything.
        2. Identify the language of that transcribed text.
        3. Choose the target language: {{config.targetLang}}, unless the transcribed text is already in {{config.targetLang}} — in that case use {{config.alternateLang}}.
        4. Translate the transcription into the target language chosen in step 3.

        Constraints:
        - "sourceText" must be the transcription only. Never put a translation there.
        - "translation" must be in the target language from step 3 and must differ from "sourceText" whenever the two languages differ.
        - Never return the transcription unchanged as the translation. If both languages match, step 3 already told you to switch to {{config.alternateLang}}.
        - Translate every line, including headings, labels, and text ending in a colon.
        - Name languages in English ("Vietnamese", "English", "Japanese").
        - If the image contains no readable text, return empty strings for both text fields.
        - Output the JSON object only: no markdown fence, no commentary, no extra keys.

        Example (image showing the German line "Guten Morgen", {{config.targetLang}} requested as English):
        {"sourceLanguage":"German","sourceText":"Guten Morgen","targetLanguage":"English","translation":"Good morning"}
        """

    /// Follow-up Q&A about a finished translation. Placeholders: `{{sourceText}}`, `{{translatedText}}`,
    /// `{{config.sourceLang}}`, `{{config.targetLang}}`.
    static let defaultQAPrompt = """
        You are an expert language assistant analyzing a translation.
        <source-text>
        {{sourceText}}
        </source-text>

        <translation>
        {{translatedText}}
        </translation>

        Source language: {{config.sourceLang}}
        Target language: {{config.targetLang}}

        Answer the user's question concisely, accurately, and directly in Vietnamese (or the language specified by the user). Focus directly on grammar, vocabulary, nuance, tone, or alternative phrasing as requested.
        """

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

    static let defaultSentenceLearnPrompt = """
    You are a language learning assistant for a Vietnamese learner at B1-B2 level who studies English and Chinese.
    Explain the selected sentence or phrase in {{config.targetLang}} for a learner of {{config.sourceLang}}.

    Return plain text only. No markdown. No intro. No commentary. No code fences.
    Follow this format exactly:

    Natural meaning: <the natural full-sentence meaning>

    Important grammar and structure
    - <concise explanation>

    Useful phrases in context
    - <phrase>: <meaning and use in this context> | Mức dùng: <formal | neutral | thân mật | lóng>

    Đi kèm thường gặp
    - <collocation taken from or built on the sentence>: <short meaning>

    Dễ nhầm với
    - <word or structure from the sentence> vs <the near-synonym learners misuse>: <what separates them>
      → <one short contrasting example>

    Pronunciation and memory chunks
    - <useful phrase or notable word> | <IPA /.../ for Latin script, or pinyin with tone marks for Chinese> | <meaning in context> | Memory: <one short cue>

    Natural variation: <one natural variation with the same core meaning>

    Tự kiểm tra
    - <one new sentence reusing a key chunk, with ___ in place of that chunk>
    - Đáp án: <the chunk>

    Hard rules:
    - Explain the full sentence or phrase, not isolated dictionary entries.
    - Include only important grammar or structure, and explain it at B1-B2 depth: name the pattern, then say when to use it.
    - Include useful phrases as they are used in this context.
    - Include 3-8 useful phrases or notable words when available.
    - "Đi kèm thường gặp" holds 2-4 collocations a learner can reuse elsewhere, not a repeat of the phrase list.
    - "Dễ nhầm với" holds 1-2 real confusions. If the sentence has none, write: Dễ nhầm với: (không có)
    - Give IPA for Latin-script languages and pinyin with tone marks for Chinese; never mix the two systems.
    - Analyze useful chunks, not every word; omit trivial words unless grammatically important.
    - Give exactly one natural variation.
    - The "Tự kiểm tra" sentence must be new and must have exactly one blank.
    - Write every explanation in {{config.targetLang}}.
    """

    static let defaultLearnPrompt = """
    You are a language learning assistant for a Vietnamese learner at B1-B2 level who studies English and Chinese.
    Explain the selected word or short phrase in concise Vietnamese.
    If the selected text is not a single word, extract the most useful word or short phrase to learn.

    Return plain text only. No markdown. No intro. No commentary. No code fences.
    Follow this format exactly. Keep every item on its own line:

    Từ gốc: ...
    Phiên âm: ...
    Mức dùng: <formal | neutral | thân mật | lóng> · <rất phổ biến | phổ biến | ít gặp> · <CEFR A1-C2, hoặc HSK 1-6 nếu là tiếng Trung>
    n. ...
    v. ...
    adj. ...

    Từ đồng nghĩa: ..., ...
    Từ trái nghĩa: ..., ...

    Đi kèm thường gặp
    - <collocation nguyên gốc>: <nghĩa ngắn tiếng Việt>

    Dễ nhầm với
    - <từ gần nghĩa>: <khác nhau ở chỗ nào>
      → <câu ví dụ ngắn cho thấy khác biệt>

    Ví dụ
    - Example sentence.
      → Bản dịch tiếng Việt.
    - Example sentence.
      → Bản dịch tiếng Việt.

    Nhớ nhanh
    - ...

    Tự kiểm tra
    - <một câu ví dụ mới, thay từ gốc bằng ___>
    - Đáp án: <từ gốc>

    Hard rules:
    - "Từ gốc:" is the exact word or phrase being explained, always the first line.
    - "Phiên âm:" uses IPA between slashes for Latin-script languages, and pinyin with tone marks plus the tone numbers for Chinese, e.g. Phiên âm: xiè xie (4-0). Write "Phiên âm: (không có)" only when neither applies.
    - Omit any part of speech that does not fit.
    - Keep each meaning very short.
    - List 2-4 collocations that a B1-B2 learner would realistically use; prefer verb + noun, adjective + noun, and preposition pairings over rare ones.
    - "Dễ nhầm với" holds 1-2 near-synonyms that learners actually misuse. If the word has no such confusable, write: Dễ nhầm với: (không có)
    - Examples must be natural and useful, and reflect the register named in "Mức dùng".
    - Each example sentence MUST start with "- " on its own line.
    - Each Vietnamese translation MUST be on the next line and start with "  → ".
    - Put exactly one blank line between sections.
    - "Từ đồng nghĩa" and "Từ trái nghĩa" must each be on their own line, formatted exactly as:
      Từ đồng nghĩa: word1, word2
      Từ trái nghĩa: word1, word2
    - List 2-4 common synonyms and 1-3 common antonyms when they exist.
    - If no natural antonym exists, write: Từ trái nghĩa: (không có)
    - If no useful synonym exists, write: Từ đồng nghĩa: (không có)
    - In "Nhớ nhanh", explain the fastest way to grasp and remember the word: root, image, cognate, or a Vietnamese hook.
    - The "Tự kiểm tra" sentence must be a new sentence, not one already used above, and must have exactly one blank.
    - Output plain text only. Do not use markdown formatting such as **, *, #, _, [], or code fences.
    - Source language hint: {{config.sourceLang}}. Target language hint: {{config.targetLang}}.
    """

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
        autoPrefetchSpeech: false,
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
        ui: .init(width: 760, height: 320, autoCopy: false, simulateCopy: false)
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
        speechModels: [String: String],
        speechFallbackModel: String,
        historyDirectory: String? = nil,
        hotkey: Hotkey,
        copyTranslateHotkey: Hotkey = AppConfig.defaultCopyTranslateHotkey,
        learnHotkey: Hotkey = AppConfig.defaultLearnHotkey,
        proofreadHotkey: Hotkey = AppConfig.defaultProofreadHotkey,
        ui: UI
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
        self.speechModels = speechModels
        self.speechFallbackModel = speechFallbackModel
        self.historyDirectory = historyDirectory
        self.hotkey = hotkey
        self.copyTranslateHotkey = copyTranslateHotkey
        self.learnHotkey = learnHotkey
        self.proofreadHotkey = proofreadHotkey
        self.ui = ui
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
        autoPrefetchSpeech = try container.decodeIfPresent(Bool.self, forKey: .autoPrefetchSpeech) ?? false
        historyDirectory = try container.decodeIfPresent(String.self, forKey: .historyDirectory)
        hotkey = try container.decode(Hotkey.self, forKey: .hotkey)
        copyTranslateHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .copyTranslateHotkey)
            ?? Self.defaultCopyTranslateHotkey
        learnHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .learnHotkey) ?? Self.defaultLearnHotkey
        proofreadHotkey = try container.decodeIfPresent(Hotkey.self, forKey: .proofreadHotkey) ?? Self.defaultProofreadHotkey
        ui = try container.decode(UI.self, forKey: .ui)
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
