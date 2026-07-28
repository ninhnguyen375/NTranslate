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
    public void Partial_send_releases_only_keys_left_down()
    {
        List<CopyInput[]> calls = [];
        var results = new Queue<uint>([2, 2]);

        var error = Assert.Throws<InvalidOperationException>(() =>
            SendInputCopyCommand.SendCopy(inputs =>
            {
                calls.Add(inputs);
                return results.Dequeue();
            }, () => 0));

        Assert.Equal("SendInput sent 2 of 4 copy events.", error.Message);
        Assert.Equal([new(0x43, true), new(0x11, true)], calls[1]);
    }

    [Theory]
    [InlineData(1, 0x11)]
    [InlineData(3, 0x11)]
    public void Partial_send_releases_each_key_still_down(uint sent, ushort expectedKey)
    {
        List<CopyInput[]> calls = [];

        Assert.Throws<InvalidOperationException>(() =>
            SendInputCopyCommand.SendCopy(inputs =>
            {
                calls.Add(inputs);
                return calls.Count == 1 ? sent : 0;
            }, () => 0));

        Assert.Equal([new(expectedKey, true)], calls[1]);
    }

    [Fact]
    public void Cleanup_failure_preserves_original_partial_send_failure()
    {
        var calls = 0;

        var error = Assert.Throws<InvalidOperationException>(() =>
            SendInputCopyCommand.SendCopy(_ => ++calls == 1 ? 2u : 0u, () => 5));

        Assert.Equal("SendInput sent 2 of 4 copy events.", error.Message);
        Assert.Equal(2, calls);
    }

    [Fact]
    public void Cleanup_exception_preserves_original_partial_send_failure()
    {
        var calls = 0;

        var error = Assert.Throws<InvalidOperationException>(() =>
            SendInputCopyCommand.SendCopy(_ => ++calls == 1 ? 2u : throw new InvalidOperationException("cleanup failed"), () => 0));

        Assert.Equal("SendInput sent 2 of 4 copy events.", error.Message);
    }

    [Fact]
    public void Failed_send_reports_partial_count_and_zero_send_win32_error()
    {
        Assert.Equal("SendInput sent 2 of 4 copy events.", SendInputCopyCommand.CreateFailureMessage(2, 0));
        Assert.Equal("SendInput sent 0 of 4 copy events (Win32 error 5).", SendInputCopyCommand.CreateFailureMessage(0, 5));
    }
}
