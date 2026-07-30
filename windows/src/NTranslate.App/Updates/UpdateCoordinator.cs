using System.Diagnostics;
using NTranslate.Core.Updates;
using NTranslate.Platform.Updates;

namespace NTranslate.App.Updates;

public enum UpdateState { Idle, Checking, Available, Installing, Error }

public sealed class UpdateCoordinator
{
    private readonly SemanticVersion _currentVersion;
    private readonly Func<CancellationToken, Task<IReadOnlyList<WindowsUpdate>>> _check;
    private readonly Func<Uri, string, long, CancellationToken, Task> _download;
    private readonly IInstallerChecksumVerifier _verifier;
    private readonly Action<ProcessStartInfo> _launch;
    private readonly Action _requestShutdown;
    private readonly string _downloadDirectory;
    private int _busy;
    private WindowsUpdate? _available;

    public UpdateCoordinator(
        SemanticVersion currentVersion,
        Func<CancellationToken, Task<IReadOnlyList<WindowsUpdate>>> check,
        Func<Uri, string, long, CancellationToken, Task> download,
        IInstallerChecksumVerifier verifier,
        Action<ProcessStartInfo> launch,
        Action requestShutdown,
        string? downloadDirectory = null)
    {
        _currentVersion = currentVersion;
        _check = check;
        _download = download;
        _verifier = verifier;
        _launch = launch;
        _requestShutdown = requestShutdown;
        _downloadDirectory = downloadDirectory ?? Path.Combine(Path.GetTempPath(), "NTranslate", "Updates");
    }

    public UpdateState State { get; private set; }
    public string? StatusMessage { get; private set; }
    public string? ReleaseNotes => _available?.Notes;

    public async Task CheckAsync(bool manual, CancellationToken token)
    {
        if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return;
        try
        {
            State = UpdateState.Checking;
            StatusMessage = null;
            var updates = await _check(token).ConfigureAwait(false);
            _available = WindowsUpdatePolicy.Select(_currentVersion, updates.SelectReleases());
            // SelectReleases allows callers to provide already-selected candidates without duplicating transport models.
            if (_available is null)
            {
                State = UpdateState.Idle;
                StatusMessage = manual ? "NTranslate is up to date." : null;
            }
            else State = UpdateState.Available;
        }
        catch (OperationCanceledException)
        {
            State = UpdateState.Idle;
            StatusMessage = null;
        }
        catch
        {
            State = UpdateState.Error;
            StatusMessage = "Unable to check for updates.";
            if (!manual) { State = UpdateState.Idle; StatusMessage = null; }
        }
        finally { Volatile.Write(ref _busy, 0); }
    }

    public async Task InstallAsync(CancellationToken token)
    {
        if (_available is null || Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return;
        try
        {
            State = UpdateState.Installing;
            Directory.CreateDirectory(_downloadDirectory);
            var installerPath = Path.Combine(_downloadDirectory, _available.InstallerAssetName);
            var checksumPath = Path.Combine(_downloadDirectory, _available.ChecksumAssetName);
            await _download(_available.InstallerDownloadUrl, installerPath, GitHubReleaseClient.MaximumInstallerBytes, token).ConfigureAwait(false);
            await _download(_available.ChecksumDownloadUrl, checksumPath, GitHubReleaseClient.MaximumChecksumBytes, token).ConfigureAwait(false);
            var verified = await _verifier.VerifyAsync(installerPath, checksumPath, _available.InstallerAssetName, _available.Version, token).ConfigureAwait(false);
            var startInfo = new ProcessStartInfo(verified.Path) { UseShellExecute = true };
            startInfo.ArgumentList.Add("/NORESTART");
            startInfo.ArgumentList.Add("/VERYSILENT");
            startInfo.ArgumentList.Add("/SUPPRESSMSGBOXES");
            startInfo.ArgumentList.Add("/CLOSEAPPLICATIONS");
            startInfo.ArgumentList.Add("/RESTARTAPPLICATIONS");
            _launch(startInfo);
            _requestShutdown();
            State = UpdateState.Idle;
            _available = null;
        }
        catch (OperationCanceledException)
        {
            State = UpdateState.Idle;
            StatusMessage = null;
        }
        catch
        {
            State = UpdateState.Error;
            StatusMessage = "Unable to verify or install update.";
            throw;
        }
        finally { Volatile.Write(ref _busy, 0); }
    }
}

internal static class UpdateCandidates
{
    public static IEnumerable<GitHubRelease> SelectReleases(this IReadOnlyList<WindowsUpdate> updates) =>
        updates.Select(update => new GitHubRelease(
            update.Tag,
            update.Notes,
            false,
            false,
            [
                new GitHubAsset(update.InstallerAssetName, update.InstallerDownloadUrl),
                new GitHubAsset(update.ChecksumAssetName, update.ChecksumDownloadUrl),
            ]));
}
