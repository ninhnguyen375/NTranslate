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
        var coordinator = Coordinator([], out _, out _);

        await coordinator.CheckAsync(manual: false, CancellationToken.None);

        Assert.Equal(UpdateState.Idle, coordinator.State);
        Assert.Null(coordinator.StatusMessage);
    }

    [Fact]
    public async Task ManualNoUpdateReportsCurrent()
    {
        var coordinator = Coordinator([], out _, out _);

        await coordinator.CheckAsync(manual: true, CancellationToken.None);

        Assert.Equal(UpdateState.Idle, coordinator.State);
        Assert.Equal("NTranslate is up to date.", coordinator.StatusMessage);
    }

    [Fact]
    public async Task AvailableUpdateExposesPlainTextNotes()
    {
        var update = new WindowsUpdate(new(2, 0, 0), "v2.0.0", "<script>alert(1)</script>\nnotes", new Uri("https://github.com/update.msix"), "NTranslate-2.0.0-win-x64.msix");
        var coordinator = Coordinator([update], out _, out _);

        await coordinator.CheckAsync(manual: true, CancellationToken.None);

        Assert.Equal(UpdateState.Available, coordinator.State);
        Assert.Equal("<script>alert(1)</script>\nnotes", coordinator.ReleaseNotes);
    }

    [Fact]
    public async Task PreventsDuplicateOperations()
    {
        var gate = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var checks = 0;
        var coordinator = new UpdateCoordinator(new(1, 0, 0), async token => { checks++; await gate.Task.WaitAsync(token); return []; }, (_, _, _) => Task.CompletedTask, new RejectingVerifier(), _ => { });

        var first = coordinator.CheckAsync(true, CancellationToken.None);
        var second = coordinator.CheckAsync(true, CancellationToken.None);
        gate.SetResult();
        await Task.WhenAll(first, second);

        Assert.Equal(1, checks);
    }

    [Fact]
    public async Task CancellationReturnsIdle()
    {
        var coordinator = new UpdateCoordinator(new(1, 0, 0), _ => throw new OperationCanceledException(), (_, _, _) => Task.CompletedTask, new RejectingVerifier(), _ => { });

        await coordinator.CheckAsync(true, CancellationToken.None);

        Assert.Equal(UpdateState.Idle, coordinator.State);
    }

    [Fact]
    public async Task InstallLaunchesOnlyVerifiedMsixWithShellExecute()
    {
        using var directory = new TemporaryDirectory();
        var update = new WindowsUpdate(new(2, 0, 0), "v2.0.0", "notes", new Uri("https://github.com/update.msix"), "NTranslate-2.0.0-win-x64.msix");
        ProcessStartInfo? launched = null;
        var coordinator = new UpdateCoordinator(new(1, 0, 0), _ => Task.FromResult<IReadOnlyList<WindowsUpdate>>([update]), async (_, path, _) => await File.WriteAllTextAsync(path, "package"), new AcceptingVerifier(), info => launched = info, directory.Path);
        await coordinator.CheckAsync(true, CancellationToken.None);
        await coordinator.InstallAsync(CancellationToken.None);

        Assert.NotNull(launched);
        Assert.True(launched.UseShellExecute);
        Assert.EndsWith(".msix", launched.FileName, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(UpdateState.Idle, coordinator.State);
    }

    [Fact]
    public async Task VerificationFailureNeverLaunchesInstaller()
    {
        using var directory = new TemporaryDirectory();
        var update = new WindowsUpdate(new(2, 0, 0), "v2.0.0", "notes", new Uri("https://github.com/update.msix"), "NTranslate-2.0.0-win-x64.msix");
        var launched = false;
        var coordinator = new UpdateCoordinator(new(1, 0, 0), _ => Task.FromResult<IReadOnlyList<WindowsUpdate>>([update]), async (_, path, _) => await File.WriteAllTextAsync(path, "package"), new RejectingVerifier(), _ => launched = true, directory.Path);
        await coordinator.CheckAsync(true, CancellationToken.None);

        await Assert.ThrowsAsync<MsixVerificationException>(() => coordinator.InstallAsync(CancellationToken.None));

        Assert.False(launched);
        Assert.Equal(UpdateState.Error, coordinator.State);
    }

    private static UpdateCoordinator Coordinator(IReadOnlyList<WindowsUpdate> updates, out bool downloaded, out bool launched)
    {
        var download = false;
        var launch = false;
        downloaded = download;
        launched = launch;
        return new(new(1, 0, 0), _ => Task.FromResult(updates), (_, _, _) => { download = true; return Task.CompletedTask; }, new RejectingVerifier(), _ => launch = true);
    }

    private sealed class AcceptingVerifier : IMsixPackageVerifier
    {
        public Task<VerifiedMsixPackage> VerifyAsync(string path, CancellationToken token) => Task.FromResult(new VerifiedMsixPackage(path, "NinhNguyen375.NTranslate", "CN=Ninh Nguyen", new(2, 0, 0), "x64"));
    }

    private sealed class RejectingVerifier : IMsixPackageVerifier
    {
        public Task<VerifiedMsixPackage> VerifyAsync(string path, CancellationToken token) => throw new MsixVerificationException("invalid");
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"NTranslate-{Guid.NewGuid():N}");
        public TemporaryDirectory() => Directory.CreateDirectory(Path);
        public void Dispose() => Directory.Delete(Path, true);
    }
}
