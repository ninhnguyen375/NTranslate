using System.Globalization;
using System.Text.RegularExpressions;

namespace NTranslate.Core.Updates;

public readonly record struct SemanticVersion(int Major, int Minor, int Patch) : IComparable<SemanticVersion>
{
    private static readonly Regex Pattern = new(@"^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$", RegexOptions.CultureInvariant);

    public static bool TryParse(string? value, out SemanticVersion version)
    {
        version = default;
        if (value is null)
            return false;

        var match = Pattern.Match(value);
        if (!match.Success ||
            !int.TryParse(match.Groups[1].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var major) ||
            !int.TryParse(match.Groups[2].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var minor) ||
            !int.TryParse(match.Groups[3].Value, NumberStyles.None, CultureInfo.InvariantCulture, out var patch))
            return false;

        version = new(major, minor, patch);
        return true;
    }

    public int CompareTo(SemanticVersion other)
    {
        var major = Major.CompareTo(other.Major);
        if (major != 0) return major;
        var minor = Minor.CompareTo(other.Minor);
        return minor != 0 ? minor : Patch.CompareTo(other.Patch);
    }

    public override string ToString() => FormattableString.Invariant($"{Major}.{Minor}.{Patch}");

    public static bool operator <(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) < 0;
    public static bool operator >(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) > 0;
    public static bool operator <=(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) <= 0;
    public static bool operator >=(SemanticVersion left, SemanticVersion right) => left.CompareTo(right) >= 0;
}

public sealed record GitHubAsset(string Name, Uri DownloadUrl);
public sealed record GitHubRelease(string Tag, string Notes, bool Draft, bool Prerelease, IReadOnlyList<GitHubAsset> Assets);
public sealed record WindowsUpdate(
    SemanticVersion Version,
    string Tag,
    string Notes,
    Uri InstallerDownloadUrl,
    string InstallerAssetName,
    Uri ChecksumDownloadUrl,
    string ChecksumAssetName);

public static class WindowsUpdatePolicy
{
    public static WindowsUpdate? Select(SemanticVersion currentVersion, IEnumerable<GitHubRelease> releases)
    {
        WindowsUpdate? selected = null;
        foreach (var release in releases)
        {
            if (release.Draft || release.Prerelease ||
                !release.Tag.StartsWith("windows-v", StringComparison.Ordinal) ||
                !SemanticVersion.TryParse(release.Tag["windows-v".Length..], out var version) ||
                version <= currentVersion)
                continue;

            var installerName = $"NTranslate-{version}-win-x64-setup.exe";
            var checksumName = installerName + ".sha256";
            var installerMatches = release.Assets.Where(asset => string.Equals(asset.Name, installerName, StringComparison.Ordinal)).ToArray();
            var checksumMatches = release.Assets.Where(asset => string.Equals(asset.Name, checksumName, StringComparison.Ordinal)).ToArray();
            if (installerMatches.Length != 1 || checksumMatches.Length != 1)
                continue;

            var candidate = new WindowsUpdate(
                version,
                release.Tag,
                release.Notes,
                installerMatches[0].DownloadUrl,
                installerMatches[0].Name,
                checksumMatches[0].DownloadUrl,
                checksumMatches[0].Name);
            if (selected is null || candidate.Version > selected.Version)
                selected = candidate;
        }
        return selected;
    }
}
