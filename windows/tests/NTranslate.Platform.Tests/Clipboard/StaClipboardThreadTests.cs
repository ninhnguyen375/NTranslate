using NTranslate.Platform.Clipboard;

namespace NTranslate.Platform.Tests.Clipboard;

public sealed class StaClipboardThreadTests
{
    [Fact]
    public void Dispatcher_host_propagates_work_exceptions()
    {
        var exception = Assert.Throws<InvalidOperationException>(() =>
            StaClipboardThread.Invoke<int>(() => throw new InvalidOperationException("clipboard failure")));

        Assert.Equal("clipboard failure", exception.Message);
    }
}
