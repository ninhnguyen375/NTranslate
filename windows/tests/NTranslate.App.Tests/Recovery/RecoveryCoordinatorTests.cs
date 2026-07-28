using NTranslate.App.Recovery;
using NTranslate.Core.Recovery;
using NTranslate.Platform.Diagnostics;

namespace NTranslate.App.Tests.Recovery;

public sealed class RecoveryCoordinatorTests
{
    [Fact]
    public async Task Shows_one_notice_opens_logs_when_requested_then_acknowledges()
    {
        var log = new CrashLogSummary("crash-new.json", DateTimeOffset.UtcNow, "System.Exception", "failure", null);
        var service = new FakeCrashLogService(log);
        var notice = new FakeNotice(RecoveryNoticeChoice.OpenLogs);
        var launcher = new FakeLauncher();
        var coordinator = new RecoveryCoordinator(service, notice, launcher);

        await coordinator.ShowPendingAsync(CancellationToken.None);
        await coordinator.ShowPendingAsync(CancellationToken.None);

        Assert.Equal(1, notice.ShowCount);
        Assert.Equal(service.LogsDirectory, launcher.OpenedPath);
        Assert.Equal(log.FileName, service.AcknowledgedFileName);
    }

    [Fact]
    public async Task Dispatches_notice_before_acknowledging()
    {
        var log = new CrashLogSummary("crash-new.json", DateTimeOffset.UtcNow, "System.Exception", "failure", null);
        var service = new FakeCrashLogService(log);
        var notice = new FakeNotice(RecoveryNoticeChoice.Dismiss);
        var dispatched = false;
        var coordinator = new RecoveryCoordinator(
            service,
            notice,
            new FakeLauncher(),
            async show =>
            {
                dispatched = true;
                return await show();
            });

        await coordinator.ShowPendingAsync(CancellationToken.None);

        Assert.True(dispatched);
        Assert.Equal(log.FileName, service.AcknowledgedFileName);
    }

    [Fact]
    public async Task Notice_failure_is_observed_and_not_acknowledged()
    {
        var log = new CrashLogSummary("crash-new.json", DateTimeOffset.UtcNow, "System.Exception", "failure", null);
        var service = new FakeCrashLogService(log);
        var coordinator = new RecoveryCoordinator(
            service,
            new ThrowingNotice(),
            new FakeLauncher(),
            show => show());

        await Assert.ThrowsAsync<InvalidOperationException>(() => coordinator.ShowPendingAsync(CancellationToken.None));

        Assert.Null(service.AcknowledgedFileName);
    }

    [Fact]
    public async Task Registers_all_exception_sources_and_marks_task_observed()
    {
        var service = new FakeCrashLogService(null);
        var winUi = new FakeWinUiSource();
        var appDomain = new FakeAppDomainSource();
        var scheduler = new FakeTaskSchedulerSource();
        using var registration = new CrashHandlerRegistration(service, winUi, appDomain, scheduler);
        registration.Register();

        winUi.Raise(new Exception("winui"));
        appDomain.Raise(new Exception("domain"));
        var task = scheduler.Raise(new AggregateException("task"));
        await service.Recorded.Task.WaitAsync(TimeSpan.FromSeconds(5));

        Assert.Equal(3, service.RecordCount);
        Assert.True(task.Observed);
    }

    private sealed class FakeCrashLogService(CrashLogSummary? pending) : ICrashLogService
    {
        public string LogsDirectory => "C:\\Logs";
        public string? AcknowledgedFileName { get; private set; }
        public int RecordCount;
        public TaskCompletionSource Recorded { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task RecordAsync(Exception exception, CancellationToken token = default)
        {
            if (Interlocked.Increment(ref RecordCount) == 3) Recorded.TrySetResult();
            return Task.CompletedTask;
        }
        public Task<CrashLogSummary?> GetNewestUnacknowledgedAsync(CancellationToken token = default) => Task.FromResult(pending);
        public Task AcknowledgeAsync(string fileName, CancellationToken token = default)
        {
            AcknowledgedFileName = fileName;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeNotice(RecoveryNoticeChoice choice) : IRecoveryNotice
    {
        public int ShowCount { get; private set; }
        public Task<RecoveryNoticeChoice> ShowAsync(CrashLogSummary summary, CancellationToken token)
        {
            ShowCount++;
            return Task.FromResult(choice);
        }
    }

    private sealed class ThrowingNotice : IRecoveryNotice
    {
        public Task<RecoveryNoticeChoice> ShowAsync(CrashLogSummary summary, CancellationToken token) =>
            Task.FromException<RecoveryNoticeChoice>(new InvalidOperationException("dialog failed"));
    }

    private sealed class FakeLauncher : ILogDirectoryLauncher
    {
        public string? OpenedPath { get; private set; }
        public Task OpenAsync(string path, CancellationToken token)
        {
            OpenedPath = path;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeWinUiSource : IWinUiUnhandledExceptionSource
    {
        public event EventHandler<CrashExceptionEventArgs>? UnhandledException;
        public void Raise(Exception error) => UnhandledException?.Invoke(this, new(error));
    }

    private sealed class FakeAppDomainSource : IAppDomainUnhandledExceptionSource
    {
        public event EventHandler<CrashExceptionEventArgs>? UnhandledException;
        public void Raise(Exception error) => UnhandledException?.Invoke(this, new(error));
    }

    private sealed class FakeTaskSchedulerSource : ITaskSchedulerUnobservedExceptionSource
    {
        public event EventHandler<CrashTaskExceptionEventArgs>? UnobservedTaskException;
        public CrashTaskExceptionEventArgs Raise(AggregateException error)
        {
            var args = new CrashTaskExceptionEventArgs(error);
            UnobservedTaskException?.Invoke(this, args);
            return args;
        }
    }
}
