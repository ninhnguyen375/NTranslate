using System.Text;
using NTranslate.Core.Configuration;

namespace NTranslate.Core.Languages;

public sealed record LanguagePair(string SourceLang, string TargetLang);

public static class LanguagePolicy
{
    private const string AutoDetect = "Auto detect";
    private const string VietnameseDiacritics = "đ̛̣̀́̂̃̆̉";

    public static string Detect(string text)
    {
        var normalized = text.Normalize(NormalizationForm.FormD);
        if (normalized.Any(character => VietnameseDiacritics.Contains(char.ToLowerInvariant(character))))
            return "Vietnamese";
        if (text.Any(character => character is >= '一' and <= '鿿'))
            return "Chinese";
        return "English";
    }

    public static LanguagePair ResolvePair(string text, AppConfig config, IReadOnlyList<string> recentTargets)
    {
        if (!string.Equals(config.SourceLang, AutoDetect, StringComparison.OrdinalIgnoreCase))
            return new(config.SourceLang, config.TargetLang);

        var detectedSource = Detect(text);
        var target = FirstDifferent(recentTargets.Where(recent => config.TargetLanguages.Contains(recent, StringComparer.OrdinalIgnoreCase)), detectedSource)
            ?? Different(config.TargetLang, detectedSource)
            ?? Different(config.NativeLang, detectedSource)
            ?? FirstDifferent(config.TargetLanguages, detectedSource)
            ?? config.TargetLanguages.FirstOrDefault()
            ?? config.TargetLang;
        return new(config.SourceLang, target);
    }

    public static LanguagePair SwapPair(LanguagePair pair) => new(pair.TargetLang, pair.SourceLang);

    private static string? FirstDifferent(IEnumerable<string> languages, string source) =>
        languages.FirstOrDefault(language => Different(language, source) is not null);

    private static string? Different(string language, string source) =>
        string.Equals(language, source, StringComparison.OrdinalIgnoreCase) ? null : language;
}
