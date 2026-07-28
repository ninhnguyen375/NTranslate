using NTranslate.Core.Speech;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage.Streams;

namespace NTranslate.Platform.Media;

public sealed class WindowsSpeechPlayer : ISpeechPlayer
{
    private readonly MediaPlayer player = new();
    private InMemoryRandomAccessStream? stream;
    private TaskCompletionSource? mediaOpen;
    private bool disposed;

    public WindowsSpeechPlayer()
    {
        player.MediaOpened += OnMediaOpened;
        player.MediaEnded += OnMediaEnded;
        player.MediaFailed += OnMediaFailed;
        HasMediaEventSubscriptions = true;
    }

    public event EventHandler? PlaybackEnded;
    public event EventHandler<Exception>? PlaybackFailed;
    public SpeechChannel? ActiveChannel { get; private set; }
    public double PlaybackRate => player.PlaybackSession.PlaybackRate;
    internal bool HasMediaEventSubscriptions { get; private set; }

    public async Task ValidateAsync(ReadOnlyMemory<byte> audio, CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        cancellationToken.ThrowIfCancellationRequested();
        await OpenAsync(audio, cancellationToken).ConfigureAwait(false);
        Stop();
    }

    public async Task PlayAsync(
        SpeechChannel channel,
        ReadOnlyMemory<byte> audio,
        double rate,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        cancellationToken.ThrowIfCancellationRequested();
        Stop();
        await OpenAsync(audio, cancellationToken).ConfigureAwait(false);
        SetRate(rate);
        ActiveChannel = channel;
        player.Play();
    }

    public void Pause()
    {
        ThrowIfDisposed();
        player.Pause();
    }

    public void Resume()
    {
        ThrowIfDisposed();
        if (ActiveChannel is not null)
            player.Play();
    }

    public void Stop()
    {
        ThrowIfDisposed();
        player.Pause();
        player.Source = null;
        stream?.Dispose();
        stream = null;
        ActiveChannel = null;
    }

    public void SetRate(double rate)
    {
        ThrowIfDisposed();
        player.PlaybackSession.PlaybackRate = Math.Clamp(
            double.IsFinite(rate) ? rate : 1,
            0.5,
            1.5);
    }

    public ValueTask DisposeAsync()
    {
        if (disposed)
            return ValueTask.CompletedTask;

        player.MediaOpened -= OnMediaOpened;
        player.MediaEnded -= OnMediaEnded;
        player.MediaFailed -= OnMediaFailed;
        HasMediaEventSubscriptions = false;
        player.Source = null;
        stream?.Dispose();
        stream = null;
        ActiveChannel = null;
        player.Dispose();
        disposed = true;
        return ValueTask.CompletedTask;
    }

    private async Task OpenAsync(ReadOnlyMemory<byte> audio, CancellationToken cancellationToken)
    {
        if (audio.IsEmpty)
            throw new ArgumentException("Audio cannot be empty.", nameof(audio));

        var nextStream = new InMemoryRandomAccessStream();
        try
        {
            await nextStream.AsStreamForWrite().WriteAsync(audio, cancellationToken).ConfigureAwait(false);
            nextStream.Seek(0);
        }
        catch
        {
            nextStream.Dispose();
            throw;
        }

        stream?.Dispose();
        stream = nextStream;
        mediaOpen = new(TaskCreationOptions.RunContinuationsAsynchronously);
        using var registration = cancellationToken.Register(
            static state => ((TaskCompletionSource)state!).TrySetCanceled(), mediaOpen);
        player.Source = MediaSource.CreateFromStream(stream, "audio/mpeg");

        try
        {
            await mediaOpen.Task.ConfigureAwait(false);
        }
        catch
        {
            player.Source = null;
            stream?.Dispose();
            stream = null;
            throw;
        }
        finally
        {
            mediaOpen = null;
        }
    }

    private void OnMediaOpened(MediaPlayer sender, object args) => mediaOpen?.TrySetResult();

    private void OnMediaEnded(MediaPlayer sender, object args)
    {
        ActiveChannel = null;
        PlaybackEnded?.Invoke(this, EventArgs.Empty);
    }

    private void OnMediaFailed(MediaPlayer sender, MediaPlayerFailedEventArgs args)
    {
        var exception = new InvalidDataException($"Audio playback failed: {args.ErrorMessage}");
        mediaOpen?.TrySetException(exception);
        ActiveChannel = null;
        PlaybackFailed?.Invoke(this, exception);
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(disposed, this);
}
