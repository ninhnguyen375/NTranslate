using NTranslate.Core.Speech;

namespace NTranslate.Core.Tests.Speech;

public sealed class SpeechPlaybackStateTests
{
    private static readonly SpeechIdentity Source = new(
        new SpeechCacheKey(SpeechChannel.Source, "source", "model"), Guid.NewGuid());
    private static readonly SpeechIdentity Result = new(
        new SpeechCacheKey(SpeechChannel.Result, "result", "model"), Guid.NewGuid());

    [Fact]
    public void ChannelsHaveIndependentState()
    {
        var state = new SpeechPlaybackState();

        var generation = state.BeginLoading(Source);

        Assert.Equal(SpeechButtonAction.Loading, state.ActionFor(Source));
        Assert.Equal(SpeechButtonAction.Play, state.ActionFor(Result));
        Assert.Equal(SpeechPhase.Loading, state.PhaseFor(SpeechChannel.Source));
        Assert.Equal(SpeechPhase.Idle, state.PhaseFor(SpeechChannel.Result));
        Assert.True(state.MarkPlaying(Source, generation));
        Assert.Equal(SpeechButtonAction.Pause, state.ActionFor(Source));
        Assert.Equal(SpeechButtonAction.Play, state.ActionFor(Result));
    }

    [Fact]
    public void SupportsLoadPlayPauseResumeAndFinish()
    {
        var state = new SpeechPlaybackState();
        var generation = state.BeginLoading(Source);

        Assert.True(state.MarkPlaying(Source, generation));
        Assert.True(state.Pause(Source));
        Assert.Equal(SpeechButtonAction.Resume, state.ActionFor(Source));
        Assert.True(state.Resume(Source));
        Assert.Equal(SpeechButtonAction.Pause, state.ActionFor(Source));
        Assert.True(state.Finish(Source));
        Assert.Equal(SpeechButtonAction.Play, state.ActionFor(Source));
        Assert.Equal(SpeechPhase.Idle, state.PhaseFor(SpeechChannel.Source));
    }

    [Fact]
    public void RejectsWrongIdentityEvenWhenCacheKeyMatches()
    {
        var state = new SpeechPlaybackState();
        var laterRecord = Source with { HistoryRecordId = Guid.NewGuid() };
        var generation = state.BeginLoading(Source);

        Assert.Equal(Source.CacheKey, laterRecord.CacheKey);
        Assert.False(state.MarkPlaying(laterRecord, generation));
        Assert.False(state.Pause(laterRecord));
        Assert.Equal(SpeechButtonAction.Play, state.ActionFor(laterRecord));
        Assert.Equal(SpeechButtonAction.Loading, state.ActionFor(Source));
    }

    [Fact]
    public void RejectsStaleGeneration()
    {
        var state = new SpeechPlaybackState();
        var staleGeneration = state.BeginLoading(Source);
        var currentGeneration = state.BeginLoading(Source);

        Assert.True(currentGeneration > staleGeneration);
        Assert.False(state.MarkPlaying(Source, staleGeneration));
        Assert.True(state.MarkPlaying(Source, currentGeneration));
    }

    [Fact]
    public void FailedMapsToRetryAndCanLoadAgain()
    {
        var state = new SpeechPlaybackState();
        var generation = state.BeginLoading(Source);

        Assert.True(state.MarkFailed(Source, generation));
        Assert.Equal(SpeechPhase.Failed, state.PhaseFor(SpeechChannel.Source));
        Assert.Equal(SpeechButtonAction.Retry, state.ActionFor(Source));

        state.BeginLoading(Source);
        Assert.Equal(SpeechButtonAction.Loading, state.ActionFor(Source));
    }

    [Fact]
    public void InvalidatingChannelRejectsItsPendingGenerationOnly()
    {
        var state = new SpeechPlaybackState();
        var sourceGeneration = state.BeginLoading(Source);
        var resultGeneration = state.BeginLoading(Result);

        state.Invalidate(SpeechChannel.Source);

        Assert.False(state.MarkPlaying(Source, sourceGeneration));
        Assert.True(state.MarkPlaying(Result, resultGeneration));
    }
}
