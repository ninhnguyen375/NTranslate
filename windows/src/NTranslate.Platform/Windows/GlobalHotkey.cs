using System.Runtime.InteropServices;
using NTranslate.Core.Configuration;

namespace NTranslate.Platform.Windows;

[Flags]
internal enum HotkeyModifiers : uint { Alt = 1, Control = 2, Shift = 4, NoRepeat = 0x4000 }

public sealed record HotkeyRegistrationResult(bool IsRegistered, string? Error);
public sealed class HotkeyOperationException(string message) : InvalidOperationException(message);
public interface IGlobalHotkey : IDisposable
{
    event EventHandler? Pressed;
    HotkeyRegistrationResult Register(HotkeyConfig config);
    void Unregister();
}

internal readonly record struct ParsedHotkey(HotkeyModifiers Modifiers, uint VirtualKey);
internal static class WindowsHotkeyValidation
{
    internal static ParsedHotkey Parse(HotkeyConfig config)
    {
        ArgumentNullException.ThrowIfNull(config);
        if (config.Command) throw new ArgumentException("Hotkey.Command is not supported on Windows.");
        if (string.IsNullOrEmpty(config.Key) || config.Key.Length != 1 || !char.IsAsciiLetter(config.Key[0])) throw new ArgumentException("Hotkey.Key must be one ASCII letter A-Z.");
        var modifiers = (config.Option ? HotkeyModifiers.Alt : 0) | (config.Control ? HotkeyModifiers.Control : 0) | (config.Shift ? HotkeyModifiers.Shift : 0);
        if (modifiers == 0) throw new ArgumentException("Hotkey.Modifiers requires Option, Control, or Shift.");
        return new(modifiers, char.ToUpperInvariant(config.Key[0]));
    }
}

internal sealed class NativeMessageEventArgs(uint message, nint wParam) : EventArgs
{
    public uint Message { get; } = message;
    public nint WParam { get; } = wParam;
}

internal interface IMessageWindow
{
    event EventHandler<NativeMessageEventArgs>? MessageReceived;
    nint Handle { get; }
    bool RegisterHotkey(nint id, HotkeyModifiers modifiers, uint key);
    bool UnregisterHotkey(nint id);
    bool Destroy();
    int GetLastError();
}

internal sealed class NativeMessageWindow : IMessageWindow
{
    private const uint WmHotkey = 0x0312;
    private const uint WmWork = 0x8001;
    private readonly Thread _thread;
    private nint _handle;
    private uint _threadId;
    private Exception? _startError;
    private int _lastError;
    public event EventHandler<NativeMessageEventArgs>? MessageReceived;
    public nint Handle => _handle;

    public NativeMessageWindow()
    {
        using var ready = new ManualResetEventSlim();
        _thread = new Thread(() => Run(ready)) { IsBackground = true, Name = "NTranslate.Hotkey" };
        _thread.Start();
        ready.Wait();
        if (_startError is not null) throw new HotkeyOperationException(_startError.Message);
    }

    public bool RegisterHotkey(nint id, HotkeyModifiers modifiers, uint key) => Invoke(() => Capture(RegisterHotKey(_handle, id, (uint)modifiers, key)));
    public bool UnregisterHotkey(nint id) => Invoke(() => Capture(UnregisterHotKey(_handle, id)));
    public bool Destroy() => Invoke(() =>
    {
        var destroyed = Capture(DestroyWindow(_handle));
        if (destroyed) PostQuitMessage(0);
        return destroyed;
    });
    public int GetLastError() => _lastError;

    private bool Capture(bool result)
    {
        _lastError = Marshal.GetLastPInvokeError();
        return result;
    }

    private T Invoke<T>(Func<T> action)
    {
        if (GetCurrentThreadId() == _threadId) return action();
        T? result = default;
        Exception? error = null;
        using var done = new ManualResetEventSlim();
        var work = GCHandle.Alloc(new Action(() => { try { result = action(); } catch (Exception e) { error = e; } finally { done.Set(); } }));
        if (!PostThreadMessage(_threadId, WmWork, 0, GCHandle.ToIntPtr(work)))
        {
            work.Free();
            throw new HotkeyOperationException($"PostThreadMessage failed (Win32 error {Marshal.GetLastPInvokeError()}).");
        }
        done.Wait();
        if (error is not null) throw error;
        return result!;
    }

    private void Run(ManualResetEventSlim ready)
    {
        try
        {
            _threadId = GetCurrentThreadId();
            _handle = CreateWindowEx(0, "STATIC", "", 0, 0, 0, 0, 0, new nint(-3), 0, 0, 0);
            if (_handle == 0) throw new InvalidOperationException($"CreateWindowEx failed (Win32 error {Marshal.GetLastPInvokeError()}).");
            ready.Set();
            while (GetMessage(out var message, 0, 0, 0) > 0)
            {
                if (message.message == WmWork)
                {
                    var work = GCHandle.FromIntPtr(message.lParam);
                    ((Action)work.Target!).Invoke();
                    work.Free();
                    continue;
                }
                if (message.hwnd == _handle && message.message == WmHotkey) Dispatch(message.message, message.wParam);
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
        }
        catch (Exception error) { _startError = error; ready.Set(); }
    }

    private void Dispatch(uint message, nint wParam)
    {
        foreach (EventHandler<NativeMessageEventArgs> handler in MessageReceived?.GetInvocationList() ?? [])
            try { handler(this, new(message, wParam)); } catch { }
    }

    [StructLayout(LayoutKind.Sequential)] private struct Msg { public nint hwnd; public uint message; public nint wParam; public nint lParam; public uint time; public nint pt; }
    [DllImport("user32.dll", SetLastError = true)] private static extern nint CreateWindowEx(uint ex, string cls, string name, uint style, int x, int y, int w, int h, nint parent, nint menu, nint instance, nint param);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool DestroyWindow(nint hwnd);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterHotKey(nint hwnd, nint id, uint modifiers, uint key);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnregisterHotKey(nint hwnd, nint id);
    [DllImport("user32.dll")] private static extern int GetMessage(out Msg message, nint hwnd, uint min, uint max);
    [DllImport("user32.dll")] private static extern bool TranslateMessage(ref Msg message);
    [DllImport("user32.dll")] private static extern nint DispatchMessage(ref Msg message);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool PostThreadMessage(uint id, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll")] private static extern void PostQuitMessage(int exitCode);
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
}

public sealed class GlobalHotkey : IGlobalHotkey
{
    private const uint WmHotkey = 0x0312;
    private const nint Id = 0x4E54;
    private readonly IMessageWindow _window;
    private bool _registered;
    private bool _disposed;
    public GlobalHotkey() : this(new NativeMessageWindow()) { }
    internal GlobalHotkey(IMessageWindow window)
    {
        _window = window ?? throw new ArgumentNullException(nameof(window));
        _window.MessageReceived += HandleMessage;
    }
    public event EventHandler? Pressed;

    public HotkeyRegistrationResult Register(HotkeyConfig config)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var parsed = WindowsHotkeyValidation.Parse(config);
        if (_registered) Unregister();
        if (_window.RegisterHotkey(Id, parsed.Modifiers | HotkeyModifiers.NoRepeat, parsed.VirtualKey))
        {
            _registered = true;
            return new(true, null);
        }
        return new(false, $"RegisterHotKey failed (Win32 error {_window.GetLastError()}).");
    }

    public void Unregister()
    {
        if (!_registered) return;
        if (!_window.UnregisterHotkey(Id)) throw new HotkeyOperationException($"UnregisterHotKey failed (Win32 error {_window.GetLastError()}).");
        _registered = false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        Unregister();
        if (!_window.Destroy()) throw new HotkeyOperationException($"DestroyWindow failed (Win32 error {_window.GetLastError()}).");
        _window.MessageReceived -= HandleMessage;
        _disposed = true;
        GC.SuppressFinalize(this);
    }

    private void HandleMessage(object? sender, NativeMessageEventArgs message)
    {
        if (message.Message != WmHotkey || message.WParam != Id) return;
        foreach (EventHandler handler in Pressed?.GetInvocationList() ?? [])
            try { handler(this, EventArgs.Empty); } catch { }
    }
}
