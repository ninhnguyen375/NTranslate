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
    NativeCommandResult<bool> RegisterHotkey(nint id, HotkeyModifiers modifiers, uint key);
    NativeCommandResult<bool> UnregisterHotkey(nint id);
    NativeCommandResult<bool> Destroy();
}

internal sealed class NativeMessageWindow : IMessageWindow
{
    private const uint WmHotkey = 0x0312;
    private const uint WmWork = 0x8001;
    private readonly Thread _thread;
    private nint _handle;
    private uint _threadId;
    private Exception? _startError;
    private readonly object _commandsGate = new();
    private readonly HashSet<Command> _commands = [];
    private Exception? _terminalError;
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

    public NativeCommandResult<bool> RegisterHotkey(nint id, HotkeyModifiers modifiers, uint key) => Invoke(() => RegisterHotKey(_handle, id, (uint)modifiers, key));
    public NativeCommandResult<bool> UnregisterHotkey(nint id) => Invoke(() => UnregisterHotKey(_handle, id));
    public NativeCommandResult<bool> Destroy() => Invoke(() =>
    {
        var destroyed = DestroyWindow(_handle);
        if (destroyed) PostQuitMessage(0);
        return destroyed;
    });

    private NativeCommandResult<bool> Invoke(Func<bool> action)
    {
        if (GetCurrentThreadId() == _threadId)
        {
            var value = action();
            return new(value, value ? 0 : Marshal.GetLastPInvokeError());
        }
        var command = new Command(action);
        lock (_commandsGate)
        {
            if (_terminalError is not null) throw new HotkeyOperationException(_terminalError.Message);
            _commands.Add(command);
        }
        var handle = GCHandle.Alloc(command);
        if (!PostThreadMessage(_threadId, WmWork, 0, GCHandle.ToIntPtr(handle)))
        {
            handle.Free();
            Complete(command, null, new HotkeyOperationException($"PostThreadMessage failed (Win32 error {Marshal.GetLastPInvokeError()})."));
        }
        if (!command.Done.Wait(TimeSpan.FromSeconds(5)))
        {
            command.Cancelled = true;
            throw new HotkeyOperationException("Hotkey command timed out.");
        }
        if (command.Error is not null) throw command.Error;
        return command.Result!;
    }

    private void Complete(Command command, NativeCommandResult<bool>? result, Exception? error)
    {
        command.Result = result;
        command.Error = error;
        command.Done.Set();
        lock (_commandsGate) _commands.Remove(command);
    }

    private sealed class Command(Func<bool> action)
    {
        public readonly Func<bool> Action = action;
        public readonly ManualResetEventSlim Done = new();
        public bool Cancelled;
        public NativeCommandResult<bool>? Result;
        public Exception? Error;
    }

    private void Run(ManualResetEventSlim ready)
    {
        try
        {
            _threadId = GetCurrentThreadId();
            _handle = CreateWindowEx(0, "STATIC", "", 0, 0, 0, 0, 0, new nint(-3), 0, 0, 0);
            if (_handle == 0) throw new InvalidOperationException($"CreateWindowEx failed (Win32 error {Marshal.GetLastPInvokeError()}).");
            ready.Set();
            while (true)
            {
                var status = GetMessage(out var message, 0, 0, 0);
                if (status == 0) break;
                if (status == -1) throw new HotkeyOperationException($"GetMessage failed (Win32 error {Marshal.GetLastPInvokeError()}).");
                if (message.message == WmWork)
                {
                    var handle = GCHandle.FromIntPtr(message.lParam);
                    var command = (Command)handle.Target!;
                    handle.Free();
                    if (!command.Cancelled)
                    {
                        try
                        {
                            var value = command.Action();
                            Complete(command, new(value, value ? 0 : Marshal.GetLastPInvokeError()), null);
                        }
                        catch (Exception error) { Complete(command, null, error); }
                    }
                    else Complete(command, null, new HotkeyOperationException("Hotkey command timed out."));
                    continue;
                }
                if (message.hwnd == _handle && message.message == WmHotkey) Dispatch(message.message, message.wParam);
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
            Terminal(new HotkeyOperationException("Hotkey message window has stopped."));
        }
        catch (Exception error) { _startError = error; ready.Set(); Terminal(error); }
    }

    private void Terminal(Exception error)
    {
        Command[] pending;
        lock (_commandsGate)
        {
            _terminalError = error;
            pending = _commands.ToArray();
        }
        foreach (var command in pending) Complete(command, null, error);
    }

    private void Dispatch(uint message, nint wParam)
    {
        foreach (EventHandler<NativeMessageEventArgs> handler in MessageReceived?.GetInvocationList() ?? [])
            _ = Task.Run(() => { try { handler(this, new(message, wParam)); } catch { } });
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
        var result = _window.RegisterHotkey(Id, parsed.Modifiers | HotkeyModifiers.NoRepeat, parsed.VirtualKey);
        if (result.Value)
        {
            _registered = true;
            return new(true, null);
        }
        return new(false, $"RegisterHotKey failed (Win32 error {result.LastError}).");
    }

    public void Unregister()
    {
        if (!_registered) return;
        var result = _window.UnregisterHotkey(Id);
        if (!result.Value) throw new HotkeyOperationException($"UnregisterHotKey failed (Win32 error {result.LastError}).");
        _registered = false;
    }

    public void Dispose()
    {
        if (_disposed) return;
        List<Exception> errors = [];
        try { Unregister(); }
        catch (Exception error) { errors.Add(error); }
        try
        {
            var result = _window.Destroy();
            if (!result.Value) errors.Add(new HotkeyOperationException($"DestroyWindow failed (Win32 error {result.LastError})."));
        }
        catch (Exception error) { errors.Add(error); }
        finally
        {
            _window.MessageReceived -= HandleMessage;
            _disposed = true;
            GC.SuppressFinalize(this);
        }
        if (errors.Count == 1) throw errors[0];
        if (errors.Count > 1) throw new AggregateException("Hotkey cleanup failed.", errors);
    }

    private void HandleMessage(object? sender, NativeMessageEventArgs message)
    {
        if (message.Message != WmHotkey || message.WParam != Id) return;
        foreach (EventHandler handler in Pressed?.GetInvocationList() ?? [])
            _ = Task.Run(() => { try { handler(this, EventArgs.Empty); } catch { } });
    }
}
