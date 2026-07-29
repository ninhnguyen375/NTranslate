using System.Runtime.InteropServices;

namespace NTranslate.Platform.Windows;

internal enum TrayCommand { Open, History, Settings, CheckForUpdates, StartWithWindows, Exit }
internal enum TrayCallbackAction { Open, ContextMenu }

internal static class TrayCallbackMessages
{
    private const uint NinSelect = 0x0400;
    private const uint NinKeySelect = 0x0401;
    private const uint WmLButtonUp = 0x0202;
    private const uint WmLButtonDblClk = 0x0203;
    private const uint WmContextMenu = 0x007B;
    private const uint WmRButtonUp = 0x0205;

    internal static TrayCallbackAction? Resolve(uint message) => message switch
    {
        NinSelect or NinKeySelect or WmLButtonUp or WmLButtonDblClk => TrayCallbackAction.Open,
        WmContextMenu or WmRButtonUp => TrayCallbackAction.ContextMenu,
        _ => null,
    };
}

internal sealed class TrayActivationGate(uint correlationWindow)
{
    private const uint NinSelect = 0x0400;
    private const uint NinKeySelect = 0x0401;
    private const uint WmLButtonDblClk = 0x0203;
    private uint? _lastMessage;
    private uint _lastTime;

    internal bool ShouldRaise(uint message, uint time)
    {
        bool duplicate = _lastMessage is uint previous
            && IsModern(previous) != IsModern(message)
            && unchecked(time - _lastTime) <= correlationWindow;
        _lastMessage = duplicate ? null : message;
        _lastTime = time;
        return !duplicate;
    }

    private static bool IsModern(uint message) => message is NinSelect or NinKeySelect;
}

internal static class TrayMenuCommands
{
    internal const int OpenId = 1001;
    internal const int HistoryId = 1002;
    internal const int SettingsId = 1003;
    internal const int CheckForUpdatesId = 1004;
    internal const int StartWithWindowsId = 1005;
    internal const int ExitId = 1099;

    internal static TrayCommand? Resolve(int id) => id switch
    {
        OpenId => TrayCommand.Open,
        HistoryId => TrayCommand.History,
        SettingsId => TrayCommand.Settings,
        CheckForUpdatesId => TrayCommand.CheckForUpdates,
        StartWithWindowsId => TrayCommand.StartWithWindows,
        ExitId => TrayCommand.Exit,
        _ => null,
    };
}

public interface ITrayIcon : IDisposable
{
    event EventHandler? OpenTranslatorRequested;
    event EventHandler? HistoryRequested;
    event EventHandler? SettingsRequested;
    event EventHandler? CheckForUpdatesRequested;
    event EventHandler? StartWithWindowsRequested;
    event EventHandler? ExitRequested;
    void Show();
}

public sealed class TrayIcon : ITrayIcon
{
    private const uint WmCallback = 0x8000 + 1; // WM_APP + 1
    private const uint WmWork = 0x8000 + 2; // WM_APP + 2
    private const uint WmCommand = 0x0111;
    private const uint IconId = 1;
    private const uint NimAdd = 0, NimDelete = 2, NimSetVersion = 4;
    private const uint NifMessage = 1, NifIcon = 2, NifTip = 4;
    private const uint NotifyIconVersion4 = 4;
    private const uint MfString = 0;
    private const uint TpmRightButton = 2, TpmReturnCmd = 0x0100;

    private readonly Thread _thread;
    private readonly TrayActivationGate _activationGate = new(GetDoubleClickTime());
    private nint _hwnd;
    private nint _icon;
    private WndProc? _windowProcedure;
    private nint _previousWindowProcedure;
    private uint _threadId;
    private bool _added;
    private bool _disposed;
    private Exception? _startError;
    private readonly object _pendingGate = new();
    private readonly HashSet<PendingInvoke> _pendingInvokes = [];
    private Exception? _terminalError;

    public event EventHandler? OpenTranslatorRequested;
    public event EventHandler? HistoryRequested;
    public event EventHandler? SettingsRequested;
    public event EventHandler? CheckForUpdatesRequested;
    public event EventHandler? StartWithWindowsRequested;
    public event EventHandler? ExitRequested;
    internal nint MessageWindow => _hwnd;

    public TrayIcon()
    {
        using var ready = new ManualResetEventSlim();
        _thread = new Thread(() => Run(ready)) { IsBackground = true, Name = "NTranslate.Tray" };
        _thread.Start();
        ready.Wait();
        if (_startError is not null) throw new InvalidOperationException(_startError.Message, _startError);
    }

    public void Show()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_added) return;
        Invoke(() =>
        {
            var data = CreateIconData(NifMessage | NifIcon | NifTip);
            if (!Shell_NotifyIconW(NimAdd, ref data)) throw new InvalidOperationException($"Shell_NotifyIconW(NIM_ADD) failed (Win32 error {Marshal.GetLastPInvokeError()}).");
            data.uVersion = NotifyIconVersion4;
            if (!Shell_NotifyIconW(NimSetVersion, ref data)) throw new InvalidOperationException($"Shell_NotifyIconW(NIM_SETVERSION) failed (Win32 error {Marshal.GetLastPInvokeError()}).");
        });
        _added = true;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_added)
        {
            Invoke(() =>
            {
                var data = CreateIconData(0);
                Shell_NotifyIconW(NimDelete, ref data);
            });
            _added = false;
        }
        Invoke(() =>
        {
            if (_icon != 0) { DestroyIcon(_icon); _icon = 0; }
            if (_hwnd != 0)
            {
                if (_previousWindowProcedure != 0) SetWindowLongPtr(_hwnd, -4, _previousWindowProcedure);
                DestroyWindow(_hwnd);
                _hwnd = 0;
            }
            PostQuitMessage(0);
        });
        _thread.Join(TimeSpan.FromSeconds(5));
        GC.SuppressFinalize(this);
    }

    private NotifyIconData CreateIconData(uint flags) => new()
    {
        cbSize = Marshal.SizeOf<NotifyIconData>(),
        hWnd = _hwnd,
        uID = IconId,
        uFlags = flags,
        uCallbackMessage = WmCallback,
        hIcon = _icon,
        szTip = "NTranslate",
    };

    private void Invoke(Action action)
    {
        if (GetCurrentThreadId() == _threadId) { action(); return; }
        var pending = new PendingInvoke(action);
        lock (_pendingGate)
        {
            if (_terminalError is not null) throw new InvalidOperationException(_terminalError.Message, _terminalError);
            _pendingInvokes.Add(pending);
        }
        var handle = GCHandle.Alloc(pending);
        if (!PostThreadMessage(_threadId, WmWork, 0, GCHandle.ToIntPtr(handle)))
        {
            handle.Free();
            Complete(pending, new InvalidOperationException($"PostThreadMessage failed (Win32 error {Marshal.GetLastPInvokeError()})."));
        }
        if (!pending.Done.Wait(TimeSpan.FromSeconds(5)))
        {
            lock (_pendingGate)
            {
                if (_terminalError is not null) throw new InvalidOperationException(_terminalError.Message, _terminalError);
            }
            throw new InvalidOperationException("Tray icon command timed out.");
        }
        if (pending.Error is not null) throw pending.Error;
    }

    private void Complete(PendingInvoke pending, Exception? error)
    {
        pending.Error = error;
        pending.Done.Set();
        lock (_pendingGate) _pendingInvokes.Remove(pending);
    }

    private void Terminal(Exception error)
    {
        PendingInvoke[] pending;
        lock (_pendingGate)
        {
            if (_terminalError is not null) return;
            _terminalError = error;
            pending = [.. _pendingInvokes];
        }
        foreach (var invoke in pending) Complete(invoke, error);
    }

    private sealed class PendingInvoke(Action action)
    {
        public readonly Action Action = action;
        public readonly ManualResetEventSlim Done = new();
        public Exception? Error;
    }

    private void Run(ManualResetEventSlim ready)
    {
        try
        {
            _threadId = GetCurrentThreadId();
            _hwnd = CreateWindowEx(0, "STATIC", "", 0, 0, 0, 0, 0, 0, 0, 0, 0);
            if (_hwnd == 0) throw new InvalidOperationException($"CreateWindowEx failed (Win32 error {Marshal.GetLastPInvokeError()}).");
            _windowProcedure = WindowProcedure;
            _previousWindowProcedure = SetWindowLongPtr(_hwnd, -4, Marshal.GetFunctionPointerForDelegate(_windowProcedure));
            if (_previousWindowProcedure == 0) throw new InvalidOperationException($"SetWindowLongPtr failed (Win32 error {Marshal.GetLastPInvokeError()}).");
            _icon = LoadImage(0, Path.Combine(AppContext.BaseDirectory, "Assets", "NTranslate.ico"), 1, 0, 0, 0x10 | 0x40);
            if (_icon == 0) throw new InvalidOperationException($"LoadImage failed (Win32 error {Marshal.GetLastPInvokeError()}).");
            ready.Set();
            while (true)
            {
                var status = GetMessage(out var message, 0, 0, 0);
                if (status == 0) break;
                if (status == -1) throw new InvalidOperationException($"GetMessage failed (Win32 error {Marshal.GetLastPInvokeError()}).");
                if (message.message == WmWork)
                {
                    var handle = GCHandle.FromIntPtr(message.lParam);
                    var pending = (PendingInvoke)handle.Target!;
                    handle.Free();
                    try { pending.Action(); Complete(pending, null); }
                    catch (Exception error) { Complete(pending, error); }
                    continue;
                }
                TranslateMessage(ref message);
                DispatchMessage(ref message);
            }
            Terminal(new InvalidOperationException("Tray icon message window has stopped."));
        }
        catch (Exception error) { _startError = error; ready.Set(); Terminal(error); }
    }

    private nint WindowProcedure(nint hwnd, uint message, nint wParam, nint lParam)
    {
        if (message == WmCallback)
        {
            HandleCallback(lParam, GetMessageTime());
            return 0;
        }
        if (message == WmCommand)
        {
            HandleCommand((int)(wParam.ToInt64() & 0xFFFF));
            return 0;
        }
        return CallWindowProc(_previousWindowProcedure, hwnd, message, wParam, lParam);
    }

    private void HandleCallback(nint lParam, uint time)
    {
        var message = (uint)(lParam.ToInt64() & 0xFFFF);
        switch (TrayCallbackMessages.Resolve(message))
        {
            case TrayCallbackAction.Open when _activationGate.ShouldRaise(message, time): Raise(OpenTranslatorRequested); break;
            case TrayCallbackAction.ContextMenu: ShowContextMenu(); break;
        }
    }

    private void ShowContextMenu()
    {
        GetCursorPos(out var point);
        var menu = CreatePopupMenu();
        AppendMenu(menu, MfString, (nint)TrayMenuCommands.OpenId, "Open Translator");
        AppendMenu(menu, MfString, (nint)TrayMenuCommands.HistoryId, "Translation History");
        AppendMenu(menu, MfString, (nint)TrayMenuCommands.SettingsId, "Settings");
        AppendMenu(menu, MfString, (nint)TrayMenuCommands.CheckForUpdatesId, "Check for Updates");
        AppendMenu(menu, MfString, (nint)TrayMenuCommands.StartWithWindowsId, "Start with Windows");
        AppendMenu(menu, MfString, (nint)TrayMenuCommands.ExitId, "Exit");
        SetForegroundWindow(_hwnd);
        var command = TrackPopupMenu(menu, TpmRightButton | TpmReturnCmd, point.x, point.y, 0, _hwnd, 0);
        PostMessage(_hwnd, 0, 0, 0); // WM_NULL: required so the menu closes correctly (MS Q135788)
        DestroyMenu(menu);
        if (command != 0) HandleCommand((int)command);
    }

    private void HandleCommand(int id)
    {
        switch (TrayMenuCommands.Resolve(id))
        {
            case TrayCommand.Open: Raise(OpenTranslatorRequested); break;
            case TrayCommand.History: Raise(HistoryRequested); break;
            case TrayCommand.Settings: Raise(SettingsRequested); break;
            case TrayCommand.CheckForUpdates: Raise(CheckForUpdatesRequested); break;
            case TrayCommand.StartWithWindows: Raise(StartWithWindowsRequested); break;
            case TrayCommand.Exit: Raise(ExitRequested); break;
        }
    }

    private static void Raise(EventHandler? handler)
    {
        foreach (EventHandler h in handler?.GetInvocationList() ?? [])
            _ = Task.Run(() => { try { h(null, EventArgs.Empty); } catch { } });
    }

    [StructLayout(LayoutKind.Sequential)] private struct Msg { public nint hwnd; public uint message; public nint wParam; public nint lParam; public uint time; public nint pt; }
    [StructLayout(LayoutKind.Sequential)] private struct Point { public int x; public int y; }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct NotifyIconData
    {
        public int cbSize;
        public nint hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public nint hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public nint hBalloonIcon;
    }

    private delegate nint WndProc(nint hwnd, uint message, nint wParam, nint lParam);
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] private static extern bool Shell_NotifyIconW(uint message, ref NotifyIconData data);
    [DllImport("user32.dll", SetLastError = true)] private static extern nint CreateWindowEx(uint ex, string cls, string name, uint style, int x, int y, int w, int h, nint parent, nint menu, nint instance, nint param);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW", SetLastError = true)] private static extern nint SetWindowLongPtr(nint hwnd, int index, nint value);
    [DllImport("user32.dll")] private static extern nint CallWindowProc(nint previous, nint hwnd, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll")] private static extern uint GetMessageTime();
    [DllImport("user32.dll", SetLastError = true)] private static extern bool DestroyWindow(nint hwnd);
    [DllImport("user32.dll")] private static extern int GetMessage(out Msg message, nint hwnd, uint min, uint max);
    [DllImport("user32.dll")] private static extern bool TranslateMessage(ref Msg message);
    [DllImport("user32.dll")] private static extern nint DispatchMessage(ref Msg message);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool PostThreadMessage(uint id, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll")] private static extern void PostQuitMessage(int exitCode);
    [DllImport("user32.dll")] private static extern bool PostMessage(nint hwnd, uint message, nint wParam, nint lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern nint LoadImage(nint instance, string name, uint type, int cx, int cy, uint flags);
    [DllImport("user32.dll")] private static extern bool DestroyIcon(nint icon);
    [DllImport("user32.dll")] private static extern nint CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool AppendMenu(nint menu, uint flags, nint id, string text);
    [DllImport("user32.dll")] private static extern bool DestroyMenu(nint menu);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint hwnd);
    [DllImport("user32.dll")] private static extern uint TrackPopupMenu(nint menu, uint flags, int x, int y, int reserved, nint hwnd, nint rect);
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out Point point);
    [DllImport("user32.dll")] private static extern uint GetDoubleClickTime();
    [DllImport("kernel32.dll")] private static extern uint GetCurrentThreadId();
}
