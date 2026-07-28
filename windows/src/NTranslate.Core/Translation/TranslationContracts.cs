namespace NTranslate.Core.Translation;

public enum TranslationMode
{
    Translate,
    Learn,
    ImageTranslate,
    ImageSearch
}

public sealed record TextTranslationRequest(
    string Text,
    string SourceLanguage,
    string TargetLanguage,
    TranslationMode Mode);

public sealed record ImageTranslationRequest(ReadOnlyMemory<byte> PngData, string TargetLanguage);

public sealed record TranslationResult(string Text);
