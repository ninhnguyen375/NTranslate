using NTranslate.Core.Requests;

namespace NTranslate.Core.Tests.Requests;

public sealed class RequestCoordinatorTests
{
    [Fact]
    public void BeginCancelsOldLeaseAndAdvancesGeneration()
    {
        using var coordinator = new RequestCoordinator();
        using var first = coordinator.Begin();
        using var second = coordinator.Begin();

        Assert.True(first.Token.IsCancellationRequested);
        Assert.True(second.Generation.Value > first.Generation.Value);
        Assert.False(coordinator.Accepts(first.Generation));
        Assert.True(coordinator.Accepts(second.Generation));
    }

    [Fact]
    public void OldCompletionCannotClearNewRequest()
    {
        using var coordinator = new RequestCoordinator();
        using var first = coordinator.Begin();
        using var second = coordinator.Begin();

        Assert.False(first.TryComplete());
        Assert.True(coordinator.IsInFlight);
        Assert.True(second.TryComplete());
        Assert.False(coordinator.IsInFlight);
        Assert.False(second.TryComplete());
    }

    [Fact]
    public void CancelCurrentRejectsOldResults()
    {
        using var coordinator = new RequestCoordinator();
        using var lease = coordinator.Begin();

        coordinator.CancelCurrent();

        Assert.True(lease.Token.IsCancellationRequested);
        Assert.False(coordinator.Accepts(lease.Generation));
        Assert.False(coordinator.IsInFlight);
    }

    [Fact]
    public void DisposeCancelsActiveToken()
    {
        var coordinator = new RequestCoordinator();
        using var lease = coordinator.Begin();

        coordinator.Dispose();

        Assert.True(lease.Token.IsCancellationRequested);
    }

    [Fact]
    public void OuterCancellationCancelsLease()
    {
        using var outer = new CancellationTokenSource();
        using var coordinator = new RequestCoordinator();
        using var lease = coordinator.Begin(outer.Token);

        outer.Cancel();

        Assert.True(lease.Token.IsCancellationRequested);
    }
}
