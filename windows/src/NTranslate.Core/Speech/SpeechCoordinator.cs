namespace NTranslate.Core.Speech;

public enum SpeechHistoryAudioKind { Source, Result }

public sealed record SpeechPlaybackStateChangedEventArgs(SpeechChannel Channel, SpeechPhase Phase);

public interface ISpeechSynthesisApi
{
    Task<byte[]> SynthesizeAsync(SpeechCacheKey key, CancellationToken cancellationToken);
}

public interface ISpeechPlayer : IAsyncDisposable
{
    event EventHandler? PlaybackEnded;
    event EventHandler<Exception>? PlaybackFailed;
    Task ValidateAsync(ReadOnlyMemory<byte> audio, CancellationToken cancellationToken);
    Task PlayAsync(SpeechChannel channel, ReadOnlyMemory<byte> audio, double rate, CancellationToken cancellationToken);
    void Pause();
    void Resume();
    void Stop();
    void SetRate(double rate);
}

public interface ISpeechHistoryStore
{
    Task AttachAudioAsync(Guid recordId, SpeechHistoryAudioKind kind, ReadOnlyMemory<byte> audio, CancellationToken cancellationToken);
}

public sealed class SpeechCoordinator : IAsyncDisposable
{
    private readonly object sync = new();
    private readonly ISpeechSynthesisApi api;
    private readonly ISpeechPlayer player;
    private readonly ISpeechHistoryStore history;
    private readonly SpeechPlaybackState state = new();
    private readonly Dictionary<SpeechCacheKey, byte[]> cache = [];
    private readonly HashSet<(Guid RecordId, SpeechHistoryAudioKind Kind)> attachments = [];
    private readonly CancellationTokenSource?[] channelCancellation = new CancellationTokenSource?[2];
    private SpeechIdentity? activePlayback;
    private bool disposed;

    public SpeechCoordinator(ISpeechSynthesisApi api, ISpeechPlayer player, ISpeechHistoryStore history)
    {
        this.api = api ?? throw new ArgumentNullException(nameof(api));
        this.player = player ?? throw new ArgumentNullException(nameof(player));
        this.history = history ?? throw new ArgumentNullException(nameof(history));
        player.PlaybackEnded += OnPlaybackEnded;
        player.PlaybackFailed += OnPlaybackFailed;
    }

    public event EventHandler<string>? NonFatalError;
    public event EventHandler<SpeechPlaybackStateChangedEventArgs>? PlaybackStateChanged;

    private void Notify(SpeechChannel channel) =>
        PlaybackStateChanged?.Invoke(this, new(channel, PhaseFor(channel)));

    public SpeechPhase PhaseFor(SpeechChannel channel)
    {
        lock (sync) return state.PhaseFor(channel);
    }

    public async Task PrefetchAsync(SpeechIdentity identity, CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        long generation;
        lock (sync) generation = state.BeginLoading(identity);
        _ = await GetAudioAsync(identity, generation, cancellationToken).ConfigureAwait(false);
        lock (sync)
        {
            if (state.ActionFor(identity) == SpeechButtonAction.Loading)
                state.Invalidate(identity.CacheKey.Channel);
        }
    }

    public async Task TogglePlaybackAsync(SpeechIdentity identity, double rate, CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        SpeechButtonAction action;
        lock (sync) action = state.ActionFor(identity);
        if (action == SpeechButtonAction.Pause)
        {
            player.Pause();
            lock (sync) state.Pause(identity);
            Notify(identity.CacheKey.Channel);
            return;
        }
        if (action == SpeechButtonAction.Resume)
        {
            player.Resume();
            lock (sync) state.Resume(identity);
            Notify(identity.CacheKey.Channel);
            return;
        }

        long generation;
        lock (sync) generation = state.BeginLoading(identity);
        var audio = await GetAudioAsync(identity, generation, cancellationToken).ConfigureAwait(false);
        lock (sync)
        {
            if (state.ActionFor(identity) != SpeechButtonAction.Loading)
                return;
        }
        try
        {
            await player.PlayAsync(identity.CacheKey.Channel, audio, rate, cancellationToken).ConfigureAwait(false);
            SpeechChannel? replacedChannel = null;
            lock (sync)
            {
                if (state.MarkPlaying(identity, generation))
                {
                    if (activePlayback is { } previous && previous.CacheKey.Channel != identity.CacheKey.Channel && state.Finish(previous))
                        replacedChannel = previous.CacheKey.Channel;
                    activePlayback = identity;
                }
                else player.Stop();
            }
            if (replacedChannel is { } channel) Notify(channel);
            Notify(identity.CacheKey.Channel);
        }
        catch (OperationCanceledException)
        {
            lock (sync) state.Invalidate(identity.CacheKey.Channel);
            throw;
        }
        catch
        {
            lock (sync) state.MarkFailed(identity, generation);
            throw;
        }
    }

    public void SetRate(double rate)
    {
        ThrowIfDisposed();
        player.SetRate(rate);
    }

    public void Invalidate(SpeechChannel channel, bool stopPlayback)
    {
        CancellationTokenSource? cancellation;
        lock (sync)
        {
            cancellation = channelCancellation[(int)channel];
            channelCancellation[(int)channel] = null;
            state.Invalidate(channel);
            if (activePlayback?.CacheKey.Channel == channel) activePlayback = null;
        }
        cancellation?.Cancel();
        cancellation?.Dispose();
        if (stopPlayback) player.Stop();
        Notify(channel);
    }

    public void InvalidateAll(bool stopPlayback)
    {
        Invalidate(SpeechChannel.Source, false);
        Invalidate(SpeechChannel.Result, false);
        if (stopPlayback) player.Stop();
    }

    public async ValueTask DisposeAsync()
    {
        if (disposed) return;
        disposed = true;
        InvalidateAll(true);
        player.PlaybackEnded -= OnPlaybackEnded;
        player.PlaybackFailed -= OnPlaybackFailed;
        await player.DisposeAsync().ConfigureAwait(false);
    }

    private async Task<byte[]> GetAudioAsync(SpeechIdentity identity, long generation, CancellationToken cancellationToken)
    {
        byte[]? audio;
        lock (sync) cache.TryGetValue(identity.CacheKey, out audio);
        if (audio is not null)
        {
            await AttachAsync(identity, audio, cancellationToken).ConfigureAwait(false);
            return audio;
        }

        CancellationTokenSource local;
        CancellationToken token;
        lock (sync)
        {
            channelCancellation[(int)identity.CacheKey.Channel]?.Cancel();
            local = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            token = local.Token;
            channelCancellation[(int)identity.CacheKey.Channel] = local;
        }
        try
        {
            audio = await api.SynthesizeAsync(identity.CacheKey, token).ConfigureAwait(false);
            await player.ValidateAsync(audio, token).ConfigureAwait(false);
            lock (sync)
            {
                if (!state.IsLoading(identity, generation))
                    return audio;
                cache[identity.CacheKey] = audio;
            }
            await AttachAsync(identity, audio, token).ConfigureAwait(false);
            return audio;
        }
        catch (OperationCanceledException)
        {
            lock (sync)
            {
                if (state.IsLoading(identity, generation))
                    state.Invalidate(identity.CacheKey.Channel);
            }
            throw;
        }
        catch
        {
            lock (sync) state.MarkFailed(identity, generation);
            throw;
        }
        finally
        {
            lock (sync)
            {
                if (ReferenceEquals(channelCancellation[(int)identity.CacheKey.Channel], local))
                    channelCancellation[(int)identity.CacheKey.Channel] = null;
            }
            local.Dispose();
        }
    }

    private async Task AttachAsync(SpeechIdentity identity, byte[] audio, CancellationToken cancellationToken)
    {
        if (identity.HistoryRecordId is not Guid recordId) return;
        var attachment = (recordId, KindFor(identity.CacheKey.Channel));
        lock (sync)
        {
            if (attachments.Contains(attachment)) return;
        }
        try
        {
            await history.AttachAudioAsync(recordId, attachment.Item2, audio, cancellationToken).ConfigureAwait(false);
            lock (sync) attachments.Add(attachment);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { throw; }
        catch (Exception)
        {
            NonFatalError?.Invoke(this, "Could not attach speech audio to history.");
        }
    }

    private static SpeechHistoryAudioKind KindFor(SpeechChannel channel) =>
        channel == SpeechChannel.Source ? SpeechHistoryAudioKind.Source : SpeechHistoryAudioKind.Result;

    private void OnPlaybackEnded(object? sender, EventArgs args)
    {
        SpeechChannel? channel;
        lock (sync)
        {
            channel = activePlayback?.CacheKey.Channel;
            if (activePlayback is not null) state.Finish(activePlayback);
            activePlayback = null;
        }
        if (channel is not null) Notify(channel.Value);
    }

    private void OnPlaybackFailed(object? sender, Exception exception)
    {
        SpeechChannel? channel;
        lock (sync)
        {
            channel = activePlayback?.CacheKey.Channel;
            if (activePlayback is not null) state.Fail(activePlayback);
            activePlayback = null;
        }
        if (channel is not null) Notify(channel.Value);
        NonFatalError?.Invoke(this, "Speech playback failed.");
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(disposed, this);
}
