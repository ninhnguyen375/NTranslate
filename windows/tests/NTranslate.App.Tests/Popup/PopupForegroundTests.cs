using NTranslate.App.Popup;

namespace NTranslate.App.Tests.Popup;

public sealed class PopupForegroundTests
{
    [Fact]
    public void Raise_ActivatesThenTogglesTopmostBeforeRequestingForeground()
    {
        var calls = new List<string>();
        var native = new RecordingForegroundNative(calls);

        new PopupForeground(native).Raise((nint)42, () => calls.Add("activate"));

        Assert.Equal(["activate", "topmost", "not-topmost", "foreground"], calls);
    }

    [Fact]
    public void Raise_NativeFailuresRemainNonfatalAndAttemptEveryStep()
    {
        var calls = new List<string>();
        var native = new RecordingForegroundNative(calls, succeed: false);

        var error = Record.Exception(() =>
            new PopupForeground(native).Raise((nint)42, () => calls.Add("activate")));

        Assert.Null(error);
        Assert.Equal(["activate", "topmost", "not-topmost", "foreground"], calls);
    }

    private sealed class RecordingForegroundNative(List<string> calls, bool succeed = true) : IPopupForegroundNative
    {
        public bool SetTopmost(nint hwnd, bool topmost)
        {
            calls.Add(topmost ? "topmost" : "not-topmost");
            return succeed;
        }

        public bool SetForeground(nint hwnd)
        {
            calls.Add("foreground");
            return succeed;
        }
    }
}
