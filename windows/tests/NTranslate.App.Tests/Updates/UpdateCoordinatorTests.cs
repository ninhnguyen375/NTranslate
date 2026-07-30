using System.Diagnostics;
using NTranslate.App.Updates;
using NTranslate.Core.Updates;
using NTranslate.Platform.Updates;

namespace NTranslate.App.Tests.Updates;

public sealed class UpdateCoordinatorTests
{
    [Fact]
    public async Task SilentNoUpdateReturnsIdleWithoutMessage()
    {
        var coordinator = Coordinator([]);

        await coordinator.CheckAsync(manual: false, CancellationToken.None);

        Assert.Equal(UpdateState.Idle, coordinator.State);
        Assert.Null(coordinator.StatusMessage);
    }

    [Fact]
    public async Task ManualNoUpdateReportsCurrent()
    {
        var coordinator = Coordinator([]);

        await coordinator.CheckAsync(manual: true, CancellationToken.None);

        Assert.Equal(UpdateState.Idle, coordinator.State);
        Assert.Equal("NTranslate is up to date.", coordinator.StatusMessage);
    }

    [Fact]
    public async Task AvailableUpdateExposesPlainTextNotes()
    {
        var update = Update("<script>alert(1)</script>\nnotes");
        var coordinator = Coordinator([update]);

        await coordinator.CheckAsync(manual: true, CancellationToken.None);

        Assert.Equal(UpdateState.Available, coordinator.State);
        Assert.Equal("<script>alert(1)</script>\nnotes", coordinator.ReleaseNotes);
    }

    [Fact]
    public async Task PreventsDuplicateOperations()
    {
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var checks = 0;
        var coordinator = new UpdateCoordinator(
            new(1, 0, 0),
            async token => { checks++; await gate.Task.WaitAsync(token); return []; },
            (_, _, _, _) => Task.CompletedTask,
            new RejectingVerifier(),
            _ => { },
            () => { });

        var first = coordinator.CheckAsync(true, CancellationToken.None);
        var second = coordinator.CheckAsync(true, CancellationToken.None);
        gate.SetResult();
        await Task.WhenAll(first, second);

        Assert.Equal(1, checks);
    }

    [Fact]
    public async Task CancellationReturnsIdle()
    {
        var coordinator = new UpdateCoordinator(
            new(1, 0, 0),
            _ => throw new OperationCanceledException(),
            (_, _, _, _) => Task.CompletedTask,
            new RejectingVerifier(),
            _ => { },
            () => { });

        await coordinator.CheckAsync(true, CancellationToken.None);

        Assert.Equal(UpdateState.Idle, coordinator.State);
    }

    [Fact]
    public async Task InstallDownloadsInstallerThenChecksumWithDistinctLimits()
    {
        using var directory = new TemporaryDirectory();
        var update = Update("notes");
        var downloads = new List<(Uri Url, long MaxBytes)>();
        var coordinator = new UpdateCoordinator(
            new(1, 0, 0),
            _ => Task.FromResult<IReadOnlyList<WindowsUpdate>>([update]),
            async (url, path, maxBytes, _) => { downloads.Add((url, maxBytes)); await File.WriteAllTextAsync(path, "content"); },
            new AcceptingVerifier(),
            _ => { },
            () => { },
            directory.Path);

        await coordinator.CheckAsync(true, CancellationToken.None);
        await coordinator.InstallAsync(CancellationToken.None);

        Assert.Equal(2, downloads.Count);
        Assert.Equal(update.InstallerDownloadUrl, downloads[0].Url);
        Assert.Equal(GitHubReleaseClient.MaximumInstallerBytes, downloads[0].MaxBytes);
        Assert.Equal(update.ChecksumDownloadUrl, downloads[1].Url);
        Assert.Equal(GitHubReleaseClient.MaximumChecksumBytes, downloads[1].MaxBytes);
    }

    [Fact]
    public async Task InstallLaunchesVerifiedSetupWithSilentArgumentsAndRequestsShutdown()
    {
        using var directory = new TemporaryDirectory();
        var update = Update("notes");
        ProcessStartInfo? launched = null;
        var shutdownRequested = false;
        var coordinator = new UpdateCoordinator(
            new(1, 0, 0),
            _ => Task.FromResult<IReadOnlyList<WindowsUpdate>>([update]),
            async (_, path, _, _) => await File.WriteAllTextAsync(path, "content"),
            new AcceptingVerifier(),
            info => launched = info,
            () => shutdownRequested = true,
            directory.Path);

        await coordinator.CheckAsync(true, CancellationToken.None);
        await coordinator.InstallAsync(CancellationToken.None);

        Assert.NotNull(launched);
        Assert.True(launched!.UseShellExecute);
        Assert.EndsWith("-setup.exe", launched.FileName, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(["/NORESTART", "/VERYSILENT", "/SUPPRESSMSGBOXES", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS"], launched.ArgumentList);
        Assert.True(shutdownRequested);
        Assert.Equal(UpdateState.Idle, coordinator.State);
    }

    [Fact]
    public async Task VerificationFailurePreventsLaunchAndShutdown()
    {
        using var directory = new TemporaryDirectory();
        var update = Update("notes");
        var launched = false;
        var shutdownRequested = false;
        var coordinator = new UpdateCoordinator(
            new(1, 0, 0),
            _ => Task.FromResult<IReadOnlyList<WindowsUpdate>>([update]),
            async (_, path, _, _) => await File.WriteAllTextAsync(path, "content"),
            new RejectingVerifier(),
            _ => launched = true,
            () => shutdownRequested = true,
            directory.Path);
        await coordinator.CheckAsync(true, CancellationToken.None);

        await Assert.ThrowsAsync<InstallerVerificationException>(() => coordinator.InstallAsync(CancellationToken.None));

        Assert.False(launched);
        Assert.False(shutdownRequested);
        Assert.Equal(UpdateState.Error, coordinator.State);
    }

    [Fact]
    public async Task ManualFlowInstallsOnlyAfterExplicitConfirmation()
    {
        var update = Update("notes");
        var installs = 0;
        var coordinator = new UpdateCoordinator(
            new(1, 0, 0),
            _ => Task.FromResult<IReadOnlyList<WindowsUpdate>>([update]),
            (_, _, _, _) => { installs++; return Task.CompletedTask; },
            new RejectingVerifier(),
            _ => { },
            () => { });
        var dialog = new RecordingUpdateDialog(confirmInstall: false);

        await new ManualUpdateFlow(coordinator, dialog).RunAsync(CancellationToken.None);

        Assert.Equal(0, installs);
        Assert.Contains(dialog.States, state => state.State == UpdateState.Checking);
        Assert.Contains(dialog.States, state => state.State == UpdateState.Available && state.ReleaseNotes == "notes");
    }

    [Fact]
    public void MapsPackagedVersionAndFallsBackForUnpackagedRuntime()
    {
        Assert.Equal(new SemanticVersion(2, 3, 4), CurrentVersionResolver.Resolve(() => new Version(2, 3, 4, 5), new Version(1, 0, 0)));
        Assert.Equal(new SemanticVersion(1, 0, 0), CurrentVersionResolver.Resolve(() => throw new InvalidOperationException(), new Version(1, 0, 0)));
    }

    private static WindowsUpdate Update(string notes) => new(
        new(2, 0, 0),
        "windows-v2.0.0",
        notes,
        new Uri("https://github.com/example/NTranslate-2.0.0-win-x64-setup.exe"),
        "NTranslate-2.0.0-win-x64-setup.exe",
        new Uri("https://github.com/example/NTranslate-2.0.0-win-x64-setup.exe.sha256"),
        "NTranslate-2.0.0-win-x64-setup.exe.sha256");

    private static UpdateCoordinator Coordinator(IReadOnlyList<WindowsUpdate> updates) => new(
        new(1, 0, 0),
        _ => Task.FromResult(updates),
        (_, _, _, _) => Task.CompletedTask,
        new RejectingVerifier(),
        _ => { },
        () => { });

    private sealed class RecordingUpdateDialog(bool confirmInstall) : IUpdateDialog
    {
        public List<(UpdateState State, string? Message, string? ReleaseNotes)> States { get; } = [];
        public Task<bool> ShowAsync(UpdateState state, string? message, string? releaseNotes, CancellationToken token)
        {
            States.Add((state, message, releaseNotes));
            return Task.FromResult(confirmInstall && state == UpdateState.Available);
        }
    }

    private sealed class AcceptingVerifier : IInstallerChecksumVerifier
    {
        public Task<VerifiedInstaller> VerifyAsync(string installerPath, string checksumPath, string expectedInstallerName, SemanticVersion expectedVersion, CancellationToken token) =>
            Task.FromResult(new VerifiedInstaller(installerPath, expectedVersion));
    }

    private sealed class RejectingVerifier : IInstallerChecksumVerifier
    {
        public Task<VerifiedInstaller> VerifyAsync(string installerPath, string checksumPath, string expectedInstallerName, SemanticVersion expectedVersion, CancellationToken token) =>
            throw new InstallerVerificationException("invalid");
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"NTranslate-{Guid.NewGuid():N}");
        public TemporaryDirectory() => Directory.CreateDirectory(Path);
        public void Dispose() => Directory.Delete(Path, true);
    }
}
