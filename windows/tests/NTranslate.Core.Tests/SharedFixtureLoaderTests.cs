namespace NTranslate.Core.Tests;

public sealed class SharedFixtureLoaderTests
{
    [Theory]
    [InlineData("config.schema.json")]
    [InlineData("prompt-vectors.json")]
    [InlineData("language-vectors.json")]
    [InlineData("openai-chat-vectors.json")]
    [InlineData("openai-speech-vectors.json")]
    public void LoadsSecretFreeJson(string name)
    {
        using var document = SharedFixtureLoader.Load(name);
        var json = document.RootElement.GetRawText();
        Assert.DoesNotContain("sk-", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Bearer ", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("\"apiKey\"", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void AutoDetectResolutionPreservesSelectedSource()
    {
        using var document = SharedFixtureLoader.Load("language-vectors.json");
        var vector = document.RootElement.GetProperty("resolution")[0];
        Assert.Equal("Auto detect", vector.GetProperty("expectedSource").GetString());
    }

    [Fact]
    public void TranslationReplacementLeavesNativeLanguagePlaceholder()
    {
        using var document = SharedFixtureLoader.Load("prompt-vectors.json");
        var vector = document.RootElement.GetProperty("replacement")[0];
        Assert.Contains("{{config.nativeLang}}", vector.GetProperty("expected").GetString());
    }

    [Fact]
    public void ConfigSchemaRequiresOnlyFieldsWithoutDecodeDefaults()
    {
        using var document = SharedFixtureLoader.Load("config.schema.json");
        var root = document.RootElement;
        var required = root.GetProperty("required").EnumerateArray().Select(item => item.GetString());
        Assert.Equal(
            ["apiBaseURL", "model", "sourceLang", "targetLang", "systemPrompt", "speechSourceModel", "speechSourceModelVietnamese", "speechSourceModelChinese", "speechTargetModel", "hotkey", "ui"],
            required);
        var requiredUi = root.GetProperty("properties").GetProperty("ui").GetProperty("required")
            .EnumerateArray().Select(item => item.GetString());
        Assert.Equal(["width", "height", "autoCopy"], requiredUi);
    }
}
