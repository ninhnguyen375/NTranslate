using NTranslate.App;

namespace NTranslate.App.Tests;

public sealed class AppShutdownTests
{
    [Fact]
    public void Shutdown_IsIdempotentAndOrdered()
    {
        var calls = new List<string>();
        var shutdown = new AppShutdown(
            () => calls.Add("cancel"),
            () => calls.Add("unregister"),
            () => calls.Add("tray"),
            () => calls.Add("wndproc"),
            () => calls.Add("close"));

        shutdown.Run();
        shutdown.Run();

        Assert.Equal(["cancel", "unregister", "tray", "wndproc", "close"], calls);
    }

    [Fact]
    public void Shutdown_WhenStepFails_StillRunsRemainingSteps()
    {
        var calls = new List<string>();
        var shutdown = new AppShutdown(
            () => calls.Add("cancel"),
            () => { calls.Add("unregister"); throw new InvalidOperationException("failed"); },
            () => calls.Add("tray"),
            () => calls.Add("wndproc"),
            () => calls.Add("close"));

        Assert.Throws<AggregateException>(shutdown.Run);

        Assert.Equal(["cancel", "unregister", "tray", "wndproc", "close"], calls);
    }
}
