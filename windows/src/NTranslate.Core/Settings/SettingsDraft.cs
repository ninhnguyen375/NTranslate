using NTranslate.Core.Configuration;

namespace NTranslate.Core.Settings;

public sealed class SettingsDraft
{
    public string ApiBaseUrl { get; set; } = string.Empty;
    public string? ApiSpeechUrl { get; set; }
    public string ApiKey { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;
    public string SourceLang { get; set; } = string.Empty;
    public string TargetLang { get; set; } = string.Empty;
    public string NativeLang { get; set; } = string.Empty;
    public List<string> Languages { get; private set; } = [];
    public List<string> TargetLanguages { get; private set; } = [];
    public int MaxTranslateLength { get; set; }
    public string SystemPrompt { get; set; } = string.Empty;
    public string LearnPrompt { get; set; } = string.Empty;
    public string SentenceLearnPrompt { get; set; } = string.Empty;
    public string GrammarPrompt { get; set; } = string.Empty;
    public bool AutoPrefetchSpeech { get; set; }
    public string SpeechSourceModel { get; set; } = string.Empty;
    public string SpeechSourceModelVietnamese { get; set; } = string.Empty;
    public string SpeechSourceModelChinese { get; set; } = string.Empty;
    public string SpeechTargetModel { get; set; } = string.Empty;
    public double SpeechRate { get; set; } = 1;
    public string? HistoryDirectory { get; set; }
    public bool StartWithWindows { get; set; }
    public string HotkeyKey { get; set; } = string.Empty;
    public bool HotkeyOption { get; set; }
    public bool HotkeyControl { get; set; }
    public bool HotkeyShift { get; set; }
    public double UiWidth { get; set; }
    public double UiHeight { get; set; }
    public bool UiAutoCopy { get; set; }
    public bool UiSimulateCopy { get; set; }

    public static SettingsDraft From(AppConfig config, string apiKey)
    {
        var draft = new SettingsDraft();
        draft.Revert(config, apiKey);
        return draft;
    }

    public void Revert(AppConfig config, string apiKey)
    {
        ApiBaseUrl = config.ApiBaseUrl;
        ApiSpeechUrl = config.ApiSpeechUrl;
        ApiKey = apiKey;
        Model = config.Model;
        SourceLang = config.SourceLang;
        TargetLang = config.TargetLang;
        NativeLang = config.NativeLang;
        Languages = [.. config.Languages];
        TargetLanguages = [.. config.TargetLanguages];
        MaxTranslateLength = config.MaxTranslateLength;
        SystemPrompt = config.SystemPrompt;
        LearnPrompt = config.LearnPrompt;
        SentenceLearnPrompt = config.SentenceLearnPrompt;
        GrammarPrompt = config.GrammarPrompt;
        AutoPrefetchSpeech = config.AutoPrefetchSpeech;
        SpeechSourceModel = config.SpeechSourceModel;
        SpeechSourceModelVietnamese = config.SpeechSourceModelVietnamese;
        SpeechSourceModelChinese = config.SpeechSourceModelChinese;
        SpeechTargetModel = config.SpeechTargetModel;
        HistoryDirectory = config.HistoryDirectory;
        HotkeyKey = config.Hotkey.Key;
        HotkeyOption = config.Hotkey.Option;
        HotkeyControl = config.Hotkey.Control;
        HotkeyShift = config.Hotkey.Shift;
        UiWidth = config.Ui.Width;
        UiHeight = config.Ui.Height;
        UiAutoCopy = config.Ui.AutoCopy;
        UiSimulateCopy = config.Ui.SimulateCopy;
    }

    public AppConfig ToAppConfig(AppConfig basis) => basis with
    {
        ApiBaseUrl = ApiBaseUrl.Trim(),
        ApiSpeechUrl = string.IsNullOrWhiteSpace(ApiSpeechUrl) ? null : ApiSpeechUrl.Trim(),
        Model = Model.Trim(),
        SourceLang = SourceLang.Trim(),
        TargetLang = TargetLang.Trim(),
        NativeLang = NativeLang.Trim(),
        Languages = Languages.Select(value => value.Trim()).ToArray(),
        TargetLanguages = TargetLanguages.Select(value => value.Trim()).ToArray(),
        MaxTranslateLength = MaxTranslateLength,
        SystemPrompt = SystemPrompt,
        LearnPrompt = LearnPrompt,
        SentenceLearnPrompt = SentenceLearnPrompt,
        GrammarPrompt = GrammarPrompt,
        AutoPrefetchSpeech = AutoPrefetchSpeech,
        SpeechSourceModel = SpeechSourceModel.Trim(),
        SpeechSourceModelVietnamese = SpeechSourceModelVietnamese.Trim(),
        SpeechSourceModelChinese = SpeechSourceModelChinese.Trim(),
        SpeechTargetModel = SpeechTargetModel.Trim(),
        HistoryDirectory = HistoryDirectory?.Trim(),
        Hotkey = new(HotkeyKey.Trim(), HotkeyOption, false, HotkeyControl, HotkeyShift),
        Ui = new(UiWidth, UiHeight, UiAutoCopy, UiSimulateCopy)
    };

    public IReadOnlyList<ConfigValidationIssue> Validate()
    {
        var config = ToAppConfig(AppConfig.Default);
        var issues = config.Validate().ToList();
        AddBlank(SystemPrompt, nameof(SystemPrompt), issues);
        AddBlank(LearnPrompt, nameof(LearnPrompt), issues);
        AddBlank(SentenceLearnPrompt, nameof(SentenceLearnPrompt), issues);
        AddBlank(GrammarPrompt, nameof(GrammarPrompt), issues);
        AddBlank(SpeechSourceModel, nameof(SpeechSourceModel), issues);
        AddBlank(SpeechSourceModelVietnamese, nameof(SpeechSourceModelVietnamese), issues);
        AddBlank(SpeechSourceModelChinese, nameof(SpeechSourceModelChinese), issues);
        AddBlank(SpeechTargetModel, nameof(SpeechTargetModel), issues);
        if (SpeechRate is < 0.5 or > 1.5)
            issues.Add(new(nameof(SpeechRate), "Must be between 0.5 and 1.5."));
        if (!string.IsNullOrWhiteSpace(HistoryDirectory) && !Path.IsPathFullyQualified(HistoryDirectory))
            issues.Add(new(nameof(HistoryDirectory), "Must be an absolute path."));
        return issues;
    }

    private static void AddBlank(string value, string field, List<ConfigValidationIssue> issues)
    {
        if (string.IsNullOrWhiteSpace(value))
            issues.Add(new(field, "Must not be empty."));
    }
}
