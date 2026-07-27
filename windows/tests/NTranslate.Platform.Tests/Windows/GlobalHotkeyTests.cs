using NTranslate.Core.Configuration;
using NTranslate.Platform.Windows;

namespace NTranslate.Platform.Tests.Windows;

public sealed class GlobalHotkeyTests
{
    [Fact]
    public void Parse_maps_letters_and_windows_modifiers()
    {
        var parsed = GlobalHotkey.Parse(new("z", Option: true, Command: false, Control: true, Shift: true));

        Assert.Equal((uint)'Z', parsed.VirtualKey);
        Assert.Equal(HotkeyModifiers.Alt | HotkeyModifiers.Control | HotkeyModifiers.Shift, parsed.Modifiers);
    }

    [Theory]
    [InlineData("1")]
    [InlineData("AA")]
    [InlineData("")]
    public void Parse_rejects_unsupported_key(string key)
    {
        var error = Assert.Throws<ArgumentException>(() => GlobalHotkey.Parse(new(key, false, false, true, false)));

        Assert.Equal("Hotkey.Key must be one letter A-Z.", error.Message);
    }

    [Fact]
    public void Parse_rejects_missing_modifier()
    {
        var error = Assert.Throws<ArgumentException>(() => GlobalHotkey.Parse(new("D", false, false, false, false)));

        Assert.Equal("Hotkey.Modifiers requires Option, Control, or Shift.", error.Message);
    }

    [Fact]
    public void Parse_rejects_command_modifier_on_windows()
    {
        var error = Assert.Throws<ArgumentException>(() => GlobalHotkey.Parse(new("D", false, true, false, false)));

        Assert.Equal("Hotkey.Command is not supported on Windows.", error.Message);
    }

    [Fact]
    public void Register_uses_fixed_id_no_repeat_and_parsed_values()
    {
        var native = new FakeNativeWindowApi();
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);

        var result = hotkey.Register(new("D", true, false, false, false));

        Assert.True(result.IsRegistered);
        Assert.Null(result.Error);
        Assert.Equal((nint)1, native.RegisterWindow);
        Assert.Equal((nint)0x4E54, native.RegisterId);
        Assert.Equal(HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, native.RegisterModifiers);
        Assert.Equal((uint)'D', native.RegisterVirtualKey);
    }

    [Fact]
    public void Register_unregisters_existing_hotkey_first()
    {
        var native = new FakeNativeWindowApi();
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);
        hotkey.Register(new("D", false, false, true, false));

        hotkey.Register(new("E", false, false, true, false));

        Assert.Equal(1, native.UnregisterCalls);
        Assert.Equal(2, native.RegisterCalls);
    }

    [Fact]
    public void Register_returns_native_error()
    {
        var native = new FakeNativeWindowApi { RegisterResult = false, LastError = 1409 };
        using var router = new WindowMessageRouter((nint)1, native);
        using var hotkey = new GlobalHotkey(router, native);

        var result = hotkey.Register(new("D", false, false, true, false));

        Assert.False(result.IsRegistered);
        Assert.Equal("RegisterHotKey failed (Win32 error 1409).", result.Error);
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
        router.Dispatch(0x0400, (nint)0x4E54, 0);

        Assert.Equal(1, pressed);
    }

    [Fact]
    public void Dispose_unregisters_and_restores_original_wndproc()
    {
        var native = new FakeNativeWindowApi { PreviousWindowProc = (nint)123 };
        var router = new WindowMessageRouter((nint)1, native);
        var hotkey = new GlobalHotkey(router, native);
        hotkey.Register(new("D", false, false, true, false));

        hotkey.Dispose();
        router.Dispose();

        Assert.Equal(1, native.UnregisterCalls);
        Assert.Equal((nint)123, native.RestoredWindowProc);
    }

    private sealed class FakeNativeWindowApi : INativeWindowApi
    {
        public nint PreviousWindowProc { get; init; } = (nint)99;
        public bool RegisterResult { get; init; } = true;
        public int LastError { get; init; }
        public nint RegisterWindow { get; private set; }
        public nint RegisterId { get; private set; }
        public HotkeyModifiers RegisterModifiers { get; private set; }
        public uint RegisterVirtualKey { get; private set; }
        public int RegisterCalls { get; private set; }
        public int UnregisterCalls { get; private set; }
        public nint RestoredWindowProc { get; private set; }

        public nint SetWindowProcedure(nint window, WindowProcedure procedure) => PreviousWindowProc;
        public void RestoreWindowProcedure(nint window, nint procedure) => RestoredWindowProc = procedure;
        public nint CallWindowProcedure(nint procedure, nint window, uint message, nint wParam, nint lParam) => 0;
        public bool RegisterHotkey(nint window, nint id, HotkeyModifiers modifiers, uint virtualKey)
        {
            RegisterWindow = window;
            RegisterId = id;
            RegisterModifiers = modifiers;
            RegisterVirtualKey = virtualKey;
            RegisterCalls++;
            return RegisterResult;
        }
        public bool UnregisterHotkey(nint window, nint id)
        {
            UnregisterCalls++;
            return true;
        }
        public int GetLastError() => LastError;
    }
}
