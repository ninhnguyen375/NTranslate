using NTranslate.Core.Configuration;
using NTranslate.Core.Languages;

namespace NTranslate.Core.Tests.Languages;

public sealed class LanguagePolicyTests
{
    [Fact]
    public void DetectsSharedLanguageVectors()
    {
        using var vectors = SharedFixtureLoader.Load("language-vectors.json");

        foreach (var vector in vectors.RootElement.GetProperty("detection").EnumerateArray())
            Assert.Equal(vector.GetProperty("expected").GetString(), LanguagePolicy.Detect(vector.GetProperty("text").GetString()!));
    }

    [Fact]
    public void DetectsVietnameseAcrossWholeMixedLanguageTextBeforeChinese()
    {
        Assert.Equal("Vietnamese", LanguagePolicy.Detect("你好 xin chào"));
    }

    [Fact]
    public void ResolvesAutoSourceUsingOnlySupportedRecentTargetDifferentFromDetectedSource()
    {
        var config = AppConfig.Default with
        {
            SourceLang = "Auto detect",
            TargetLang = "English",
            NativeLang = "Vietnamese",
            TargetLanguages = ["English", "Vietnamese"]
        };

        var pair = LanguagePolicy.ResolvePair("hello", config, ["Chinese", "English", "Vietnamese"]);

        Assert.Equal(new LanguagePair("Auto detect", "Vietnamese"), pair);
    }

    [Fact]
    public void PrefersConfiguredTargetWhenNoRecentTargetIsUsable()
    {
        var config = AppConfig.Default with
        {
            SourceLang = "Auto detect",
            TargetLang = "Chinese",
            NativeLang = "Vietnamese",
            TargetLanguages = ["English", "Vietnamese", "Chinese"]
        };

        var pair = LanguagePolicy.ResolvePair("hello", config, ["English"]);

        Assert.Equal(new LanguagePair("Auto detect", "Chinese"), pair);
    }

    [Fact]
    public void FallsBackToNativeThenFirstTargetDifferentFromDetectedSource()
    {
        var nativeConfig = AppConfig.Default with
        {
            SourceLang = "Auto detect",
            TargetLang = "English",
            NativeLang = "Vietnamese",
            TargetLanguages = ["English", "Vietnamese"]
        };
        var firstConfig = nativeConfig with { NativeLang = "English" };

        Assert.Equal(new LanguagePair("Auto detect", "Vietnamese"), LanguagePolicy.ResolvePair("hello", nativeConfig, []));
        Assert.Equal(new LanguagePair("Auto detect", "English"), LanguagePolicy.ResolvePair("你好", firstConfig, []));
    }

    [Fact]
    public void FallbackSkipsFirstTargetWhenItMatchesDetectedSource()
    {
        var config = AppConfig.Default with
        {
            SourceLang = "Auto detect",
            TargetLang = "Chinese",
            NativeLang = "Chinese",
            TargetLanguages = ["Chinese", "English"]
        };

        Assert.Equal(new LanguagePair("Auto detect", "English"), LanguagePolicy.ResolvePair("你好", config, []));
    }

    [Fact]
    public void KeepsExplicitSameLanguagePairForGrammar()
    {
        var config = AppConfig.Default with { SourceLang = "English", TargetLang = "English" };

        Assert.Equal(new LanguagePair("English", "English"), LanguagePolicy.ResolvePair("hello", config, []));
    }

    [Fact]
    public void SwapsPair()
    {
        Assert.Equal(new LanguagePair("Vietnamese", "English"), LanguagePolicy.SwapPair(new("English", "Vietnamese")));
    }
}
