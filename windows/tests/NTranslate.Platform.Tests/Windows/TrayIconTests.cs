using NTranslate.Platform.Windows;

namespace NTranslate.Platform.Tests.Windows;

public sealed class TrayIconTests
{
    [Fact]
    public void Resolve_maps_open_command_id()
        => Assert.Equal(TrayCommand.Open, TrayMenuCommands.Resolve(1001));

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

    [Fact]
    public void Show_add_and_dispose_delete_icon_without_throwing()
    {
        using var tray = new TrayIcon();
        tray.Show();
        tray.Show(); // idempotent
    }
}
