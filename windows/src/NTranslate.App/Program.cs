using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using WinRT;

namespace NTranslate.App;

/// <summary>
/// Unpackaged entry point. Replaces WinUI's generated Main (see
/// <c>DISABLE_XAML_GENERATED_MAIN</c> in the csproj) so we can decide, before any UI
/// spins up, whether this process is the primary instance or should redirect
/// activation to an already-running one.
/// </summary>
public static class Program
{
    [STAThread]
    private static void Main(string[] _)
    {
        ComWrappersSupport.InitializeComWrappers();

        var activationArgs = AppInstance.GetCurrent().GetActivatedEventArgs();
        var keyedInstance = AppInstance.FindOrRegisterForKey("NTranslate.Primary");

        switch (ActivationPolicy.Decide(keyedInstance.IsCurrent))
        {
            case ActivationDecision.RedirectAndExit:
                keyedInstance.RedirectActivationToAsync(activationArgs).AsTask().GetAwaiter().GetResult();
                break;
            case ActivationDecision.StartPrimary:
            default:
                Application.Start(_ => new App());
                break;
        }
    }
}
