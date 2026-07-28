using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace NTranslate.App;

/// <summary>Tray-only WinUI composition root.</summary>
public partial class App : Application
{
    private AppComposition? _composition;
    private readonly UiActivationGate _activationGate;

    internal XamlRoot? ContentRoot => _composition?.ContentRoot;

    public App()
    {
        InitializeComponent();
        _activationGate = new UiActivationGate(Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread(), () => _composition!.ShowManual());
        AppInstance.GetCurrent().Activated += (_, _) => _activationGate.Activate();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _composition = new AppComposition(Microsoft.UI.Dispatching.DispatcherQueue.GetForCurrentThread());
        _composition.Start();
        _activationGate.Ready();
    }
}
