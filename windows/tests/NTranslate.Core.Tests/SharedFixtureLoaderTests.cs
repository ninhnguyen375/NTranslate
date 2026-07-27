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
}
