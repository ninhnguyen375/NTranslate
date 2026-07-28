using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace NTranslate.App;

/// <summary>Tray-only WinUI composition root.</summary>
public partial class App : Application
{
    private AppComposition? _composition;
    private readonly Queue<AppActivationArguments> _pendingActivations = [];

    public App()
    {
        InitializeComponent();
        AppInstance.GetCurrent().Activated += (_, activatedArgs) => OnActivationDispatched(activatedArgs);
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _composition = new AppComposition(Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
        _composition.Start();
        while (_pendingActivations.TryDequeue(out _))
            _composition.ShowManual();
    }

    private void OnActivationDispatched(AppActivationArguments activatedArgs)
    {
        if (_composition is null)
        {
            _pendingActivations.Enqueue(activatedArgs);
            return;
        }
        _composition.ShowManual();
    }
}
