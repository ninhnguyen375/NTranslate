using NTranslate.Core.Updates;

namespace NTranslate.Core.Tests.Updates;

public sealed class UpdatePolicyTests
{
    [Theory]
    [InlineData("1.2.3")]
    [InlineData("v1.2.3")]
    public void ParsesStrictSemanticVersions(string value)
    {
        Assert.True(SemanticVersion.TryParse(value, out var version));
        Assert.Equal(new SemanticVersion(1, 2, 3), version);
    }

    [Theory]
    [InlineData("")]
    [InlineData("1.2")]
    [InlineData("1.2.3.4")]
    [InlineData("1.2.3-beta")]
    [InlineData("V1.2.3")]
    [InlineData("01.2.3")]
    [InlineData(" 1.2.3")]
    [InlineData("1.2.3 ")]
    [InlineData("1.-2.3")]
    public void RejectsNonSemanticVersions(string value) =>
        Assert.False(SemanticVersion.TryParse(value, out _));

    [Fact]
    public void ComparesNumericComponents()
    {
        Assert.True(new SemanticVersion(2, 0, 0) > new SemanticVersion(1, 99, 99));
        Assert.True(new SemanticVersion(1, 3, 0) > new SemanticVersion(1, 2, 99));
        Assert.True(new SemanticVersion(1, 2, 4) > new SemanticVersion(1, 2, 3));
        Assert.Equal(0, new SemanticVersion(1, 2, 3).CompareTo(new(1, 2, 3)));
    }

    [Fact]
    public void SelectsOnlyExactCaseSensitiveAssetWithMatchingVersion()
    {
        var release = Release("v1.2.3", "NTranslate-1.2.3-win-x64.msix");

        var update = WindowsUpdatePolicy.Select(new SemanticVersion(1, 2, 2), [release]);

        Assert.NotNull(update);
        Assert.Equal(new SemanticVersion(1, 2, 3), update.Version);
        Assert.Equal("NTranslate-1.2.3-win-x64.msix", update.AssetName);
    }

    [Theory]
    [InlineData("NTranslate-1.2.3-win-X64.msix")]
    [InlineData("ntranslate-1.2.3-win-x64.msix")]
    [InlineData("NTranslate-v1.2.3-win-x64.msix")]
    [InlineData("NTranslate-1.2.4-win-x64.msix")]
    public void RejectsAssetNameMismatch(string assetName) =>
        Assert.Null(WindowsUpdatePolicy.Select(new(1, 0, 0), [Release("v1.2.3", assetName)]));

    [Fact]
    public void RejectsDraftPrereleaseSameOlderMultipleAndMalformedReleases()
    {
        var current = new SemanticVersion(1, 2, 3);
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v2.0.0", "NTranslate-2.0.0-win-x64.msix", draft: true)]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v2.0.0", "NTranslate-2.0.0-win-x64.msix", prerelease: true)]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v1.2.3", "NTranslate-1.2.3-win-x64.msix")]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v1.2.2", "NTranslate-1.2.2-win-x64.msix")]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v2.0.0", "NTranslate-2.0.0-win-x64.msix", secondAsset: true)]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v2.0", "NTranslate-2.0-win-x64.msix")]));
    }

    private static GitHubRelease Release(
        string tag,
        string assetName,
        bool draft = false,
        bool prerelease = false,
        bool secondAsset = false)
    {
        var assets = new List<GitHubAsset> { new(assetName, new Uri($"https://github.com/example/{assetName}")) };
        if (secondAsset)
            assets.Add(new(assetName, new Uri($"https://objects.githubusercontent.com/example/{assetName}")));
        return new(tag, "notes", draft, prerelease, assets);
    }
}
