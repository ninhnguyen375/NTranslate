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
}
