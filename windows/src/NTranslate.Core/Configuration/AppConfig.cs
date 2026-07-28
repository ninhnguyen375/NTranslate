namespace NTranslate.Core.Configuration;

public sealed record HotkeyConfig(string Key, bool Option, bool Command, bool Control, bool Shift);

public sealed record UiConfig(double Width, double Height, bool AutoCopy, bool SimulateCopy);

public sealed record AppConfig(
    string ApiBaseUrl,
    string? ApiSpeechUrl,
    string Model,
    string SourceLang,
    string TargetLang,
    string NativeLang,
    IReadOnlyList<string> Languages,
    IReadOnlyList<string> TargetLanguages,
    int MaxTranslateLength,
    string SystemPrompt,
    string LearnPrompt,
    string SentenceLearnPrompt,
    string GrammarPrompt,
    bool AutoPrefetchSpeech,
    string SpeechSourceModel,
    string SpeechSourceModelVietnamese,
    string SpeechSourceModelChinese,
    string SpeechTargetModel,
    string? HistoryDirectory,
    HotkeyConfig Hotkey,
    UiConfig Ui)
{
    public static AppConfig Default { get; } = ConfigJson.LoadDefault();

    public IReadOnlyList<ConfigValidationIssue> Validate()
    {
        List<ConfigValidationIssue> issues = [];
        ValidateEndpoint(ApiBaseUrl, nameof(ApiBaseUrl), issues);
        ValidateEndpoint(ApiSpeechUrl, nameof(ApiSpeechUrl), issues);
        AddBlank(Model, nameof(Model), issues);
        if (MaxTranslateLength < 1)
            issues.Add(new(nameof(MaxTranslateLength), "Must be greater than zero."));
        if (HasDuplicates(Languages))
            issues.Add(new(nameof(Languages), "Must not contain duplicates."));
        if (HasDuplicates(TargetLanguages))
            issues.Add(new(nameof(TargetLanguages), "Must not contain duplicates."));
        if (!Contains(Languages, SourceLang))
            issues.Add(new(nameof(SourceLang), "Must be present in Languages."));
        if (!Contains(TargetLanguages, TargetLang))
            issues.Add(new(nameof(TargetLang), "Must be present in TargetLanguages."));
        if (!Contains(Languages, NativeLang))
            issues.Add(new(nameof(NativeLang), "Must be present in Languages."));
        if (string.IsNullOrWhiteSpace(Hotkey.Key) || Hotkey.Key.Length != 1 || !char.IsAsciiLetter(Hotkey.Key[0]))
            issues.Add(new("Hotkey.Key", "Must be one ASCII letter A-Z."));
        if (Hotkey.Command)
            issues.Add(new("Hotkey.Command", "Command is not supported on Windows."));
        if (!(Hotkey.Option || Hotkey.Command || Hotkey.Control || Hotkey.Shift))
            issues.Add(new("Hotkey.Modifiers", "At least one modifier is required."));
        if (Ui.Width <= 0)
            issues.Add(new("Ui.Width", "Must be greater than zero."));
        if (Ui.Height <= 0)
            issues.Add(new("Ui.Height", "Must be greater than zero."));
        return issues;
    }

    internal AppConfig WithDerivedSpeechUrl() =>
        string.IsNullOrWhiteSpace(ApiSpeechUrl) ? this with { ApiSpeechUrl = DeriveSpeechUrl(ApiBaseUrl) } : this;

    private static string? DeriveSpeechUrl(string apiBaseUrl)
    {
        const string chatSuffix = "/chat/completions";
        return Uri.TryCreate(apiBaseUrl, UriKind.Absolute, out var uri) &&
               (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps) &&
               uri.AbsolutePath.EndsWith(chatSuffix, StringComparison.OrdinalIgnoreCase)
            ? new UriBuilder(uri) { Path = uri.AbsolutePath[..^chatSuffix.Length] + "/audio/speech" }.Uri.AbsoluteUri
            : null;
    }

    private static void ValidateEndpoint(string? value, string field, List<ConfigValidationIssue> issues)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttps && !(uri.Scheme == Uri.UriSchemeHttp && uri.IsLoopback)))
            issues.Add(new(field, "Must use HTTPS, except for HTTP loopback URLs."));
    }

    private static void AddBlank(string value, string field, List<ConfigValidationIssue> issues)
    {
        if (string.IsNullOrWhiteSpace(value))
            issues.Add(new(field, "Must not be empty."));
    }

    private static bool HasDuplicates(IReadOnlyList<string> values) =>
        values.Distinct(StringComparer.OrdinalIgnoreCase).Count() != values.Count;

    private static bool Contains(IReadOnlyList<string> values, string value) =>
        values.Contains(value, StringComparer.OrdinalIgnoreCase);
}
