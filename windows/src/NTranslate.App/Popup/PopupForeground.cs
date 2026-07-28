using System.Runtime.InteropServices;

namespace NTranslate.App.Popup;

internal interface IPopupForegroundNative
{
    bool SetTopmost(nint hwnd, bool topmost);
    bool SetForeground(nint hwnd);
}

internal sealed class PopupForeground(IPopupForegroundNative native)
{
    public void Raise(nint hwnd, Action activate)
    {
        activate();
        native.SetTopmost(hwnd, true);
        native.SetTopmost(hwnd, false);
        native.SetForeground(hwnd);
    }
}

internal sealed class Win32PopupForegroundNative : IPopupForegroundNative
{
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoActivate = 0x0010;

    public bool SetTopmost(nint hwnd, bool topmost) =>
        SetWindowPos(hwnd, topmost ? new(-1) : new(-2), 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate);

    public bool SetForeground(nint hwnd) => SetForegroundWindow(hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(nint hwnd, nint insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(nint hwnd);
}
