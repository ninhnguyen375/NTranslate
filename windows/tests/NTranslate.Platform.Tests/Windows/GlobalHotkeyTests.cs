using NTranslate.Core.Configuration;
using NTranslate.Platform.Windows;

namespace NTranslate.Platform.Tests.Windows;

public sealed class GlobalHotkeyTests
{
    [Fact]
    public void Parse_maps_letters_and_windows_modifiers()
    {
        var parsed = WindowsHotkeyValidation.Parse(new("z", true, false, true, true));
        Assert.Equal((uint)'Z', parsed.VirtualKey);
        Assert.Equal(HotkeyModifiers.Alt | HotkeyModifiers.Control | HotkeyModifiers.Shift, parsed.Modifiers);
    }

    [Theory]
    [InlineData("1")]
    [InlineData("AA")]
    [InlineData("")]
    [InlineData("Đ")]
    public void Parse_rejects_non_ascii_key(string key) =>
        Assert.Equal("Hotkey.Key must be one ASCII letter A-Z.", Assert.Throws<ArgumentException>(() => WindowsHotkeyValidation.Parse(new(key, false, false, true, false))).Message);

    [Fact]
    public void Register_uses_fixed_id_no_repeat_and_parsed_values()
    {
        var native = new FakeNativeWindowApi();
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);
        Assert.True(hotkey.Register(new("D", true, false, false, false)).IsRegistered);
        Assert.Equal((nint)0x4E54, native.RegisterId);
        Assert.Equal(HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, native.RegisterModifiers);
    }

    [Fact]
    public void Register_throws_and_preserves_existing_registration_when_unregister_fails()
    {
        var native = new FakeNativeWindowApi { UnregisterResult = false, LastError = 5 };
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);
        hotkey.Register(new("D", false, false, true, false));

        Assert.Equal("UnregisterHotKey failed (Win32 error 5).", Assert.Throws<HotkeyOperationException>(() => hotkey.Register(new("E", false, false, true, false))).Message);
        Assert.Equal(1, native.RegisterCalls);
        native.UnregisterResult = true;
    }

    [Fact]
    public void Unregister_throws_native_failure_and_can_retry()
    {
        var native = new FakeNativeWindowApi { UnregisterResult = false, LastError = 5 };
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);
        hotkey.Register(new("D", false, false, true, false));

        Assert.Throws<HotkeyOperationException>(hotkey.Unregister);
        native.UnregisterResult = true;
        hotkey.Unregister();
        Assert.Equal(2, native.UnregisterCalls);
    }

    [Fact]
    public void Dispose_failed_unregister_keeps_state_for_explicit_retry()
    {
        var native = new FakeNativeWindowApi { UnregisterResult = false, LastError = 5 };
        using var router = new WindowMessageRouter((nint)1, native);
        var hotkey = new GlobalHotkey(router, native);
        hotkey.Register(new("D", false, false, true, false));

        hotkey.Dispose();

        Assert.Equal(1, native.UnregisterCalls);
        Assert.Equal(0, native.RestoreCalls);
        native.UnregisterResult = true;
        hotkey.Unregister();
        hotkey.Dispose();
        Assert.Equal(0, native.RestoreCalls);
    }

    [Fact]
    public void Router_rejects_window_owned_by_another_thread_before_subclassing()
    {
        var native = new FakeNativeWindowApi { WindowThreadId = (uint)(Environment.CurrentManagedThreadId + 1) };
        Assert.Equal("HWND belongs to a different thread.", Assert.Throws<InvalidOperationException>(() => new WindowMessageRouter((nint)1, native)).Message);
        Assert.Equal(0, native.SetWindowProcedureCalls);
    }

    [Fact]
    public void Router_forwards_old_proc_when_subscriber_throws()
    {
        var native = new FakeNativeWindowApi();
        using var router = new WindowMessageRouter((nint)1, native);
        router.MessageReceived += (_, _) => throw new InvalidOperationException();
        router.Dispatch(1, 2, 3);
        Assert.Equal(1, native.CallWindowProcedureCalls);
    }

    [Fact]
    public void Router_dispose_failed_restore_is_retryable()
    {
        var native = new FakeNativeWindowApi { RestoreResult = false, LastError = 87 };
        var router = new WindowMessageRouter((nint)1, native);
        Assert.Throws<HotkeyOperationException>(router.Dispose);
        native.RestoreResult = true;
        router.Dispose();
        router.Dispose();
        Assert.Equal(2, native.RestoreCalls);
    }

    [Fact]
    public void Lifecycle_rejects_wrong_thread()
    {
        var native = new FakeNativeWindowApi();
        var router = new WindowMessageRouter((nint)1, native);
        var hotkey = new GlobalHotkey(router, native);
        Exception? error = null;
        var thread = new Thread(() => error = Record.Exception(() => hotkey.Register(new("D", false, false, true, false))));
        thread.Start(); thread.Join();
        Assert.Equal("Global hotkey must run on its owner thread.", Assert.IsType<InvalidOperationException>(error).Message);
        hotkey.Dispose(); router.Dispose();
    }

    private sealed class FakeNativeWindowApi : INativeWindowApi
    {
        public nint PreviousWindowProc { get; set; } = (nint)99;
        public uint WindowThreadId { get; set; } = (uint)Environment.CurrentManagedThreadId;
        public bool RegisterResult { get; set; } = true;
        public bool UnregisterResult { get; set; } = true;
        public bool RestoreResult { get; set; } = true;
        public int LastError { get; set; }
        public nint RegisterId { get; private set; }
        public HotkeyModifiers RegisterModifiers { get; private set; }
        public int RegisterCalls { get; private set; }
        public int UnregisterCalls { get; private set; }
        public int RestoreCalls { get; private set; }
        public int SetWindowProcedureCalls { get; private set; }
        public int CallWindowProcedureCalls { get; private set; }
        public uint GetWindowThreadId(nint window) => WindowThreadId;
        public nint SetWindowProcedure(nint window, WindowProcedure procedure) { SetWindowProcedureCalls++; return PreviousWindowProc; }
        public bool RestoreWindowProcedure(nint window, nint procedure) { RestoreCalls++; return RestoreResult; }
        public nint CallWindowProcedure(nint procedure, nint window, uint message, nint wParam, nint lParam) { CallWindowProcedureCalls++; return 0; }
        public bool RegisterHotkey(nint window, nint id, HotkeyModifiers modifiers, uint virtualKey) { RegisterId = id; RegisterModifiers = modifiers; RegisterCalls++; return RegisterResult; }
        public bool UnregisterHotkey(nint window, nint id) { UnregisterCalls++; return UnregisterResult; }
        public int GetLastError() => LastError;
    }
}
