using System.Security.Cryptography;
using System.Text.RegularExpressions;
using NTranslate.Core.Updates;

namespace NTranslate.Platform.Updates;

public sealed record VerifiedInstaller(string Path, SemanticVersion Version);

public interface IInstallerChecksumVerifier
{
    Task<VerifiedInstaller> VerifyAsync(
        string installerPath,
        string checksumPath,
        string expectedInstallerName,
        SemanticVersion expectedVersion,
        CancellationToken token);
}

public sealed class InstallerVerificationException(string message) : Exception(message);

public sealed class InstallerChecksumVerifier : IInstallerChecksumVerifier
{
    private const long MaximumChecksumBytes = 4 * 1024;
    private static readonly Regex ChecksumLine = new(@"^([0-9A-Fa-f]{64}) \*(.+)$", RegexOptions.CultureInvariant);

    public async Task<VerifiedInstaller> VerifyAsync(
        string installerPath,
        string checksumPath,
        string expectedInstallerName,
        SemanticVersion expectedVersion,
        CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        ArgumentException.ThrowIfNullOrWhiteSpace(installerPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(checksumPath);
        ArgumentException.ThrowIfNullOrWhiteSpace(expectedInstallerName);

        var fullInstallerPath = Path.GetFullPath(installerPath);
        var fullChecksumPath = Path.GetFullPath(checksumPath);
        if (!File.Exists(fullInstallerPath))
            throw new InstallerVerificationException("Installer does not exist.");
        if (!File.Exists(fullChecksumPath))
            throw new InstallerVerificationException("Checksum file does not exist.");
        if ((File.GetAttributes(fullInstallerPath) & FileAttributes.ReparsePoint) != 0)
            throw new InstallerVerificationException("Installer cannot be a reparse point.");
        if ((File.GetAttributes(fullChecksumPath) & FileAttributes.ReparsePoint) != 0)
            throw new InstallerVerificationException("Checksum file cannot be a reparse point.");
        if (!string.Equals(Path.GetFileName(fullInstallerPath), expectedInstallerName, StringComparison.Ordinal))
            throw new InstallerVerificationException("Installer file name does not match expected update asset.");

        var checksumInfo = new FileInfo(fullChecksumPath);
        if (checksumInfo.Length > MaximumChecksumBytes)
            throw new InstallerVerificationException("Checksum file exceeds the size limit.");

        var checksumText = await File.ReadAllTextAsync(fullChecksumPath, token).ConfigureAwait(false);
        var lines = checksumText.Replace("\r\n", "\n").Split('\n', StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length != 1)
            throw new InstallerVerificationException("Checksum file must contain exactly one record.");

        var match = ChecksumLine.Match(lines[0]);
        if (!match.Success)
            throw new InstallerVerificationException("Checksum file is malformed.");
        if (!string.Equals(match.Groups[2].Value, expectedInstallerName, StringComparison.Ordinal))
            throw new InstallerVerificationException("Checksum file does not reference the expected installer name.");

        byte[] expectedDigest;
        try { expectedDigest = Convert.FromHexString(match.Groups[1].Value); }
        catch (FormatException) { throw new InstallerVerificationException("Checksum file is malformed."); }

        await using var installerStream = File.OpenRead(fullInstallerPath);
        var actualDigest = await SHA256.HashDataAsync(installerStream, token).ConfigureAwait(false);
        if (!CryptographicOperations.FixedTimeEquals(expectedDigest, actualDigest))
            throw new InstallerVerificationException("Installer checksum does not match.");

        return new VerifiedInstaller(fullInstallerPath, expectedVersion);
    }
}
