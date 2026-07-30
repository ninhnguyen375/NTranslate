using NTranslate.Core.Speech;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Storage.Streams;

namespace NTranslate.Platform.Media;

public sealed class WindowsSpeechPlayer : ISpeechPlayer
{
    internal const string Mp3ContentType = "audio/mpeg";

    private readonly MediaPlayer player = new();
    private readonly SemaphoreSlim mediaGate = new(1, 1);
    private readonly object stateGate = new();
    private InMemoryRandomAccessStream? stream;
    private TaskCompletionSource? mediaOpen;
    private SpeechChannel? activeChannel;
    private bool hasMediaEventSubscriptions;
    private bool disposed;

    public WindowsSpeechPlayer()
    {
        player.MediaOpened += OnMediaOpened;
        player.MediaEnded += OnMediaEnded;
        player.MediaFailed += OnMediaFailed;
        hasMediaEventSubscriptions = true;
    }

    public event EventHandler? PlaybackEnded;
    public event EventHandler<Exception>? PlaybackFailed;
    public SpeechChannel? ActiveChannel { get { lock (stateGate) return activeChannel; } }
    public double PlaybackRate => WithMediaGate(() => player.PlaybackSession.PlaybackRate);
    internal bool HasMediaEventSubscriptions { get { lock (stateGate) return hasMediaEventSubscriptions; } }

    public async Task ValidateAsync(ReadOnlyMemory<byte> audio, CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        cancellationToken.ThrowIfCancellationRequested();
        await mediaGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ThrowIfDisposed();
            await OpenAsync(audio, cancellationToken).ConfigureAwait(false);
            StopCore();
        }
        finally
        {
            mediaGate.Release();
        }
    }

    public async Task PlayAsync(
        SpeechChannel channel,
        ReadOnlyMemory<byte> audio,
        double rate,
        CancellationToken cancellationToken)
    {
        ThrowIfDisposed();
        cancellationToken.ThrowIfCancellationRequested();
        await mediaGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            ThrowIfDisposed();
            StopCore();
            await OpenAsync(audio, cancellationToken).ConfigureAwait(false);
            SetRateCore(rate);
            lock (stateGate) activeChannel = channel;
            player.Play();
        }
        finally
        {
            mediaGate.Release();
        }
    }

    public void Pause() => WithMediaGate(player.Pause);

    public void Resume() => WithMediaGate(() =>
    {
        if (ActiveChannel is not null)
            player.Play();
    });

    public void Stop() => WithMediaGate(StopCore);

    private void StopCore()
    {
        player.Pause();
        player.Source = null;
        stream?.Dispose();
        stream = null;
        lock (stateGate) activeChannel = null;
    }

    public void SetRate(double rate) => WithMediaGate(() => SetRateCore(rate));

    private void SetRateCore(double rate)
    {
        player.PlaybackSession.PlaybackRate = Math.Clamp(
            double.IsFinite(rate) ? rate : 1,
            0.5,
            1.5);
    }

    public async ValueTask DisposeAsync()
    {
        await mediaGate.WaitAsync().ConfigureAwait(false);
        try
        {
            if (disposed) return;

            player.MediaOpened -= OnMediaOpened;
            player.MediaEnded -= OnMediaEnded;
            player.MediaFailed -= OnMediaFailed;
            StopCore();
            player.Dispose();
            lock (stateGate)
            {
                hasMediaEventSubscriptions = false;
                disposed = true;
            }
        }
        finally
        {
            mediaGate.Release();
        }
    }

    private async Task OpenAsync(ReadOnlyMemory<byte> audio, CancellationToken cancellationToken)
    {
        if (audio.IsEmpty)
            throw new ArgumentException("Audio cannot be empty.", nameof(audio));

        var nextStream = new InMemoryRandomAccessStream();
        try
        {
            await nextStream.WriteAsync(audio.ToArray().AsBuffer()).AsTask(cancellationToken).ConfigureAwait(false);
            nextStream.Seek(0);
        }
        catch
        {
            nextStream.Dispose();
            throw;
        }

        stream?.Dispose();
        stream = nextStream;
        var open = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (stateGate) mediaOpen = open;
        using var registration = cancellationToken.Register(
            static state => ((TaskCompletionSource)state!).TrySetCanceled(), open);
        player.Source = MediaSource.CreateFromStream(stream, Mp3ContentType);

        try
        {
            await open.Task.ConfigureAwait(false);
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
            lock (stateGate)
            {
                if (ReferenceEquals(mediaOpen, open)) mediaOpen = null;
            }
        }
    }

    private void OnMediaOpened(MediaPlayer sender, object args)
    {
        TaskCompletionSource? open;
        lock (stateGate) open = mediaOpen;
        open?.TrySetResult();
    }

    private void OnMediaEnded(MediaPlayer sender, object args)
    {
        lock (stateGate) activeChannel = null;
        PlaybackEnded?.Invoke(this, EventArgs.Empty);
    }

    private void OnMediaFailed(MediaPlayer sender, MediaPlayerFailedEventArgs args)
    {
        var exception = new InvalidDataException($"Audio playback failed: {args.ErrorMessage}");
        TaskCompletionSource? open;
        lock (stateGate)
        {
            open = mediaOpen;
            activeChannel = null;
        }
        open?.TrySetException(exception);
        PlaybackFailed?.Invoke(this, exception);
    }

    private void WithMediaGate(Action action)
    {
        mediaGate.Wait();
        try
        {
            ThrowIfDisposed();
            action();
        }
        finally
        {
            mediaGate.Release();
        }
    }

    private T WithMediaGate<T>(Func<T> action)
    {
        mediaGate.Wait();
        try
        {
            ThrowIfDisposed();
            return action();
        }
        finally
        {
            mediaGate.Release();
        }
    }

    private void ThrowIfDisposed()
    {
        lock (stateGate) ObjectDisposedException.ThrowIf(disposed, this);
    }
}
