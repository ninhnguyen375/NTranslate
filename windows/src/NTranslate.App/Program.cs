using System;
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
    private static int Main(string[] _)
    {
        ComWrappersSupport.InitializeComWrappers();

        var activationArgs = AppInstance.GetCurrent().GetActivatedEventArgs();

        AppInstance keyedInstance;
        try
        {
            keyedInstance = AppInstance.FindOrRegisterForKey("NTranslate.Primary");
        }
        catch (Exception ex)
        {
            // We can't tell whether this process is the primary instance, so there is
            // no safe fallback other than a fatal, diagnosable exit.
            Console.Error.WriteLine($"NTranslate: single-instance registration failed: {ex}");
            return ActivationPolicy.GetExitCode(StartupFailure.RegistrationFailed);
        }

        switch (ActivationPolicy.Decide(keyedInstance.IsCurrent))
        {
            case ActivationDecision.RedirectAndExit:
                try
                {
                    keyedInstance.RedirectActivationToAsync(activationArgs).AsTask().GetAwaiter().GetResult();
                }
                catch (Exception ex)
                {
                    // Prefer exiting over falling through to start a second primary
                    // instance here: two tray icons fighting over the same hotkey is
                    // worse than this launch silently doing nothing.
                    Console.Error.WriteLine($"NTranslate: activation redirect failed: {ex}");
                    return ActivationPolicy.GetExitCode(StartupFailure.RedirectFailed);
                }
                break;
            case ActivationDecision.StartPrimary:
            default:
                Application.Start(_ => new App());
                break;
        }

        return 0;
    }
}
