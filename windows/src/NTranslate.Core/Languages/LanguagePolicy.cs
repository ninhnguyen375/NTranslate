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
        foreach (var character in text.Normalize(NormalizationForm.FormD))
        {
            if (character is >= '一' and <= '鿿')
                return "Chinese";
            if (VietnameseDiacritics.Contains(char.ToLowerInvariant(character)))
                return "Vietnamese";
        }

        return "English";
    }

    public static LanguagePair ResolvePair(string text, AppConfig config, IReadOnlyList<string> recentTargets)
    {
        if (!string.Equals(config.SourceLang, AutoDetect, StringComparison.OrdinalIgnoreCase))
            return new(config.SourceLang, config.TargetLang);

        var detectedSource = Detect(text);
        var target = FirstDifferent(recentTargets, detectedSource)
            ?? Different(config.TargetLang, detectedSource)
            ?? Different(config.NativeLang, detectedSource)
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
