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
    [InlineData("Đ")]
    public void Parse_rejects_non_ascii_key(string key) => Assert.Throws<ArgumentException>(() => WindowsHotkeyValidation.Parse(new(key, false, false, true, false)));

    [Fact]
    public void Register_uses_owned_message_window_fixed_id_and_no_repeat()
    {
        var owner = new FakeMessageWindow();
        using var hotkey = new GlobalHotkey(owner);
        var result = hotkey.Register(new("D", true, false, false, false));
        Assert.True(result.IsRegistered);
        Assert.Equal((nint)77, owner.RegisterWindow);
        Assert.Equal((nint)0x4E54, owner.RegisterId);
        Assert.Equal(HotkeyModifiers.Alt | HotkeyModifiers.NoRepeat, owner.RegisterModifiers);
    }

    [Fact]
    public void Register_failure_returns_native_error_without_throwing()
    {
        var owner = new FakeMessageWindow { RegisterResult = false, LastError = 1409 };
        using var hotkey = new GlobalHotkey(owner);

        var result = hotkey.Register(new("D", false, false, true, false));

        Assert.False(result.IsRegistered);
        Assert.Contains("1409", result.Error);
    }

    [Fact]
    public void WmHotkey_filters_id_and_contains_subscriber_errors()
    {
        var owner = new FakeMessageWindow();
        using var hotkey = new GlobalHotkey(owner);
        var pressed = 0;
        using var delivered = new ManualResetEventSlim();
        hotkey.Pressed += (_, _) => throw new InvalidOperationException();
        hotkey.Pressed += (_, _) => { Interlocked.Increment(ref pressed); delivered.Set(); };
        hotkey.Register(new("D", false, false, true, false));
        owner.Dispatch(0x0312, 1);
        owner.Dispatch(0x0312, 0x4E54);
        Assert.True(delivered.Wait(TimeSpan.FromSeconds(5)));
        Assert.Equal(1, Volatile.Read(ref pressed));
    }

    [Fact]
    public void Unregister_failure_throws_and_can_retry()
    {
        var owner = new FakeMessageWindow { UnregisterResult = false, LastError = 5 };
        using var hotkey = new GlobalHotkey(owner);
        hotkey.Register(new("D", false, false, true, false));
        Assert.Throws<HotkeyOperationException>(hotkey.Unregister);
        owner.UnregisterResult = true;
        hotkey.Unregister();
        Assert.Equal(2, owner.UnregisterCalls);
    }

    [Fact]
    public void Dispose_failure_throws_keeps_owned_window_for_retry()
    {
        var owner = new FakeMessageWindow { UnregisterResult = false, LastError = 5 };
        var hotkey = new GlobalHotkey(owner);
        hotkey.Register(new("D", false, false, true, false));
        Assert.Throws<HotkeyOperationException>(hotkey.Dispose);
        Assert.Equal(0, owner.DestroyCalls);
        owner.UnregisterResult = true;
        hotkey.Dispose();
        hotkey.Dispose();
        Assert.Equal(1, owner.DestroyCalls);
    }

    [Fact]
    public void Dispose_destroy_failure_throws_and_retries()
    {
        var owner = new FakeMessageWindow { DestroyResult = false, LastError = 87 };
        var hotkey = new GlobalHotkey(owner);
        Assert.Throws<HotkeyOperationException>(hotkey.Dispose);
        owner.DestroyResult = true;
        hotkey.Dispose();
        Assert.Equal(2, owner.DestroyCalls);
    }

    private sealed class FakeMessageWindow : IMessageWindow
    {
        public event EventHandler<NativeMessageEventArgs>? MessageReceived;
        public nint Handle => 77;
        public bool RegisterResult { get; set; } = true;
        public bool UnregisterResult { get; set; } = true;
        public bool DestroyResult { get; set; } = true;
        public int LastError { get; set; }
        public nint RegisterWindow { get; private set; }
        public nint RegisterId { get; private set; }
        public HotkeyModifiers RegisterModifiers { get; private set; }
        public int UnregisterCalls { get; private set; }
        public int DestroyCalls { get; private set; }
        public NativeCommandResult<bool> RegisterHotkey(nint id, HotkeyModifiers modifiers, uint key) { RegisterWindow = Handle; RegisterId = id; RegisterModifiers = modifiers; return new(RegisterResult, RegisterResult ? 0 : LastError); }
        public NativeCommandResult<bool> UnregisterHotkey(nint id) { UnregisterCalls++; return new(UnregisterResult, UnregisterResult ? 0 : LastError); }
        public NativeCommandResult<bool> Destroy() { DestroyCalls++; return new(DestroyResult, DestroyResult ? 0 : LastError); }
        public void Dispatch(uint message, nint wParam) => MessageReceived?.Invoke(this, new(message, wParam));
    }
}
