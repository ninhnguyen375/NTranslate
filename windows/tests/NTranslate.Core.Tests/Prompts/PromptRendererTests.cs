using NTranslate.Core.Configuration;
using NTranslate.Core.Prompts;

namespace NTranslate.Core.Tests.Prompts;

public sealed class PromptRendererTests
{
    [Fact]
    public void SelectsModesFromSharedVectors()
    {
        using var vectors = SharedFixtureLoader.Load("prompt-vectors.json");

        foreach (var vector in vectors.RootElement.GetProperty("mode").EnumerateArray())
            Assert.Equal(
                Enum.Parse<PromptMode>(vector.GetProperty("expected").GetString()!),
                PromptRenderer.SelectMode(
                    vector.GetProperty("text").GetString()!,
                    vector.GetProperty("sourceLang").GetString()!,
                    vector.GetProperty("targetLang").GetString()!,
                    vector.GetProperty("learn").GetBoolean()));
    }

    [Fact]
    public void RendersSharedReplacementVectors()
    {
        using var vectors = SharedFixtureLoader.Load("prompt-vectors.json");

        foreach (var vector in vectors.RootElement.GetProperty("replacement").EnumerateArray())
        {
            var config = AppConfig.Default with
            {
                SourceLang = vector.GetProperty("sourceLang").GetString()!,
                TargetLang = vector.GetProperty("targetLang").GetString()!,
                NativeLang = vector.GetProperty("nativeLang").GetString()!,
                SystemPrompt = vector.GetProperty("template").GetString()!,
                GrammarPrompt = vector.GetProperty("template").GetString()!
            };
            var lang = vector.GetProperty("lang").GetString()!;
            var actual = vector.GetProperty("name").GetString() == "grammar language placeholder"
                ? PromptRenderer.RenderGrammar(lang, config)
                : PromptRenderer.RenderTranslation(config);

            Assert.Equal(vector.GetProperty("expected").GetString(), actual);
        }
    }

    [Fact]
    public void RendersWordAndSentenceLearnTemplatesWithoutReplacingNativeOrLanguagePlaceholders()
    {
        var config = AppConfig.Default with
        {
            SourceLang = "English",
            TargetLang = "Vietnamese",
            LearnPrompt = "word {{config.sourceLang}} {{config.targetLang}} {{config.nativeLang}} {{lang}}",
            SentenceLearnPrompt = "sentence {{config.sourceLang}} {{config.targetLang}} {{config.nativeLang}} {{lang}}"
        };

        Assert.Equal("word English Vietnamese {{config.nativeLang}} {{lang}}", PromptRenderer.RenderLearn("word", config));
        Assert.Equal("sentence English Vietnamese {{config.nativeLang}} {{lang}}", PromptRenderer.RenderLearn("two words", config));
    }
}
