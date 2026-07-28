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
}
