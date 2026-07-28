using NTranslate.App;
using NTranslate.Core.Configuration;
using NTranslate.Platform.Capture;

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

    [Theory]
    [InlineData(SelectionSource.UiAutomation, "selected", "selected")]
    [InlineData(SelectionSource.SimulatedCopy, "copied", "copied")]
    [InlineData(SelectionSource.Clipboard, "stale", null)]
    public void CaptureRouting_ForwardsOnlyConfirmedSelection(SelectionSource source, string text, string? expected)
    {
        Assert.Equal(expected, CaptureRouting.SourceText(new(text, source, null)));
    }

    [Fact]
    public void CaptureRouting_EmptyCaptureUsesManualEntry() =>
        Assert.Null(CaptureRouting.SourceText(null));

    [Fact]
    public void ClosePopup_InvalidatesBlockedCaptureBeforeLateCompletion()
    {
        var generation = new CaptureGeneration();
        var capture = generation.Begin();
        generation.Cancel();
        Assert.False(generation.IsCurrent(capture));
    }

    [Fact]
    public void PersistentGuidance_CombinesConfigAndHotkeyFailures()
    {
        Assert.Equal(
            "Configuration invalid. Global hotkey unavailable.",
            GuidancePolicy.Combine("Configuration invalid.", "RegisterHotKey failed (Win32 error 1409)."));
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
