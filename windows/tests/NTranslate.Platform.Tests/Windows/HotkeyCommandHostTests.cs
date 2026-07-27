using NTranslate.Platform.Windows;

namespace NTranslate.Platform.Tests.Windows;

public sealed class HotkeyCommandHostTests
{
    [Fact]
    public void RunNext_returns_per_command_error_without_leaking_to_next()
    {
        var host = new HotkeyCommandHost();
        var failed = host.Enqueue<int>(() => throw new InvalidOperationException("first"));
        var passed = host.Enqueue(() => new NativeCommandResult<int>(2, 0));

        host.RunNext();
        host.RunNext();

        Assert.Throws<InvalidOperationException>(() => failed.GetResult());
        Assert.Equal(2, passed.GetResult().Value);
    }

    [Fact]
    public void Cancelled_queued_command_does_not_run()
    {
        var host = new HotkeyCommandHost();
        var called = false;
        var command = host.Enqueue(() => { called = true; return new NativeCommandResult<bool>(true, 0); });

        Assert.True(command.TryCancel());
        host.RunNext();

        Assert.False(called);
        Assert.Throws<HotkeyOperationException>(() => command.GetResult());
    }

    [Fact]
    public void Terminal_completes_pending_and_rejects_future_commands()
    {
        var host = new HotkeyCommandHost();
        var command = host.Enqueue(() => new NativeCommandResult<bool>(true, 0));

        host.Terminal(new HotkeyOperationException("stopped"));

        Assert.Throws<HotkeyOperationException>(() => command.GetResult());
        Assert.Throws<HotkeyOperationException>(() => host.Enqueue(() => new NativeCommandResult<bool>(true, 0)));
    }
}
