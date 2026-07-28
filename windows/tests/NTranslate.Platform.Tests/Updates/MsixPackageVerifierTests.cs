using System.IO.Compression;
using NTranslate.Core.Updates;
using NTranslate.Platform.Updates;

namespace NTranslate.Platform.Tests.Updates;

public sealed class MsixPackageVerifierTests
{
    [Fact]
    public async Task RejectsMissingPackage() =>
        await Assert.ThrowsAsync<MsixVerificationException>(() => Verifier(true).VerifyAsync(Path.Combine(Path.GetTempPath(), $"{Guid.NewGuid():N}.msix"), CancellationToken.None));

    [Fact]
    public async Task RejectsWrongExtension()
    {
        using var fixture = Fixture(".zip", ValidManifest);
        await Assert.ThrowsAsync<MsixVerificationException>(() => Verifier(true).VerifyAsync(fixture.Path, CancellationToken.None));
    }

    [Fact]
    public async Task RejectsReparsePoint()
    {
        if (!OperatingSystem.IsWindows()) return;
        using var fixture = Fixture(".msix", ValidManifest);
        var link = fixture.Path + ".link.msix";
        try
        {
            File.CreateSymbolicLink(link, fixture.Path);
        }
        catch (Exception exception) when (exception is UnauthorizedAccessException or IOException) { return; }
        try
        {
            await Assert.ThrowsAsync<MsixVerificationException>(() => Verifier(true).VerifyAsync(link, CancellationToken.None));
        }
        finally { File.Delete(link); }
    }

    [Fact]
    public async Task RejectsUnsignedBeforeOpeningZip()
    {
        using var fixture = Raw("not a zip");
        var signatureChecked = false;
        var verifier = new MsixPackageVerifier(_ => { signatureChecked = true; return false; });

        await Assert.ThrowsAsync<MsixVerificationException>(() => verifier.VerifyAsync(fixture.Path, CancellationToken.None));

        Assert.True(signatureChecked);
    }

    [Fact]
    public async Task RejectsInvalidZip()
    {
        using var fixture = Raw("not a zip");
        await Assert.ThrowsAsync<MsixVerificationException>(() => Verifier(true).VerifyAsync(fixture.Path, CancellationToken.None));
    }

    [Theory]
    [InlineData(null, false)]
    [InlineData("<Package/>", false)]
    [InlineData(ValidManifest, true)]
    public async Task RequiresExactlyOneRootManifest(string? manifest, bool duplicate)
    {
        using var fixture = Fixture(".msix", manifest, duplicate);
        await Assert.ThrowsAsync<MsixVerificationException>(() => Verifier(true).VerifyAsync(fixture.Path, CancellationToken.None));
    }

    [Theory]
    [InlineData("Wrong.Identity", "CN=Ninh Nguyen", "x64", "1.2.3.0")]
    [InlineData("NinhNguyen375.NTranslate", "CN=Attacker", "x64", "1.2.3.0")]
    [InlineData("NinhNguyen375.NTranslate", "CN=Ninh Nguyen", "arm64", "1.2.3.0")]
    [InlineData("NinhNguyen375.NTranslate", "CN=Ninh Nguyen", "x64", "1.2.3.4")]
    [InlineData("NinhNguyen375.NTranslate", "CN=Ninh Nguyen", "x64", "1.2")]
    public async Task RejectsWrongManifestIdentity(string name, string publisher, string architecture, string version)
    {
        using var fixture = Fixture(".msix", Manifest(name, publisher, architecture, version));
        await Assert.ThrowsAsync<MsixVerificationException>(() => Verifier(true).VerifyAsync(fixture.Path, CancellationToken.None));
    }

    [Fact]
    public async Task RejectsDtd()
    {
        using var fixture = Fixture(".msix", "<!DOCTYPE Package [<!ENTITY xxe SYSTEM 'file:///c:/windows/win.ini'>]><Package><Identity Name='&xxe;' Publisher='CN=Ninh Nguyen' ProcessorArchitecture='x64' Version='1.2.3.0'/></Package>");
        await Assert.ThrowsAsync<MsixVerificationException>(() => Verifier(true).VerifyAsync(fixture.Path, CancellationToken.None));
    }

    [Fact]
    public async Task ReturnsVerifiedSignedPackage()
    {
        using var fixture = Fixture(".msix", ValidManifest);

        var package = await Verifier(true).VerifyAsync(fixture.Path, CancellationToken.None);

        Assert.Equal(Path.GetFullPath(fixture.Path), package.Path);
        Assert.Equal("NinhNguyen375.NTranslate", package.IdentityName);
        Assert.Equal("CN=Ninh Nguyen", package.Publisher);
        Assert.Equal(new SemanticVersion(1, 2, 3), package.Version);
        Assert.Equal("x64", package.Architecture);
    }

    private const string ValidManifest = "<Package xmlns='http://schemas.microsoft.com/appx/manifest/foundation/windows10'><Identity Name='NinhNguyen375.NTranslate' Publisher='CN=Ninh Nguyen' ProcessorArchitecture='x64' Version='1.2.3.0'/></Package>";
    private static string Manifest(string name, string publisher, string architecture, string version) => $"<Package xmlns='http://schemas.microsoft.com/appx/manifest/foundation/windows10'><Identity Name='{name}' Publisher='{publisher}' ProcessorArchitecture='{architecture}' Version='{version}'/></Package>";
    private static MsixPackageVerifier Verifier(bool signed) => new(_ => signed);

    private static TemporaryFile Raw(string content)
    {
        var file = new TemporaryFile(".msix");
        File.WriteAllText(file.Path, content);
        return file;
    }

    private static TemporaryFile Fixture(string extension, string? manifest, bool duplicate = false)
    {
        var file = new TemporaryFile(extension);
        using var archive = ZipFile.Open(file.Path, ZipArchiveMode.Create);
        if (manifest is not null)
        {
            Write(archive.CreateEntry("AppxManifest.xml"), manifest);
            if (duplicate) Write(archive.CreateEntry("AppxManifest.xml"), manifest);
        }
        return file;
    }

    private static void Write(ZipArchiveEntry entry, string value)
    {
        using var writer = new StreamWriter(entry.Open());
        writer.Write(value);
    }

    private sealed class TemporaryFile(string extension) : IDisposable
    {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"NTranslate-{Guid.NewGuid():N}{extension}");
        public void Dispose() => File.Delete(Path);
    }
}
