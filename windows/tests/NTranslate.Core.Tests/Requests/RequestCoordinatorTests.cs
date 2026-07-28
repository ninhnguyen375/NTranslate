using NTranslate.Core.Requests;

namespace NTranslate.Core.Tests.Requests;

public sealed class RequestCoordinatorTests
{
    [Fact]
    public void BeginAdvancesGenerationAndIsCurrentForNewestOnly()
    {
        var coordinator = new RequestCoordinator();

        var first = coordinator.Begin();
        var second = coordinator.Begin();

        Assert.NotEqual(first, second);
        Assert.False(coordinator.IsCurrent(first));
        Assert.True(coordinator.IsCurrent(second));
    }

    [Fact]
    public void OlderCompletionLosesToNewerRequest()
    {
        var coordinator = new RequestCoordinator();

        var stale = coordinator.Begin();
        coordinator.Begin();

        Assert.False(coordinator.IsCurrent(stale));
    }

    [Fact]
    public void InvalidateDiscardsInFlightCompletionEvenWithoutNewRequest()
    {
        var coordinator = new RequestCoordinator();
        var generation = coordinator.Begin();

        coordinator.Invalidate();

        Assert.False(coordinator.IsCurrent(generation));
    }
}
