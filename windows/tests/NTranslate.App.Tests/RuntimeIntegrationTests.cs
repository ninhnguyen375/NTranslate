using NTranslate.App.Recovery;
using NTranslate.Core.Configuration;
using NTranslate.Core.Recovery;
using NTranslate.Core.Settings;

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
            (enabled, _) => { startup = enabled; return enabled ? Task.FromException(new InvalidOperationException("startup failed")) : Task.CompletedTask; });

        await Assert.ThrowsAsync<InvalidOperationException>(() => apply.ApplyRuntimeAsync(old with { SpeechRate = 1.2 }, 1.2, true, CancellationToken.None));

        Assert.Equal(old, current);
        Assert.False(startup);
    }

    [Fact]
    public async Task RuntimeSettingsApplySkipsUnchangedConfigAndStartup()
    {
        var current = AppConfig.Default;
        var configCalls = 0;
        var startupCalls = 0;
        var apply = new RuntimeSettingsApplier(
            () => (current, current.StartWithWindows),
            (_, _) => { configCalls++; throw new InvalidOperationException("config should not run"); },
            (_, _) => { startupCalls++; throw new InvalidOperationException("startup should not run"); });

        await apply.ApplyRuntimeAsync(current, current.SpeechRate, current.StartWithWindows, CancellationToken.None);

        Assert.Equal(0, configCalls);
        Assert.Equal(0, startupCalls);
    }

    [Fact]
    public async Task RuntimeSettingsApplySkipsUnchangedStartupWhenConfigChanges()
    {
        var current = AppConfig.Default;
        var startupCalls = 0;
        var apply = new RuntimeSettingsApplier(
            () => (current, current.StartWithWindows),
            (config, _) => { current = config; return Task.CompletedTask; },
            (_, _) => { startupCalls++; throw new InvalidOperationException("startup should not run"); });

        await apply.ApplyRuntimeAsync(current with { Model = "changed" }, current.SpeechRate, current.StartWithWindows, CancellationToken.None);

        Assert.Equal("changed", current.Model);
        Assert.Equal(0, startupCalls);
    }

    [Fact]
    public async Task RuntimeSettingsApplyAttemptsEveryRollbackAndPreservesPrimaryFailure()
    {
        var old = AppConfig.Default;
        var current = old;
        var startup = false;
        var configCalls = 0;
        var startupCalls = 0;
        var apply = new RuntimeSettingsApplier(
            () => (current, startup),
            (config, _) =>
            {
                configCalls++;
                if (configCalls == 2) throw new IOException("config rollback failed");
                current = config;
                return Task.CompletedTask;
            },
            (enabled, _) =>
            {
                startupCalls++;
                startup = enabled;
                if (startupCalls == 1) throw new InvalidOperationException("startup failed");
                return Task.CompletedTask;
            });

        var exception = await Assert.ThrowsAsync<SettingsCommitException>(() =>
            apply.ApplyRuntimeAsync(old with { Model = "changed" }, old.SpeechRate, true, CancellationToken.None));

        Assert.Equal("startup failed", exception.PrimaryException.Message);
        Assert.Equal(["config rollback failed"], exception.RollbackExceptions.Select(error => error.Message));
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
