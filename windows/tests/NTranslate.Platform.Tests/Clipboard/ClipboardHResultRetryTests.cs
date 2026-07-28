using System.Runtime.InteropServices;
using NTranslate.Platform.Clipboard;

namespace NTranslate.Platform.Tests.Clipboard;

public sealed class ClipboardHResultRetryTests
{
    private const int ClipboardCannotOpen = unchecked((int)0x800401D0);

    [Fact]
    public void Transient_cannot_open_then_success_retries_exact_attempts()
    {
        var attempts = 0;
        var delays = 0;

        ClipboardHResultRetry.Run(
            () => ++attempts < 3 ? ClipboardCannotOpen : 0,
            () => delays++);

        Assert.Equal(3, attempts);
        Assert.Equal(2, delays);
    }

    [Fact]
    public void Non_transient_failure_throws_immediately()
    {
        var attempts = 0;
        var delays = 0;

        var exception = Assert.Throws<COMException>(() => ClipboardHResultRetry.Run(
            () =>
            {
                attempts++;
                return unchecked((int)0x80004005);
            },
            () => delays++));

        Assert.Equal(unchecked((int)0x80004005), exception.HResult);
        Assert.Equal(1, attempts);
        Assert.Equal(0, delays);
    }

    [Fact]
    public void Exhausted_cannot_open_throws()
    {
        var attempts = 0;
        var delays = 0;

        var exception = Assert.Throws<COMException>(() => ClipboardHResultRetry.Run(
            () =>
            {
                attempts++;
                return ClipboardCannotOpen;
            },
            () => delays++));

        Assert.Equal(ClipboardCannotOpen, exception.HResult);
        Assert.Equal(3, attempts);
        Assert.Equal(2, delays);
    }
}
