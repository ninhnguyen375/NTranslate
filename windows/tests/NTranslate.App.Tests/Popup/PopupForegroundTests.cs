using NTranslate.App.Popup;

namespace NTranslate.App.Tests.Popup;

public sealed class PopupForegroundTests
{
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
