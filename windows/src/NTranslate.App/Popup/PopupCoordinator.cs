using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using NTranslate.Platform.Windows;
using WinRT.Interop;

namespace NTranslate.App.Popup;

internal sealed class PopupCoordinator
{
    private readonly Window _window;
    private readonly AppWindow _appWindow;
    private readonly PopupLifecycle _lifecycle;
    private readonly PopupForeground _foreground = new(new Win32PopupForegroundNative());
    private readonly double _width;
    private readonly double _height;

    public PopupCoordinator(Window window, TranslationViewModel viewModel, double width, double height, Action cancelWork)
    {
        _window = window;
        var hwnd = WindowNative.GetWindowHandle(window);
        _appWindow = AppWindow.GetFromWindowId(Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd));
        _width = width;
        _height = height;
        var dpi = GetDpiForWindow(hwnd);
        var size = PopupPlacement.ToPhysicalPixels(width, height, dpi);
        _appWindow.Resize(new(size.Width, size.Height));
        _lifecycle = new PopupLifecycle(cancelWork, _appWindow.Hide);
    }

    public bool IsPinned { get => _lifecycle.IsPinned; set => _lifecycle.IsPinned = value; }

    public void Show(string? sourceText)
    {
        if (sourceText is not null)
            ((TranslationWindow)_window).ViewModel.SourceText = sourceText;

        var hwnd = WindowNative.GetWindowHandle(_window);
        GetCursorPos(out var cursor);
        var monitor = MonitorFromPoint(cursor, MonitorDefaultToNearest);
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(monitor, ref info))
            throw new InvalidOperationException($"GetMonitorInfo failed (Win32 error {Marshal.GetLastPInvokeError()}).");
        var dpi = GetDpiForMonitor(monitor);
        var size = PopupPlacement.ToPhysicalPixels(_width, _height, dpi);
        _appWindow.Resize(new(size.Width, size.Height));
        var point = PopupPlacement.Place(
            new(cursor.X, cursor.Y), size,
            new(info.Work.Left, info.Work.Top, info.Work.Right, info.Work.Bottom));
        _appWindow.Move(new(point.X, point.Y));
        _foreground.Raise(hwnd, _window.Activate);
    }

    public void Close() => _lifecycle.Close();
    public void Deactivate() => _lifecycle.Deactivate();
    public void Drag() => _lifecycle.Drag();
    public void RestoreWindowProcedure() { }

    private const uint MonitorDefaultToNearest = 2;
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int X; public int Y; }
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public Rect Monitor; public Rect Work; public uint Flags; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern nint MonitorFromPoint(Point point, uint flags);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool GetMonitorInfo(nint monitor, ref MonitorInfo info);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(nint hwnd);
    [DllImport("shcore.dll")] private static extern int GetDpiForMonitor(nint monitor, int type, out uint dpiX, out uint dpiY);

    private static uint GetDpiForMonitor(nint monitor) =>
        GetDpiForMonitor(monitor, 0, out var dpi, out _) == 0 ? dpi : 96;
}
