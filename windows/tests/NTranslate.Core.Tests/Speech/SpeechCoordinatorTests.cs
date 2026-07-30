using NTranslate.Core.Configuration;
using NTranslate.Core.Speech;

namespace NTranslate.Core.Tests.Speech;

public sealed class SpeechCoordinatorTests
{
    private static readonly byte[] ValidAudio = [1, 2, 3];

    [Fact]
    public void JapaneseModelResolverIsCaseInsensitive() =>
        Assert.Equal(AppConfig.Default.SpeechSourceModelJapanese, SpeechModelResolver.Resolve("jApAnEsE", AppConfig.Default));

    [Fact]
    public async Task PlaybackStateChangesCoverPlayPauseResumeEndFailureAndInvalidation()
    {
        await using var fixture = new Fixture();
        var states = new List<(SpeechChannel Channel, SpeechPhase Phase)>();
        fixture.Coordinator.PlaybackStateChanged += (_, change) => states.Add((change.Channel, change.Phase));
        var identity = Identity(SpeechChannel.Source);

        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);
        fixture.Player.RaiseEnded();
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);
        fixture.Player.RaiseFailed();
        fixture.Coordinator.Invalidate(SpeechChannel.Source, true);

        Assert.Contains((SpeechChannel.Source, SpeechPhase.Playing), states);
        Assert.Contains((SpeechChannel.Source, SpeechPhase.Paused), states);
        Assert.True(states.Count(state => state == (SpeechChannel.Source, SpeechPhase.Playing)) >= 2);
        Assert.Contains((SpeechChannel.Source, SpeechPhase.Failed), states);
        Assert.Equal((SpeechChannel.Source, SpeechPhase.Idle), states[^1]);
    }

    [Fact]
    public async Task PlayingNewChannelReturnsPreviousChannelToIdle()
    {
        await using var fixture = new Fixture();
        var states = new List<(SpeechChannel Channel, SpeechPhase Phase)>();
        fixture.Coordinator.PlaybackStateChanged += (_, change) => states.Add((change.Channel, change.Phase));

        await fixture.Coordinator.TogglePlaybackAsync(Identity(SpeechChannel.Source), 1, CancellationToken.None);
        await fixture.Coordinator.TogglePlaybackAsync(Identity(SpeechChannel.Result), 1, CancellationToken.None);

        Assert.Equal(SpeechPhase.Idle, fixture.Coordinator.PhaseFor(SpeechChannel.Source));
        Assert.Equal(SpeechPhase.Playing, fixture.Coordinator.PhaseFor(SpeechChannel.Result));
        Assert.Contains((SpeechChannel.Source, SpeechPhase.Idle), states);
    }

    [Fact]
    public async Task ToggleFetchesValidatesCachesAndPlays()
    {
        await using var fixture = new Fixture();
        var identity = Identity(SpeechChannel.Source);

        await fixture.Coordinator.TogglePlaybackAsync(identity, 1.2, CancellationToken.None);
        fixture.Player.RaiseEnded();
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1.2, CancellationToken.None);

        Assert.Equal(1, fixture.Api.CallCount);
        Assert.Equal(1, fixture.Player.ValidateCount);
        Assert.Equal(2, fixture.Player.PlayCount);
    }

    [Fact]
    public async Task InvalidAudioIsNotCachedOrAttachedToHistory()
    {
        await using var fixture = new Fixture();
        fixture.Api.Audio = [0];
        var identity = Identity(SpeechChannel.Result, Guid.NewGuid());

        await Assert.ThrowsAsync<InvalidDataException>(() => fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None));
        fixture.Api.Audio = ValidAudio;
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);

        Assert.Equal(2, fixture.Api.CallCount);
        Assert.Single(fixture.History.Attachments);
    }

    [Fact]
    public async Task PauseAndResumeDoNotFetchOrReplay()
    {
        await using var fixture = new Fixture();
        var identity = Identity(SpeechChannel.Source);
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);

        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);

        Assert.Equal(1, fixture.Api.CallCount);
        Assert.Equal(1, fixture.Player.PlayCount);
        Assert.Equal(1, fixture.Player.PauseCount);
        Assert.Equal(1, fixture.Player.ResumeCount);
    }

    [Fact]
    public async Task SourceAndResultCancellationAreIndependent()
    {
        await using var fixture = new Fixture();
        var sourceFetch = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        var resultFetch = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Api.Handler = (key, token) => (key.Channel == SpeechChannel.Source ? sourceFetch.Task : resultFetch.Task).WaitAsync(token);

        var sourceTask = fixture.Coordinator.PrefetchAsync(Identity(SpeechChannel.Source), CancellationToken.None);
        var resultTask = fixture.Coordinator.PrefetchAsync(Identity(SpeechChannel.Result), CancellationToken.None);
        fixture.Coordinator.Invalidate(SpeechChannel.Source, stopPlayback: false);
        resultFetch.SetResult(ValidAudio);

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => sourceTask);
        await resultTask;
        Assert.Equal(SpeechPhase.Idle, fixture.Coordinator.PhaseFor(SpeechChannel.Source));
        Assert.Equal(SpeechPhase.Idle, fixture.Coordinator.PhaseFor(SpeechChannel.Result));
    }

    [Fact]
    public async Task StaleFetchCannotPlay()
    {
        await using var fixture = new Fixture();
        var fetch = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Api.Handler = (_, _) => fetch.Task;
        var identity = Identity(SpeechChannel.Source);

        var playTask = fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);
        fixture.Coordinator.Invalidate(SpeechChannel.Source, stopPlayback: false);
        fetch.SetResult(ValidAudio);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => playTask);

        Assert.Equal(0, fixture.Player.PlayCount);
        Assert.Equal(SpeechPhase.Idle, fixture.Coordinator.PhaseFor(SpeechChannel.Source));
    }

    [Fact]
    public async Task CanceledRequestDoesNotInvalidateNewerRequestOnSameChannel()
    {
        await using var fixture = new Fixture();
        var firstStarted = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var secondAudio = new TaskCompletionSource<byte[]>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Api.Handler = async (key, token) =>
        {
            if (key.Text == "first")
            {
                firstStarted.SetResult();
                await Task.Delay(Timeout.Infinite, token);
            }
            return await secondAudio.Task.WaitAsync(token);
        };
        var first = new SpeechIdentity(new(SpeechChannel.Source, "first", "model"), null);
        var second = new SpeechIdentity(new(SpeechChannel.Source, "second", "model"), null);

        var firstTask = fixture.Coordinator.TogglePlaybackAsync(first, 1, CancellationToken.None);
        await firstStarted.Task;
        var secondTask = fixture.Coordinator.TogglePlaybackAsync(second, 1, CancellationToken.None);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => firstTask);
        secondAudio.SetResult(ValidAudio);
        await secondTask;
        fixture.Player.RaiseEnded();
        await fixture.Coordinator.TogglePlaybackAsync(second, 1, CancellationToken.None);

        Assert.Equal(2, fixture.Api.CallCount);
        Assert.Equal(1, fixture.Player.ValidateCount);
        Assert.Equal(2, fixture.Player.PlayCount);
    }

    [Fact]
    public async Task PrefetchCachesWithoutPlaying()
    {
        await using var fixture = new Fixture();
        var identity = Identity(SpeechChannel.Result);

        await fixture.Coordinator.PrefetchAsync(identity, CancellationToken.None);
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);

        Assert.Equal(1, fixture.Api.CallCount);
        Assert.Equal(1, fixture.Player.PlayCount);
    }

    [Theory]
    [InlineData(SpeechChannel.Source, SpeechHistoryAudioKind.Source)]
    [InlineData(SpeechChannel.Result, SpeechHistoryAudioKind.Result)]
    public async Task AttachesValidatedAudioToExactHistoryRecordAndKind(SpeechChannel channel, SpeechHistoryAudioKind expectedKind)
    {
        await using var fixture = new Fixture();
        var recordId = Guid.NewGuid();

        await fixture.Coordinator.PrefetchAsync(Identity(channel, recordId), CancellationToken.None);

        var attachment = Assert.Single(fixture.History.Attachments);
        Assert.Equal(recordId, attachment.RecordId);
        Assert.Equal(expectedKind, attachment.Kind);
        Assert.Equal(ValidAudio, attachment.Audio);
    }

    [Fact]
    public async Task CachedAudioAttachesToLaterHistoryRecord()
    {
        await using var fixture = new Fixture();
        var first = Identity(SpeechChannel.Result);
        var later = first with { HistoryRecordId = Guid.NewGuid() };

        await fixture.Coordinator.PrefetchAsync(first, CancellationToken.None);
        await fixture.Coordinator.PrefetchAsync(later, CancellationToken.None);

        Assert.Equal(1, fixture.Api.CallCount);
        Assert.Equal(later.HistoryRecordId, Assert.Single(fixture.History.Attachments).RecordId);
    }

    [Fact]
    public async Task CancellationReturnsChannelToIdle()
    {
        await using var fixture = new Fixture();
        fixture.Api.Handler = (_, token) => WaitForever(token);
        using var cancellation = new CancellationTokenSource();
        var task = fixture.Coordinator.TogglePlaybackAsync(Identity(SpeechChannel.Source), 1, cancellation.Token);

        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => task);
        Assert.Equal(SpeechPhase.Idle, fixture.Coordinator.PhaseFor(SpeechChannel.Source));
    }

    [Fact]
    public async Task HistoryFailureKeepsMemoryCacheAndRaisesNonfatalError()
    {
        await using var fixture = new Fixture();
        fixture.History.Error = new IOException("disk unavailable");
        string? error = null;
        fixture.Coordinator.NonFatalError += (_, message) => error = message;
        var identity = Identity(SpeechChannel.Result, Guid.NewGuid());

        await fixture.Coordinator.PrefetchAsync(identity, CancellationToken.None);
        fixture.History.Error = null;
        await fixture.Coordinator.TogglePlaybackAsync(identity, 1, CancellationToken.None);

        Assert.Equal("Could not attach speech audio to history.", error);
        Assert.Equal(1, fixture.Api.CallCount);
        Assert.Equal(1, fixture.Player.PlayCount);
    }

    private static async Task<byte[]> WaitForever(CancellationToken token)
    {
        await Task.Delay(Timeout.Infinite, token);
        return [];
    }

    private static SpeechIdentity Identity(SpeechChannel channel, Guid? recordId = null) =>
        new(new SpeechCacheKey(channel, channel == SpeechChannel.Source ? "source" : "result", "model"), recordId);

    private sealed class Fixture : IAsyncDisposable
    {
        public FakeApi Api { get; } = new();
        public FakePlayer Player { get; } = new();
        public FakeHistory History { get; } = new();
        public SpeechCoordinator Coordinator { get; }

        public Fixture() => Coordinator = new SpeechCoordinator(Api, Player, History);
        public ValueTask DisposeAsync() => Coordinator.DisposeAsync();
    }

    private sealed class FakeApi : ISpeechSynthesisApi
    {
        public byte[] Audio { get; set; } = ValidAudio;
        public int CallCount { get; private set; }
        public Func<SpeechCacheKey, CancellationToken, Task<byte[]>>? Handler { get; set; }
        public Task<byte[]> SynthesizeAsync(SpeechCacheKey key, CancellationToken cancellationToken)
        {
            CallCount++;
            return Handler?.Invoke(key, cancellationToken) ?? Task.FromResult(Audio);
        }
    }

    private sealed class FakePlayer : ISpeechPlayer
    {
        public event EventHandler? PlaybackEnded;
        public event EventHandler<Exception>? PlaybackFailed;
        public int ValidateCount { get; private set; }
        public int PlayCount { get; private set; }
        public int PauseCount { get; private set; }
        public int ResumeCount { get; private set; }
        public Task ValidateAsync(ReadOnlyMemory<byte> audio, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            ValidateCount++;
            if (audio.Span[0] == 0) throw new InvalidDataException("invalid audio");
            return Task.CompletedTask;
        }
        public Task PlayAsync(SpeechChannel channel, ReadOnlyMemory<byte> audio, double rate, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            PlayCount++;
            return Task.CompletedTask;
        }
        public void Pause() => PauseCount++;
        public void Resume() => ResumeCount++;
        public void Stop() { }
        public void SetRate(double rate) { }
        public void RaiseEnded() => PlaybackEnded?.Invoke(this, EventArgs.Empty);
        public void RaiseFailed() => PlaybackFailed?.Invoke(this, new IOException("playback failed"));
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private sealed class FakeHistory : ISpeechHistoryStore
    {
        public List<Attachment> Attachments { get; } = [];
        public Exception? Error { get; set; }
        public Task AttachAudioAsync(Guid recordId, SpeechHistoryAudioKind kind, ReadOnlyMemory<byte> audio, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (Error is not null) throw Error;
            Attachments.Add(new(recordId, kind, audio.ToArray()));
            return Task.CompletedTask;
        }
    }

    private sealed record Attachment(Guid RecordId, SpeechHistoryAudioKind Kind, byte[] Audio);
}
