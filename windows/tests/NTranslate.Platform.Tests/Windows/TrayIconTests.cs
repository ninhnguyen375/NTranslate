using NTranslate.Platform.Windows;

namespace NTranslate.Platform.Tests.Windows;

public sealed class TrayIconTests
{
    [Fact]
    public void Resolve_maps_open_command_id()
        => Assert.Equal(TrayCommand.Open, TrayMenuCommands.Resolve(1001));

    [Fact]
    public void Resolve_maps_integrated_command_ids()
    {
        Assert.Equal(TrayCommand.History, TrayMenuCommands.Resolve(1002));
        Assert.Equal(TrayCommand.Settings, TrayMenuCommands.Resolve(1003));
        Assert.Equal(TrayCommand.CheckForUpdates, TrayMenuCommands.Resolve(1004));
        Assert.Equal(TrayCommand.StartWithWindows, TrayMenuCommands.Resolve(1005));
    }

    [Fact]
    public void Resolve_maps_exit_command_id()
        => Assert.Equal(TrayCommand.Exit, TrayMenuCommands.Resolve(1099));

    [Theory]
    [InlineData(0)]
    [InlineData(1000)]
    [InlineData(1100)]
    public void Resolve_returns_null_for_unknown_id(int id)
        => Assert.Null(TrayMenuCommands.Resolve(id));

    [Theory]
    [InlineData(0x0400)] // NIN_SELECT
    [InlineData(0x0401)] // NIN_KEYSELECT
    [InlineData(0x0203)] // WM_LBUTTONDBLCLK fallback
    public void Resolve_callback_maps_activation_messages(uint message)
        => Assert.Equal(TrayCallbackAction.Open, TrayCallbackMessages.Resolve(message));

    [Theory]
    [InlineData(0x0400)] // NIN_SELECT
    [InlineData(0x0401)] // NIN_KEYSELECT
    public void Immediate_modern_then_legacy_activation_raises_once(uint modernMessage)
    {
        var gate = new TrayActivationGate(500);

        Assert.True(gate.ShouldRaise(modernMessage, 1000));
        Assert.False(gate.ShouldRaise(0x0203, 1001));
    }

    [Theory]
    [InlineData(0x0400)] // NIN_SELECT
    [InlineData(0x0401)] // NIN_KEYSELECT
    public void Immediate_legacy_then_modern_activation_raises_once(uint modernMessage)
    {
        var gate = new TrayActivationGate(500);

        Assert.True(gate.ShouldRaise(0x0203, 1000));
        Assert.False(gate.ShouldRaise(modernMessage, 1001));
    }

    [Fact]
    public void Delayed_unrelated_activation_is_not_suppressed()
    {
        var gate = new TrayActivationGate(500);

        Assert.True(gate.ShouldRaise(0x0203, 1000));
        Assert.True(gate.ShouldRaise(0x0400, 1501));
    }

    [Fact]
    public void Repeated_modern_activations_are_not_suppressed()
    {
        var gate = new TrayActivationGate(500);

        Assert.True(gate.ShouldRaise(0x0400, 1000));
        Assert.True(gate.ShouldRaise(0x0400, 1001));
    }

    [Fact]
    public void Show_add_and_dispose_delete_icon_without_throwing()
    {
        using var tray = new TrayIcon();
        tray.Show();
        tray.Show(); // idempotent
    }
}
