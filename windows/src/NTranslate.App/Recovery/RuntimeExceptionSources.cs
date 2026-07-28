using Microsoft.UI.Xaml;

namespace NTranslate.App.Recovery;

internal sealed class WinUiUnhandledExceptionSource : IWinUiUnhandledExceptionSource, IDisposable
{
    private readonly Application _application;
    public WinUiUnhandledExceptionSource(Application application)
    {
        _application = application;
        _application.UnhandledException += OnUnhandled;
    }
    public event EventHandler<CrashExceptionEventArgs>? UnhandledException;
    public void Dispose() => _application.UnhandledException -= OnUnhandled;
    private void OnUnhandled(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs args) => UnhandledException?.Invoke(this, new(args.Exception));
}

internal sealed class AppDomainUnhandledExceptionSource : IAppDomainUnhandledExceptionSource, IDisposable
{
    public AppDomainUnhandledExceptionSource() => AppDomain.CurrentDomain.UnhandledException += OnUnhandled;
    public event EventHandler<CrashExceptionEventArgs>? UnhandledException;
    public void Dispose() => AppDomain.CurrentDomain.UnhandledException -= OnUnhandled;
    private void OnUnhandled(object sender, System.UnhandledExceptionEventArgs args)
    {
        if (args.ExceptionObject is Exception exception) UnhandledException?.Invoke(this, new(exception));
    }
}

internal sealed class TaskSchedulerUnobservedExceptionSource : ITaskSchedulerUnobservedExceptionSource, IDisposable
{
    public TaskSchedulerUnobservedExceptionSource() => TaskScheduler.UnobservedTaskException += OnUnhandled;
    public event EventHandler<CrashTaskExceptionEventArgs>? UnobservedTaskException;
    public void Dispose() => TaskScheduler.UnobservedTaskException -= OnUnhandled;
    private void OnUnhandled(object? sender, UnobservedTaskExceptionEventArgs args)
    {
        var forwarded = new CrashTaskExceptionEventArgs(args.Exception);
        UnobservedTaskException?.Invoke(this, forwarded);
        if (forwarded.Observed) args.SetObserved();
    }
}
