namespace NTranslate.App;

public enum ActivationDecision
{
    StartPrimary,
    RedirectAndExit,
}

/// <summary>
/// Reasons startup can fail before any UI exists.
/// </summary>
public enum StartupFailure
{
    /// <summary>AppInstance.FindOrRegisterForKey threw (e.g. transient AppLifecycle/COM failure).</summary>
    RegistrationFailed,

    /// <summary>RedirectActivationToAsync threw while handing off to the primary instance.</summary>
    RedirectFailed,
}

/// <summary>
/// Pure decision logic for single-instance startup routing. Kept free of
/// <c>Microsoft.Windows.AppLifecycle</c> types so it is unit-testable without OS-level
/// app registration; <see cref="Program"/> is a thin wrapper around this decision.
/// </summary>
public static class ActivationPolicy
{
    public const int RegistrationFailedExitCode = 1;

    /// <summary>
    /// Redirect failure exits rather than falling through to start a second primary
    /// instance: two tray icons fighting over the same hotkey registration is worse
    /// than a second launch silently doing nothing.
    /// </summary>
    public const int RedirectFailedExitCode = 2;

    public static ActivationDecision Decide(bool isCurrent) =>
        isCurrent ? ActivationDecision.StartPrimary : ActivationDecision.RedirectAndExit;

    public static int GetExitCode(StartupFailure failure) => failure switch
    {
        StartupFailure.RegistrationFailed => RegistrationFailedExitCode,
        StartupFailure.RedirectFailed => RedirectFailedExitCode,
        _ => 1,
    };
}
