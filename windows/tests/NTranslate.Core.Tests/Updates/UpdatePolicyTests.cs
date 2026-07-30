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
    public void SelectsOnlyExactCaseSensitiveInstallerAndChecksumWithMatchingVersion()
    {
        var release = Release("v1.2.3", "NTranslate-1.2.3-win-x64-setup.exe", "NTranslate-1.2.3-win-x64-setup.exe.sha256");

        var update = WindowsUpdatePolicy.Select(new SemanticVersion(1, 2, 2), [release]);

        Assert.NotNull(update);
        Assert.Equal(new SemanticVersion(1, 2, 3), update.Version);
        Assert.Equal("NTranslate-1.2.3-win-x64-setup.exe", update.InstallerAssetName);
        Assert.Equal("NTranslate-1.2.3-win-x64-setup.exe.sha256", update.ChecksumAssetName);
    }

    [Theory]
    [InlineData("NTranslate-1.2.3-win-X64-setup.exe")]
    [InlineData("ntranslate-1.2.3-win-x64-setup.exe")]
    [InlineData("NTranslate-v1.2.3-win-x64-setup.exe")]
    [InlineData("NTranslate-1.2.4-win-x64-setup.exe")]
    [InlineData("NTranslate-1.2.3-win-x64.msix")]
    public void RejectsInstallerNameMismatch(string installerName) =>
        Assert.Null(WindowsUpdatePolicy.Select(new(1, 0, 0), [Release("v1.2.3", installerName, installerName + ".sha256")]));

    [Fact]
    public void RejectsMissingChecksumAsset()
    {
        var release = new GitHubRelease(
            "v1.2.3",
            "notes",
            false,
            false,
            [new GitHubAsset("NTranslate-1.2.3-win-x64-setup.exe", new Uri("https://github.com/example/NTranslate-1.2.3-win-x64-setup.exe"))]);

        Assert.Null(WindowsUpdatePolicy.Select(new(1, 0, 0), [release]));
    }

    [Fact]
    public void RejectsDuplicateInstallerOrChecksumAsset()
    {
        var installerName = "NTranslate-1.2.3-win-x64-setup.exe";
        var checksumName = installerName + ".sha256";
        var duplicateInstaller = new GitHubRelease(
            "v1.2.3",
            "notes",
            false,
            false,
            [
                new(installerName, new Uri($"https://github.com/example/{installerName}")),
                new(installerName, new Uri($"https://objects.githubusercontent.com/example/{installerName}")),
                new(checksumName, new Uri($"https://github.com/example/{checksumName}")),
            ]);
        var duplicateChecksum = new GitHubRelease(
            "v1.2.3",
            "notes",
            false,
            false,
            [
                new(installerName, new Uri($"https://github.com/example/{installerName}")),
                new(checksumName, new Uri($"https://github.com/example/{checksumName}")),
                new(checksumName, new Uri($"https://objects.githubusercontent.com/example/{checksumName}")),
            ]);

        Assert.Null(WindowsUpdatePolicy.Select(new(1, 0, 0), [duplicateInstaller]));
        Assert.Null(WindowsUpdatePolicy.Select(new(1, 0, 0), [duplicateChecksum]));
    }

    [Fact]
    public void RejectsDraftPrereleaseSameOlderAndMalformedReleases()
    {
        var current = new SemanticVersion(1, 2, 3);
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v2.0.0", "NTranslate-2.0.0-win-x64-setup.exe", "NTranslate-2.0.0-win-x64-setup.exe.sha256", draft: true)]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v2.0.0", "NTranslate-2.0.0-win-x64-setup.exe", "NTranslate-2.0.0-win-x64-setup.exe.sha256", prerelease: true)]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v1.2.3", "NTranslate-1.2.3-win-x64-setup.exe", "NTranslate-1.2.3-win-x64-setup.exe.sha256")]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v1.2.2", "NTranslate-1.2.2-win-x64-setup.exe", "NTranslate-1.2.2-win-x64-setup.exe.sha256")]));
        Assert.Null(WindowsUpdatePolicy.Select(current, [Release("v2.0", "NTranslate-2.0-win-x64-setup.exe", "NTranslate-2.0-win-x64-setup.exe.sha256")]));
    }

    [Fact]
    public void SelectsHighestValidStableReleaseEvenWhenNewerReleaseIsMalformed()
    {
        var current = new SemanticVersion(1, 0, 0);
        var releases = new[]
        {
            Release("v3.0.0", "NTranslate-3.0.0-win-x64-setup.exe", "NTranslate-3.0.0-win-x64-setup.exe.sha256", draft: true),
            Release("v2.0.0", "NTranslate-2.0.0-win-x64-setup.exe", "NTranslate-2.0.0-win-x64-setup.exe.sha256"),
            Release("v1.5.0", "NTranslate-1.5.0-win-x64-setup.exe", "NTranslate-1.5.0-win-x64-setup.exe.sha256"),
        };

        var update = WindowsUpdatePolicy.Select(current, releases);

        Assert.NotNull(update);
        Assert.Equal(new SemanticVersion(2, 0, 0), update.Version);
    }

    private static GitHubRelease Release(
        string tag,
        string installerName,
        string checksumName,
        bool draft = false,
        bool prerelease = false)
    {
        var assets = new List<GitHubAsset>
        {
            new(installerName, new Uri($"https://github.com/example/{installerName}")),
            new(checksumName, new Uri($"https://github.com/example/{checksumName}")),
        };
        return new(tag, "notes", draft, prerelease, assets);
    }
}
