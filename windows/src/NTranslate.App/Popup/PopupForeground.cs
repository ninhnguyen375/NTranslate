using System.Runtime.InteropServices;

namespace NTranslate.App.Popup;

internal interface IPopupForegroundNative
{
    bool SetWindowPos(nint hwnd, nint insertAfter);
    bool SetForeground(nint hwnd);
}

internal sealed class PopupForeground(IPopupForegroundNative native)
{
    public void Raise(nint hwnd, Action activate)
    {
        activate();
        native.SetWindowPos(hwnd, 0);
        native.SetForeground(hwnd);
    }
}

internal sealed class Win32PopupForegroundNative : IPopupForegroundNative
{
    private const uint SwpNoMove = 0x0002;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoActivate = 0x0010;

    public bool SetWindowPos(nint hwnd, nint insertAfter) =>
        NativeSetWindowPos(hwnd, insertAfter, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpNoActivate);

    public bool SetForeground(nint hwnd) => SetForegroundWindow(hwnd);

    [DllImport("user32.dll", EntryPoint = "SetWindowPos", SetLastError = true)]
    private static extern bool NativeSetWindowPos(nint hwnd, nint insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(nint hwnd);
}
