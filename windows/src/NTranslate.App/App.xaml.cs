using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;

namespace NTranslate.App;

/// <summary>
/// Composition root. Task 7 only proves the single-instance skeleton: a hidden window
/// (never activated, so no visible normal window on startup) and a seam for dispatching
/// redirected activations to a popup entry point. Task 9 wires the real popup/tray/hotkey
/// composition into <see cref="OnActivationDispatched"/>.
/// </summary>
public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        _window = new Window { Title = "NTranslate" };
        AppInstance.GetCurrent().Activated += (_, activatedArgs) => OnActivationDispatched(activatedArgs);
    }

    /// <summary>
    /// Stub seam for redirected activation reaching the primary instance. Deliberately a
    /// no-op until Task 9 composes the popup coordinator; must never log activation args
    /// (they may carry launch context derived from user selection/clipboard).
    /// </summary>
    private void OnActivationDispatched(AppActivationArguments activatedArgs)
    {
    }
}
