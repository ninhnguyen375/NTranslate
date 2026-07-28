using NTranslate.App.Recovery;
using NTranslate.Core.Configuration;
using NTranslate.Core.Recovery;

namespace NTranslate.App.Tests;

public sealed class RuntimeIntegrationTests
{
    [Fact]
    public async Task RuntimeSettingsApplyRollsBackWhenAnyStepFails()
    {
        var old = AppConfig.Default;
        var current = old;
        var startup = false;
        var apply = new RuntimeSettingsApplier(
            () => (current, startup),
            (config, _) => { current = config; return Task.CompletedTask; },
            (enabled, _) => { startup = enabled; throw new InvalidOperationException("startup failed"); });

        await Assert.ThrowsAsync<InvalidOperationException>(() => apply.ApplyRuntimeAsync(old with { SpeechRate = 1.2 }, 1.2, true, CancellationToken.None));

        Assert.Equal(old, current);
        Assert.False(startup);
    }

    [Fact]
    public async Task RecoveryDoesNotAcknowledgeWhenNoticeCannotComplete()
    {
        var logs = new FakeCrashLogs();
        var recovery = new RecoveryCoordinator(logs, new FailingNotice(), new FakeLauncher());

        await Assert.ThrowsAsync<InvalidOperationException>(() => recovery.ShowPendingAsync());

        Assert.False(logs.Acknowledged);
    }

    private sealed class FailingNotice : IRecoveryNotice
    {
        public Task<RecoveryNoticeChoice> ShowAsync(CrashLogSummary summary, CancellationToken token) => throw new InvalidOperationException("owner unavailable");
    }

    private sealed class FakeLauncher : ILogDirectoryLauncher
    {
        public Task OpenAsync(string path, CancellationToken token) => Task.CompletedTask;
    }

    private sealed class FakeCrashLogs : NTranslate.Platform.Diagnostics.ICrashLogService
    {
        public string LogsDirectory => "C:\\logs";
        public bool Acknowledged { get; private set; }
        public Task RecordAsync(Exception exception, CancellationToken token = default) => Task.CompletedTask;
        public Task<CrashLogSummary?> GetNewestUnacknowledgedAsync(CancellationToken token = default) => Task.FromResult<CrashLogSummary?>(new("crash.json", DateTimeOffset.UtcNow, "Error", "message", null));
        public Task AcknowledgeAsync(string fileName, CancellationToken token = default) { Acknowledged = true; return Task.CompletedTask; }
    }
}
