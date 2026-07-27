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
    public async Task Parallel_runners_select_only_one_command()
    {
        var host = new HotkeyCommandHost();
        using var started = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        host.Enqueue(() => { started.Set(); release.Wait(); return new NativeCommandResult<bool>(true, 0); });

        var first = Task.Run(host.RunNext);
        started.Wait();
        Assert.False(host.RunNext());
        release.Set();
        Assert.True(await first);
    }

    [Fact]
    public void Terminal_signals_every_queued_command()
    {
        var host = new HotkeyCommandHost();
        var commands = Enumerable.Range(0, 3).Select(_ => host.Enqueue(() => new NativeCommandResult<bool>(true, 0))).ToArray();

        host.Terminal(new HotkeyOperationException("stopped"));

        Assert.All(commands, command => Assert.True(command.Done.Wait(TimeSpan.Zero)));
        Assert.All(commands, command => Assert.Throws<HotkeyOperationException>(() => command.GetResult()));
    }

    [Fact]
    public async Task Runner_and_terminal_complete_running_and_queued_commands()
    {
        var host = new HotkeyCommandHost();
        using var started = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        var running = host.Enqueue(() => { started.Set(); release.Wait(); return new NativeCommandResult<int>(1, 0); });
        var queued = host.Enqueue(() => new NativeCommandResult<int>(2, 0));
        var runner = Task.Run(host.RunNext);
        started.Wait();

        host.Terminal(new HotkeyOperationException("stopped"));
        release.Set();
        await runner;

        Assert.Equal(1, running.GetResult().Value);
        Assert.True(queued.Done.Wait(TimeSpan.Zero));
        Assert.Throws<HotkeyOperationException>(() => queued.GetResult());
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
