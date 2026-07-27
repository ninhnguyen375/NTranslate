using NTranslate.Core.Configuration;

namespace NTranslate.Core.Prompts;

public enum PromptMode { Translate, Grammar, LearnWord, LearnSentence }

public static class PromptRenderer
{
    public static PromptMode SelectMode(string text, string source, string target, bool learn) =>
        learn ? SelectLearnMode(text) : string.Equals(source, target, StringComparison.OrdinalIgnoreCase) ? PromptMode.Grammar : PromptMode.Translate;

    public static PromptMode SelectLearnMode(string text) =>
        text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length == 1 ? PromptMode.LearnWord : PromptMode.LearnSentence;

    public static string RenderTranslation(AppConfig config) =>
        config.SystemPrompt
            .Replace("{{config.sourceLang}}", config.SourceLang, StringComparison.Ordinal)
            .Replace("{{config.targetLang}}", config.TargetLang, StringComparison.Ordinal);

    public static string RenderGrammar(string language, AppConfig config) =>
        config.GrammarPrompt
            .Replace("{{config.nativeLang}}", config.NativeLang, StringComparison.Ordinal)
            .Replace("{{lang}}", language, StringComparison.Ordinal);

    public static string RenderLearn(string text, AppConfig config) =>
        Render(SelectLearnMode(text) == PromptMode.LearnWord ? config.LearnPrompt : config.SentenceLearnPrompt,
            config.SourceLang, config.TargetLang, config.NativeLang, config.SourceLang);

    private static string Render(string template, string source, string target, string native, string language) =>
        template
            .Replace("{{config.sourceLang}}", source, StringComparison.Ordinal)
            .Replace("{{config.targetLang}}", target, StringComparison.Ordinal)
            .Replace("{{config.nativeLang}}", native, StringComparison.Ordinal)
            .Replace("{{lang}}", language, StringComparison.Ordinal);
}
