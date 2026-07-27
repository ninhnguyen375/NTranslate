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
    public void Parse_rejects_missing_modifier() =>
        Assert.Equal("Hotkey.Modifiers requires Option, Control, or Shift.", Assert.Throws<ArgumentException>(() => WindowsHotkeyValidation.Parse(new("D", false, false, false, false))).Message);

    [Fact]
    public void Validate_rejects_command_before_native_registration()
    {
        var issues = WindowsHotkeyValidation.Validate(new("D", false, true, false, false));
        Assert.Contains(issues, x => x.Field == "Hotkey.Command" && x.Message == "Command is not supported on Windows.");
    }

    [Fact]
    public void Register_uses_fixed_id_no_repeat_and_parsed_values()
    {
        var native = new FakeNativeWindowApi();
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);
        var result = hotkey.Register(new("D", true, false, false, false));
        Assert.True(result.IsRegistered);
        Assert.Equal((nint)0x4E54, native.RegisterId);
        Assert.Equal(HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, native.RegisterModifiers);
    }

    [Fact]
    public void Register_preserves_existing_state_when_unregister_fails()
    {
        var native = new FakeNativeWindowApi { UnregisterResult = false, LastError = 5 };
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);
        Assert.True(hotkey.Register(new("D", false, false, true, false)).IsRegistered);

        var result = hotkey.Register(new("E", false, false, true, false));

        Assert.False(result.IsRegistered);
        Assert.Equal("UnregisterHotKey failed (Win32 error 5).", result.Error);
        Assert.Equal(1, native.RegisterCalls);
        Assert.Equal(1, native.UnregisterCalls);
        native.UnregisterResult = true;
    }

    [Fact]
    public void Unregister_reports_native_failure_and_can_retry()
    {
        var native = new FakeNativeWindowApi { UnregisterResult = false, LastError = 5 };
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);
        hotkey.Register(new("D", false, false, true, false));

        Assert.Equal("UnregisterHotKey failed (Win32 error 5).", hotkey.Unregister().Error);
        native.UnregisterResult = true;
        Assert.True(hotkey.Unregister().IsRegistered);
    }

    [Fact]
    public void Pressed_filters_message_id()
    {
        var native = new FakeNativeWindowApi();
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);
        var pressed = 0;
        hotkey.Pressed += (_, _) => pressed++;
        hotkey.Register(new("D", false, false, true, false));
        router.Dispatch(WindowMessageRouter.WmHotkey, (nint)0x1234, 0);
        router.Dispatch(WindowMessageRouter.WmHotkey, (nint)0x4E54, 0);
        Assert.Equal(1, pressed);
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
    public void Router_dispose_failed_restore_is_retryable_and_keeps_callback_alive()
    {
        var native = new FakeNativeWindowApi { RestoreResult = false, LastError = 87 };
        var router = new WindowMessageRouter((nint)1, native);

        Assert.Equal("SetWindowLongPtr restore failed (Win32 error 87).", Assert.Throws<InvalidOperationException>(router.Dispose).Message);
        Assert.Equal(1, native.RestoreCalls);
        native.RestoreResult = true;
        router.Dispose();
        router.Dispose();
        Assert.Equal(2, native.RestoreCalls);
    }

    [Fact]
    public void Router_install_zero_return_with_no_error_is_valid()
    {
        var native = new FakeNativeWindowApi { PreviousWindowProc = 0, LastError = 0 };
        using var router = new WindowMessageRouter((nint)1, native);
    }

    [Fact]
    public void Router_install_zero_return_with_error_fails()
    {
        var native = new FakeNativeWindowApi { PreviousWindowProc = 0, LastError = 1400 };
        Assert.Equal("SetWindowLongPtr failed (Win32 error 1400).", Assert.Throws<InvalidOperationException>(() => new WindowMessageRouter((nint)1, native)).Message);
    }

    [Fact]
    public void Lifecycle_rejects_wrong_thread()
    {
        var native = new FakeNativeWindowApi();
        var router = new WindowMessageRouter((nint)1, native);
        var hotkey = new GlobalHotkey(router, native);
        Exception? error = null;
        var thread = new Thread(() => error = Record.Exception(() => hotkey.Register(new("D", false, false, true, false))));
        thread.Start();
        thread.Join();
        Assert.Equal("Global hotkey must run on its owner thread.", Assert.IsType<InvalidOperationException>(error).Message);
        hotkey.Dispose();
        router.Dispose();
    }

    private sealed class FakeNativeWindowApi : INativeWindowApi
    {
        public nint PreviousWindowProc { get; set; } = (nint)99;
        public bool RegisterResult { get; set; } = true;
        public bool UnregisterResult { get; set; } = true;
        public bool RestoreResult { get; set; } = true;
        public int LastError { get; set; }
        public nint RegisterId { get; private set; }
        public HotkeyModifiers RegisterModifiers { get; private set; }
        public int RegisterCalls { get; private set; }
        public int UnregisterCalls { get; private set; }
        public int RestoreCalls { get; private set; }
        public int CallWindowProcedureCalls { get; private set; }
        public nint SetWindowProcedure(nint window, WindowProcedure procedure) => PreviousWindowProc;
        public bool RestoreWindowProcedure(nint window, nint procedure) { RestoreCalls++; return RestoreResult; }
        public nint CallWindowProcedure(nint procedure, nint window, uint message, nint wParam, nint lParam) { CallWindowProcedureCalls++; return 0; }
        public bool RegisterHotkey(nint window, nint id, HotkeyModifiers modifiers, uint virtualKey) { RegisterId = id; RegisterModifiers = modifiers; RegisterCalls++; return RegisterResult; }
        public bool UnregisterHotkey(nint window, nint id) { UnregisterCalls++; return UnregisterResult; }
        public int GetLastError() => LastError;
    }
}
