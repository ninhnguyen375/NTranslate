namespace NTranslate.App;

public enum ActivationDecision
{
    StartPrimary,
    RedirectAndExit,
}

/// <summary>
/// Pure decision logic for single-instance startup routing. Kept free of
/// <c>Microsoft.Windows.AppLifecycle</c> types so it is unit-testable without OS-level
/// app registration; <see cref="Program"/> is a thin wrapper around this decision.
/// </summary>
public static class ActivationPolicy
{
    public static ActivationDecision Decide(bool isCurrent) =>
        isCurrent ? ActivationDecision.StartPrimary : ActivationDecision.RedirectAndExit;
}
