using NTranslate.Core.Speech;
using NTranslate.Platform.Media;

namespace NTranslate.Platform.Tests.Media;

[Collection("Windows media")]
public sealed class WindowsSpeechPlayerTests
{
    private static readonly string FixtureDirectory = Path.GetFullPath(
        Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "Media"));
    private static readonly byte[] ValidMp3 = File.ReadAllBytes(Path.Combine(FixtureDirectory, "valid.mp3"));
    private static readonly byte[] InvalidAudio = File.ReadAllBytes(Path.Combine(FixtureDirectory, "invalid.bin"));

    [Fact]
    public async Task ValidateAsync_accepts_valid_MP3()
    {
        await using var player = new WindowsSpeechPlayer();

        await player.ValidateAsync(ValidMp3, CancellationToken.None);
    }

    [Fact]
    public async Task ValidateAsync_rejects_invalid_audio()
    {
        await using var player = new WindowsSpeechPlayer();

        await Assert.ThrowsAnyAsync<Exception>(() =>
            player.ValidateAsync(InvalidAudio, CancellationToken.None));
    }

    [Fact]
    public async Task ValidateAsync_honors_pre_cancellation()
    {
        await using var player = new WindowsSpeechPlayer();
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            player.ValidateAsync(ValidMp3, cancellation.Token));
    }

    [Theory]
    [InlineData(7, 1.5)]
    [InlineData(-1, 0.5)]
    [InlineData(double.NaN, 1)]
    public async Task PlayAsync_normalizes_rate(double rate, double expected)
    {
        await using var player = new WindowsSpeechPlayer();

        await player.PlayAsync(SpeechChannel.Source, ValidMp3, rate, CancellationToken.None);

        Assert.Equal(expected, player.PlaybackRate);
    }

    [Fact]
    public async Task PlayAsync_tracks_active_channel()
    {
        await using var player = new WindowsSpeechPlayer();

        await player.PlayAsync(SpeechChannel.Source, ValidMp3, 1, CancellationToken.None);

        Assert.Equal(SpeechChannel.Source, player.ActiveChannel);
    }

    [Fact]
    public async Task PlayAsync_rejects_invalid_audio_without_marking_channel_active()
    {
        await using var player = new WindowsSpeechPlayer();

        await Assert.ThrowsAnyAsync<Exception>(() =>
            player.PlayAsync(SpeechChannel.Source, InvalidAudio, 1, CancellationToken.None));

        Assert.Null(player.ActiveChannel);
    }

    [Fact]
    public async Task PlayAsync_honors_pre_cancellation()
    {
        await using var player = new WindowsSpeechPlayer();
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            player.PlayAsync(SpeechChannel.Source, ValidMp3, 1, cancellation.Token));

        Assert.Null(player.ActiveChannel);
    }

    [Fact]
    public async Task SetRate_normalizes_rate()
    {
        await using var player = new WindowsSpeechPlayer();

        player.SetRate(0);

        Assert.Equal(0.5, player.PlaybackRate);
    }

    [Fact]
    public async Task Pause_and_resume_preserve_active_channel()
    {
        await using var player = new WindowsSpeechPlayer();
        await player.PlayAsync(SpeechChannel.Source, ValidMp3, 1, CancellationToken.None);

        player.Pause();
        player.Resume();

        Assert.Equal(SpeechChannel.Source, player.ActiveChannel);
    }

    [Fact]
    public async Task Playing_new_channel_replaces_old_channel()
    {
        await using var player = new WindowsSpeechPlayer();
        await player.PlayAsync(SpeechChannel.Source, ValidMp3, 1, CancellationToken.None);

        await player.PlayAsync(SpeechChannel.Result, ValidMp3, 1, CancellationToken.None);

        Assert.Equal(SpeechChannel.Result, player.ActiveChannel);
    }

    [Fact]
    public async Task Stop_clears_active_channel()
    {
        await using var player = new WindowsSpeechPlayer();
        await player.PlayAsync(SpeechChannel.Source, ValidMp3, 1, CancellationToken.None);

        player.Stop();

        Assert.Null(player.ActiveChannel);
    }

    [Fact]
    public async Task DisposeAsync_unsubscribes_media_events()
    {
        var player = new WindowsSpeechPlayer();
        Assert.True(player.HasMediaEventSubscriptions);

        await player.DisposeAsync();

        Assert.False(player.HasMediaEventSubscriptions);
    }
}

[CollectionDefinition("Windows media", DisableParallelization = true)]
public sealed class WindowsMediaCollection;
