using NTranslate.Platform.Diagnostics;

namespace NTranslate.App.Recovery;

public sealed class CrashExceptionEventArgs(Exception exception) : EventArgs
{
    public Exception Exception { get; } = exception;
}

public sealed class CrashTaskExceptionEventArgs(AggregateException exception) : EventArgs
{
    public AggregateException Exception { get; } = exception;
    public bool Observed { get; private set; }
    public void SetObserved() => Observed = true;
}

public interface IWinUiUnhandledExceptionSource { event EventHandler<CrashExceptionEventArgs>? UnhandledException; }
public interface IAppDomainUnhandledExceptionSource { event EventHandler<CrashExceptionEventArgs>? UnhandledException; }
public interface ITaskSchedulerUnobservedExceptionSource { event EventHandler<CrashTaskExceptionEventArgs>? UnobservedTaskException; }

public sealed class CrashHandlerRegistration(
    ICrashLogService crashLogs,
    IWinUiUnhandledExceptionSource winUi,
    IAppDomainUnhandledExceptionSource appDomain,
    ITaskSchedulerUnobservedExceptionSource taskScheduler) : IDisposable
{
    private int _registered;

    public void Register()
    {
        if (Interlocked.Exchange(ref _registered, 1) != 0) return;
        winUi.UnhandledException += OnUnhandled;
        appDomain.UnhandledException += OnUnhandled;
        taskScheduler.UnobservedTaskException += OnTaskUnhandled;
    }

    public void Dispose()
    {
        if (Interlocked.Exchange(ref _registered, 0) == 0) return;
        winUi.UnhandledException -= OnUnhandled;
        appDomain.UnhandledException -= OnUnhandled;
        taskScheduler.UnobservedTaskException -= OnTaskUnhandled;
    }

    private void OnUnhandled(object? sender, CrashExceptionEventArgs args) => Forget(crashLogs.RecordAsync(args.Exception));
    private void OnTaskUnhandled(object? sender, CrashTaskExceptionEventArgs args)
    {
        args.SetObserved();
        Forget(crashLogs.RecordAsync(args.Exception));
    }
    private static async void Forget(Task task)
    {
        try { await task.ConfigureAwait(false); }
        catch (Exception) { }
    }
}
