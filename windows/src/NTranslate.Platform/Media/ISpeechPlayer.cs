using NTranslate.Core.Speech;

namespace NTranslate.Platform.Media;

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
