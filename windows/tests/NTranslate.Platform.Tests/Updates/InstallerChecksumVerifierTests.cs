using System.Security.Cryptography;
using NTranslate.Core.Updates;
using NTranslate.Platform.Updates;

namespace NTranslate.Platform.Tests.Updates;

public sealed class InstallerChecksumVerifierTests
{
    private const string InstallerName = "NTranslate-1.2.3-win-x64-setup.exe";
    private static readonly SemanticVersion ExpectedVersion = new(1, 2, 3);

    [Fact]
    public async Task RejectsMissingInstaller()
    {
        using var directory = new TemporaryDirectory();
        var checksum = directory.WriteFile("checksum.sha256", Sha256("content") + " *" + InstallerName);
        await Assert.ThrowsAsync<InstallerVerificationException>(() =>
            Verify(Path.Combine(directory.Path, InstallerName), checksum));
    }

    [Fact]
    public async Task RejectsMissingChecksum()
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        await Assert.ThrowsAsync<InstallerVerificationException>(() =>
            Verify(installer, Path.Combine(directory.Path, "missing.sha256")));
    }

    [Fact]
    public async Task RejectsInstallerReparsePoint()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile("real-" + InstallerName, "content");
        var checksum = directory.WriteFile("checksum.sha256", Sha256("content") + " *" + InstallerName);
        var link = Path.Combine(directory.Path, InstallerName);
        try { File.CreateSymbolicLink(link, installer); }
        catch (Exception exception) when (exception is UnauthorizedAccessException or IOException) { return; }
        await Assert.ThrowsAsync<InstallerVerificationException>(() => Verify(link, checksum));
    }

    [Theory]
    [InlineData("")]
    [InlineData("not-hex-not-hex-not-hex-not-hex-not-hex-not-hex-not-hex-not-hex *" + InstallerName)]
    [InlineData("abcd *" + InstallerName)]
    public async Task RejectsMalformedDigest(string checksumContent)
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        var checksum = directory.WriteFile("checksum.sha256", checksumContent);
        await Assert.ThrowsAsync<InstallerVerificationException>(() => Verify(installer, checksum));
    }

    [Fact]
    public async Task RejectsMissingFilenameInChecksum()
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        var checksum = directory.WriteFile("checksum.sha256", Sha256("content"));
        await Assert.ThrowsAsync<InstallerVerificationException>(() => Verify(installer, checksum));
    }

    [Theory]
    [InlineData("NTranslate-1.2.3-win-X64-setup.exe")]
    [InlineData("ntranslate-1.2.3-win-x64-setup.exe")]
    [InlineData("dir/NTranslate-1.2.3-win-x64-setup.exe")]
    public async Task RejectsWrongOrCaseChangedFilenameInChecksum(string filename)
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        var checksum = directory.WriteFile("checksum.sha256", Sha256("content") + " *" + filename);
        await Assert.ThrowsAsync<InstallerVerificationException>(() => Verify(installer, checksum));
    }

    [Fact]
    public async Task RejectsMultipleChecksumRecords()
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        var checksum = directory.WriteFile(
            "checksum.sha256",
            Sha256("content") + " *" + InstallerName + "\n" + Sha256("content") + " *" + InstallerName);
        await Assert.ThrowsAsync<InstallerVerificationException>(() => Verify(installer, checksum));
    }

    [Fact]
    public async Task RejectsDigestMismatch()
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        var checksum = directory.WriteFile("checksum.sha256", Sha256("different") + " *" + InstallerName);
        await Assert.ThrowsAsync<InstallerVerificationException>(() => Verify(installer, checksum));
    }

    [Fact]
    public async Task RejectsCancellation()
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        var checksum = directory.WriteFile("checksum.sha256", Sha256("content") + " *" + InstallerName);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            new InstallerChecksumVerifier().VerifyAsync(installer, checksum, InstallerName, ExpectedVersion, cancellation.Token));
    }

    [Fact]
    public async Task AcceptsValidUppercaseDigestAndReturnsExpectedVersion()
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        var checksum = directory.WriteFile("checksum.sha256", Sha256("content").ToUpperInvariant() + " *" + InstallerName);

        var result = await Verify(installer, checksum);

        Assert.Equal(Path.GetFullPath(installer), result.Path);
        Assert.Equal(ExpectedVersion, result.Version);
    }

    [Fact]
    public async Task AcceptsValidLowercaseDigest()
    {
        using var directory = new TemporaryDirectory();
        var installer = directory.WriteFile(InstallerName, "content");
        var checksum = directory.WriteFile("checksum.sha256", Sha256("content") + " *" + InstallerName);

        var result = await Verify(installer, checksum);

        Assert.Equal(ExpectedVersion, result.Version);
    }

    private static Task<VerifiedInstaller> Verify(string installerPath, string checksumPath) =>
        new InstallerChecksumVerifier().VerifyAsync(installerPath, checksumPath, InstallerName, ExpectedVersion, CancellationToken.None);

    private static string Sha256(string content) => Convert.ToHexStringLower(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(content)));

    private sealed class TemporaryDirectory : IDisposable
    {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"NTranslate-{Guid.NewGuid():N}");
        public TemporaryDirectory() => Directory.CreateDirectory(Path);
        public string WriteFile(string name, string content)
        {
            var path = System.IO.Path.Combine(Path, name);
            File.WriteAllText(path, content);
            return path;
        }
        public void Dispose() => Directory.Delete(Path, true);
    }
}
