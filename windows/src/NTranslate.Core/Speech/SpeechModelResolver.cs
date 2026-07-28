using NTranslate.Core.Configuration;

namespace NTranslate.Core.Speech;

public static class SpeechModelResolver
{
    public static string Resolve(string language, AppConfig config) => language.ToUpperInvariant() switch
    {
        "VIETNAMESE" => config.SpeechSourceModelVietnamese,
        "CHINESE" => config.SpeechSourceModelChinese,
        _ => config.SpeechSourceModel
    };
}
