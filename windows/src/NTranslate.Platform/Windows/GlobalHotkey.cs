using System.Runtime.InteropServices;
using NTranslate.Core.Configuration;

namespace NTranslate.Platform.Windows;

[Flags]
internal enum HotkeyModifiers : uint
{
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    NoRepeat = 0x4000
}

internal delegate nint WindowProcedure(nint window, uint message, nint wParam, nint lParam);

internal interface INativeWindowApi
{
    nint SetWindowProcedure(nint window, WindowProcedure procedure);
    void RestoreWindowProcedure(nint window, nint procedure);
    nint CallWindowProcedure(nint procedure, nint window, uint message, nint wParam, nint lParam);
    bool RegisterHotkey(nint window, nint id, HotkeyModifiers modifiers, uint virtualKey);
    bool UnregisterHotkey(nint window, nint id);
    int GetLastError();
}

internal sealed class NativeWindowApi : INativeWindowApi
{
    public nint SetWindowProcedure(nint window, WindowProcedure procedure) => SetWindowLongPtr(window, -4, Marshal.GetFunctionPointerForDelegate(procedure));
    public void RestoreWindowProcedure(nint window, nint procedure) => SetWindowLongPtr(window, -4, procedure);
    public nint CallWindowProcedure(nint procedure, nint window, uint message, nint wParam, nint lParam) => CallWindowProc(procedure, window, message, wParam, lParam);
    public bool RegisterHotkey(nint window, nint id, HotkeyModifiers modifiers, uint virtualKey) => RegisterHotKey(window, id, (uint)modifiers, virtualKey);
    public bool UnregisterHotkey(nint window, nint id) => UnregisterHotKey(window, id);
    public int GetLastError() => Marshal.GetLastWin32Error();

    [DllImport("user32.dll", SetLastError = true)] private static extern nint SetWindowLongPtr(nint hWnd, int nIndex, nint dwNewLong);
    [DllImport("user32.dll")] private static extern nint CallWindowProc(nint lpPrevWndFunc, nint hWnd, uint msg, nint wParam, nint lParam);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(nint hWnd, nint id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(nint hWnd, nint id);
}

public sealed record HotkeyRegistrationResult(bool IsRegistered, string? Error);

public interface IGlobalHotkey : IDisposable
{
    event EventHandler? Pressed;
    HotkeyRegistrationResult Register(HotkeyConfig config);
    void Unregister();
}

internal readonly record struct ParsedHotkey(HotkeyModifiers Modifiers, uint VirtualKey);

internal sealed class WindowMessageRouter : IDisposable
{
    internal const uint WmHotkey = 0x0312;

    private readonly nint _window;
    private readonly INativeWindowApi _native;
    private readonly WindowProcedure _procedure;
    private readonly nint _previousProcedure;
    private bool _disposed;

    public event EventHandler<WindowMessageEventArgs>? MessageReceived;

    internal nint Window => _window;

    public WindowMessageRouter(nint window, INativeWindowApi native)
    {
        if (window == 0) throw new ArgumentOutOfRangeException(nameof(window));
        _window = window;
        _native = native ?? throw new ArgumentNullException(nameof(native));
        _procedure = ProcessMessage;
        _previousProcedure = _native.SetWindowProcedure(window, _procedure);
        if (_previousProcedure == 0)
            throw new InvalidOperationException($"SetWindowLongPtr failed (Win32 error {_native.GetLastError()}).");
    }

    internal nint Dispatch(uint message, nint wParam, nint lParam) => ProcessMessage(_window, message, wParam, lParam);

    public void Dispose()
    {
        if (_disposed) return;
        _native.RestoreWindowProcedure(_window, _previousProcedure);
        _disposed = true;
        GC.SuppressFinalize(this);
    }

    private nint ProcessMessage(nint window, uint message, nint wParam, nint lParam)
    {
        MessageReceived?.Invoke(this, new(message, wParam, lParam));
        return _native.CallWindowProcedure(_previousProcedure, window, message, wParam, lParam);
    }
}

internal sealed class WindowMessageEventArgs(uint message, nint wParam, nint lParam) : EventArgs
{
    public uint Message { get; } = message;
    public nint WParam { get; } = wParam;
    public nint LParam { get; } = lParam;
}

public sealed class GlobalHotkey : IGlobalHotkey
{
    private const nint Id = 0x4E54;
    private readonly WindowMessageRouter _router;
    private readonly INativeWindowApi _native;
    private readonly bool _ownsRouter;
    private bool _registered;
    private bool _disposed;

    public GlobalHotkey(nint window)
    {
        _native = new NativeWindowApi();
        _router = new WindowMessageRouter(window, _native);
        _ownsRouter = true;
        _router.MessageReceived += HandleMessage;
    }

    internal GlobalHotkey(WindowMessageRouter router, INativeWindowApi native)
    {
        _router = router ?? throw new ArgumentNullException(nameof(router));
        _native = native ?? throw new ArgumentNullException(nameof(native));
        _router.MessageReceived += HandleMessage;
    }

    public event EventHandler? Pressed;

    public HotkeyRegistrationResult Register(HotkeyConfig config)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var parsed = Parse(config);
        Unregister();
        if (_native.RegisterHotkey(_router.Window, Id, parsed.Modifiers | HotkeyModifiers.NoRepeat, parsed.VirtualKey))
        {
            _registered = true;
            return new(true, null);
        }

        return new(false, $"RegisterHotKey failed (Win32 error {_native.GetLastError()}).");
    }

    public void Unregister()
    {
        if (!_registered) return;
        _native.UnregisterHotkey(_router.Window, Id);
        _registered = false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        Unregister();
        _router.MessageReceived -= HandleMessage;
        if (_ownsRouter) _router.Dispose();
        _disposed = true;
        GC.SuppressFinalize(this);
    }

    internal static ParsedHotkey Parse(HotkeyConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        if (config.Command)
            throw new ArgumentException("Hotkey.Command is not supported on Windows.");
        if (string.IsNullOrEmpty(config.Key) || config.Key.Length != 1 || !char.IsAsciiLetter(config.Key[0]))
            throw new ArgumentException("Hotkey.Key must be one letter A-Z.");

        var modifiers = (config.Option ? HotkeyModifiers.Alt : 0) |
                        (config.Control ? HotkeyModifiers.Control : 0) |
                        (config.Shift ? HotkeyModifiers.Shift : 0);
        if (modifiers == 0)
            throw new ArgumentException("Hotkey.Modifiers requires Option, Control, or Shift.");

        return new(modifiers, char.ToUpperInvariant(config.Key[0]));
    }

    private void HandleMessage(object? sender, WindowMessageEventArgs message)
    {
        if (message.Message == WindowMessageRouter.WmHotkey && message.WParam == Id)
            Pressed?.Invoke(this, EventArgs.Empty);
    }

}
