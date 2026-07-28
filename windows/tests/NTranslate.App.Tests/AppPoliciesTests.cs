using NTranslate.App;
using NTranslate.Core.Configuration;

namespace NTranslate.App.Tests;

public sealed class AppPoliciesTests
{
    [Fact]
    public void ManualActivation_CancelsCaptureBeforeShowing()
    {
        var calls = new List<string>();
        var router = new PopupRouter(() => calls.Add("cancel"), () => calls.Add("show"));
        router.ShowManual();
        Assert.Equal(["cancel", "show"], calls);
    }

    [Fact]
    public void ActivationGate_DrainsQueuedActivationOnceReady()
    {
        var shown = 0;
        var gate = new ActivationGate(() => shown++);
        gate.Activate();
        gate.Ready();
        gate.Ready();
        Assert.Equal(1, shown);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("{broken")]
    [InlineData("{\"apiKey\":\"secret\"}")]
    public void ConfigStartupPolicy_FallsBackWithSafeGuidance(string? json)
    {
        var result = ConfigStartupPolicy.Resolve(json, "config.json");
        Assert.Equal(AppConfig.Default, result.Config);
        Assert.NotNull(result.Guidance);
        Assert.DoesNotContain("secret", result.Guidance, StringComparison.Ordinal);
    }
}
