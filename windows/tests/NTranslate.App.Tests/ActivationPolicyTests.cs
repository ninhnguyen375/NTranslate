using NTranslate.App;

namespace NTranslate.App.Tests;

public class ActivationPolicyTests
{
    [Fact]
    public void Decide_WhenCurrentInstanceIsPrimary_StartsPrimary()
    {
        Assert.Equal(ActivationDecision.StartPrimary, ActivationPolicy.Decide(isCurrent: true));
    }

    [Fact]
    public void Decide_WhenAnotherInstanceOwnsTheKey_RedirectsAndExits()
    {
        Assert.Equal(ActivationDecision.RedirectAndExit, ActivationPolicy.Decide(isCurrent: false));
    }

    [Fact]
    public void GetExitCode_WhenRegistrationFailed_ReturnsRegistrationExitCode()
    {
        Assert.Equal(
            ActivationPolicy.RegistrationFailedExitCode,
            ActivationPolicy.GetExitCode(StartupFailure.RegistrationFailed));
    }

    [Fact]
    public void GetExitCode_WhenRedirectFailed_ReturnsRedirectExitCode()
    {
        Assert.Equal(
            ActivationPolicy.RedirectFailedExitCode,
            ActivationPolicy.GetExitCode(StartupFailure.RedirectFailed));
    }

    [Fact]
    public void ExitCodes_AreDistinct()
    {
        Assert.NotEqual(ActivationPolicy.RegistrationFailedExitCode, ActivationPolicy.RedirectFailedExitCode);
    }
}
