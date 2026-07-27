using NTranslate.Platform.Input;

namespace NTranslate.Platform.Tests.Input;

public sealed class SendInputCopyCommandTests
{
    [Fact]
    public void Copy_input_sequence_has_control_and_c_down_then_c_and_control_up()
    {
        var inputs = SendInputCopyCommand.CreateCopyInputs();

        Assert.Equal(4, inputs.Length);
        Assert.Equal(new ushort[] { 0x11, 0x43, 0x43, 0x11 }, inputs.Select(input => input.VirtualKey));
        Assert.Equal(new[] { false, false, true, true }, inputs.Select(input => input.KeyUp));
    }

    [Fact]
    public void Failed_send_reports_partial_count_and_zero_send_win32_error()
    {
        Assert.Equal("SendInput sent 2 of 4 copy events.", SendInputCopyCommand.CreateFailureMessage(2, 0));
        Assert.Equal("SendInput sent 0 of 4 copy events (Win32 error 5).", SendInputCopyCommand.CreateFailureMessage(0, 5));
    }
}
