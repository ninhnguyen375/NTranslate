using NTranslate.App.Popup;

namespace NTranslate.App.Tests.Popup;

public sealed class PopupForegroundTests
{
    [Theory]
    [InlineData(300, 200, 1000, 300)]
    [InlineData(300, 600, 1000, 600)]
    [InlineData(300, 900, 1000, 800)]
    [InlineData(900, 700, 500, 400)]
    public void ContentHeight_UsesConfiguredMinimumAndWorkAreaCap(
        int configuredHeight, int desiredHeight, int workAreaHeight, int expected)
    {
        Assert.Equal(expected, PopupCoordinator.CalculateHeight(configuredHeight, desiredHeight, workAreaHeight));
    }

    [Fact]
    public void TextGrowth_RequestsLargerHeightUpToWorkAreaCap()
    {
        var desiredHeight = TranslationWindow.CalculateDesiredContentHeight(
            chromeHeight: 100,
            sourceContentHeight: 900,
            resultContentHeight: 250);

        Assert.Equal(1250, desiredHeight);
        Assert.Equal(800, PopupCoordinator.CalculateHeight(300, (int)desiredHeight, 1000));
    }

    [Fact]
    public void TextShrink_ReducesDesiredHeightBackToConfiguredMinimum()
    {
        var longText = TranslationWindow.CalculateDesiredContentHeight(100, 900, 250);
        var shortText = TranslationWindow.CalculateDesiredContentHeight(100, 50, 50);

        Assert.Equal(800, PopupCoordinator.CalculateHeight(300, (int)longText, 1000));
        Assert.Equal(300, PopupCoordinator.CalculateHeight(300, (int)shortText, 1000));
    }

    [Fact]
    public void ContentResize_ClampsExistingWindowPositionToWorkArea()
    {
        var point = NTranslate.Platform.Windows.PopupPlacement.ClampToWorkArea(
            new(900, 700), new(300, 400), new(0, 0, 1000, 800));

        Assert.Equal(new NTranslate.Platform.Windows.ScreenPoint(700, 400), point);
    }

    [Fact]
    public void Raise_ActivatesThenRaisesInNormalZOrderBeforeRequestingForeground()
    {
        var calls = new List<string>();
        var native = new RecordingForegroundNative(calls);

        new PopupForeground(native).Raise((nint)42, () => calls.Add("activate"));

        Assert.Equal(["activate", "raise:42:0", "foreground:42"], calls);
    }

    [Fact]
    public void Raise_SetWindowPosFailureRemainsNonfatalAndStillRequestsForeground()
    {
        var calls = new List<string>();
        var native = new RecordingForegroundNative(calls, raiseSucceeds: false);

        var error = Record.Exception(() =>
            new PopupForeground(native).Raise((nint)42, () => calls.Add("activate")));

        Assert.Null(error);
        Assert.Equal(["activate", "raise:42:0", "foreground:42"], calls);
    }

    [Fact]
    public void SetTopmost_FailureIsReportedDeterministically()
    {
        var foreground = new PopupForeground(new RecordingForegroundNative([], raiseSucceeds: false));

        var exception = Assert.Throws<InvalidOperationException>(() => foreground.SetTopmost((nint)42, true));

        Assert.Contains("SetWindowPos", exception.Message, StringComparison.Ordinal);
    }

    [Theory]
    [InlineData(true, -1)]
    [InlineData(false, -2)]
    public void SetTopmost_UsesExplicitTopmostZOrder(bool isPinned, int expectedInsertAfter)
    {
        var calls = new List<string>();
        var foreground = new PopupForeground(new RecordingForegroundNative(calls));

        foreground.SetTopmost((nint)42, isPinned);

        Assert.Equal([$"raise:42:{expectedInsertAfter}"], calls);
    }

    [Fact]
    public void Raise_UnpinnedPopupUsesNormalZOrder()
    {
        var calls = new List<string>();
        var foreground = new PopupForeground(new RecordingForegroundNative(calls));
        foreground.SetTopmost((nint)42, false);
        calls.Clear();

        foreground.Raise((nint)42, () => calls.Add("activate"));

        Assert.Equal(["activate", "raise:42:0", "foreground:42"], calls);
    }

    private sealed class RecordingForegroundNative(List<string> calls, bool raiseSucceeds = true) : IPopupForegroundNative
    {
        public bool SetWindowPos(nint hwnd, nint insertAfter)
        {
            calls.Add($"raise:{hwnd}:{insertAfter}");
            return raiseSucceeds;
        }

        public bool SetForeground(nint hwnd)
        {
            calls.Add($"foreground:{hwnd}");
            return true;
        }
    }
}
