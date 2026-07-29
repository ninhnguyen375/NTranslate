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
    [InlineData(SelectionSource.Clipboard, "clipboard fallback", "clipboard fallback")]
    public void CaptureRouting_ForwardsCapturedText(SelectionSource source, string text, string? expected)
    {
        Assert.Equal(expected, CaptureRouting.SourceText(new(text, source, null)));
    }

    [Fact]
    public void CaptureRouting_ResolvesTextImageAndEmptyCaptures()
    {
        Assert.Equal(PopupCaptureKind.Text, CaptureRouting.Resolve(new("hello", null, SelectionSource.UiAutomation, null)).Kind);
        Assert.Equal(PopupCaptureKind.Image, CaptureRouting.Resolve(new(null, [1, 2, 3], SelectionSource.Clipboard, null)).Kind);
        Assert.Equal(PopupCaptureKind.Empty, CaptureRouting.Resolve(null).Kind);
        Assert.Equal(PopupCaptureKind.Empty, CaptureRouting.Resolve(new(null, null, SelectionSource.Clipboard, "diagnostic")).Kind);
    }

    [Fact]
    public void PopupRequestPolicy_MapsCaptureKindsToActions()
    {
        Assert.Equal(PopupRequestAction.ShowAndTranslateText, PopupRequestPolicy.Resolve(CaptureRouting.Resolve(new("hello", null, SelectionSource.UiAutomation, null))));
        Assert.Equal(PopupRequestAction.ShowAndTranslateImage, PopupRequestPolicy.Resolve(CaptureRouting.Resolve(new(null, [1, 2, 3], SelectionSource.Clipboard, null))));
        Assert.Equal(PopupRequestAction.ShowManual, PopupRequestPolicy.Resolve(CaptureRouting.Resolve(null)));
        Assert.Equal(PopupRequestAction.ShowManual, PopupRequestPolicy.Resolve(CaptureRouting.Resolve(new("  ", null, SelectionSource.Clipboard, null))));
    }

    [Fact]
    public void PopupRequestDispatcher_InvalidatesSynchronouslyThenDispatchesExactlyOneAction()
    {
        var calls = new List<string>();
        Action? queued = null;
        var dispatcher = new PopupRequestDispatcher(
            () => calls.Add("invalidate"),
            action => queued = action,
            () => calls.Add("manual"),
            (text, _) => { calls.Add($"text:{text}"); return Task.CompletedTask; },
            (image, _) => { calls.Add($"image:{image.Length}"); return Task.CompletedTask; });

        dispatcher.Invalidate();
        dispatcher.Enqueue(CaptureRouting.Resolve(new("hello", null, SelectionSource.UiAutomation, null)), () => true, CancellationToken.None);

        Assert.Equal(["invalidate"], calls);
        queued!();
        Assert.Equal(["invalidate", "text:hello"], calls);
    }

    [Fact]
    public void PopupRequestDispatcher_IgnoresStaleDispatchAndRoutesManualAndImageOnce()
    {
        var calls = new List<string>();
        var queued = new Queue<Action>();
        var dispatcher = new PopupRequestDispatcher(
            () => calls.Add("invalidate"),
            queued.Enqueue,
            () => calls.Add("manual"),
            (text, _) => { calls.Add($"text:{text}"); return Task.CompletedTask; },
            (image, _) => { calls.Add($"image:{image.Length}"); return Task.CompletedTask; });

        dispatcher.Enqueue(CaptureRouting.Resolve(new("stale", null, SelectionSource.UiAutomation, null)), () => false, CancellationToken.None);
        dispatcher.Enqueue(CaptureRouting.Resolve(null), () => true, CancellationToken.None);
        dispatcher.Enqueue(CaptureRouting.Resolve(new(null, [1, 2, 3], SelectionSource.Clipboard, null)), () => true, CancellationToken.None);
        while (queued.TryDequeue(out var action)) action();

        Assert.Equal(["manual", "image:3"], calls);
    }

    [Fact]
    public void CaptureRouting_EmptyOrMissingCaptureUsesManualEntry()
    {
        Assert.Null(CaptureRouting.SourceText(new(string.Empty, null, SelectionSource.Clipboard, null)));
        Assert.Null(CaptureRouting.SourceText(null));
    }

    [Fact]
    public void ClosePopup_InvalidatesBlockedCaptureBeforeLateCompletion()
    {
        var generation = new CaptureGeneration();
        var capture = generation.Begin();
        generation.Cancel();
        Assert.False(generation.IsCurrent(capture));
    }

    [Fact]
    public async Task EventBoundarySwallowsCancellationOnly()
    {
        await EventBoundary.IgnoreCancellation(() => Task.FromException(new OperationCanceledException()));

        await Assert.ThrowsAsync<IOException>(() => EventBoundary.IgnoreCancellation(() => Task.FromException(new IOException("failed"))));
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
