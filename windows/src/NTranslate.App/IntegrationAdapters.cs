using System.Diagnostics;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using NTranslate.App.History;
using NTranslate.App.Recovery;
using NTranslate.Core.Configuration;
using NTranslate.Core.History;
using NTranslate.Core.OpenAI;
using NTranslate.Core.Settings;
using NTranslate.Core.Speech;
using NTranslate.Platform.Media;
using NTranslate.Platform.Storage;

namespace NTranslate.App;

internal sealed class JsonConfigStore(string path) : IConfigStore
{
    public async Task<AppConfig> LoadAsync(CancellationToken token = default) =>
        ConfigJson.Parse(await File.ReadAllTextAsync(path, token).ConfigureAwait(false)).Config;

    public async Task SaveAsync(AppConfig config, CancellationToken token = default)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        await new AtomicFileWriter().WriteAsync(path, System.Text.Encoding.UTF8.GetBytes(ConfigJson.Serialize(config)), token).ConfigureAwait(false);
    }
}

internal sealed class OpenAiSpeechApi(OpenAiCompatibleClient client, Func<AppConfig> config, Func<CancellationToken, Task<string>> apiKey) : ISpeechSynthesisApi
{
    public async Task<byte[]> SynthesizeAsync(SpeechCacheKey key, CancellationToken cancellationToken) =>
        await client.SynthesizeSpeechAsync(new Uri(config().ApiSpeechUrl!), await apiKey(cancellationToken).ConfigureAwait(false), new(key.Model, key.Text), cancellationToken).ConfigureAwait(false);
}

internal sealed class SpeechHistoryAdapter(ITranslationHistoryStore store) : ISpeechHistoryStore
{
    public Task AttachAudioAsync(Guid recordId, SpeechHistoryAudioKind kind, ReadOnlyMemory<byte> audio, CancellationToken cancellationToken) =>
        store.AttachAudioAsync(recordId, kind == SpeechHistoryAudioKind.Source ? TranslationAudioKind.Source : TranslationAudioKind.Result, audio, cancellationToken);
}

internal sealed class HistoryAudioPlayer : IHistoryAudioPlayer
{
    private readonly WindowsSpeechPlayer _player = new();
    public Task PlayAsync(ReadOnlyMemory<byte> audio, CancellationToken token) => _player.PlayAsync(SpeechChannel.Result, audio, 1, token);
    public void Stop() => _player.Stop();
    public ValueTask DisposeAsync() => _player.DisposeAsync();
}

internal sealed class RecoveryNotice(Func<XamlRoot?> resolveRoot) : IRecoveryNotice
{
    public async Task<RecoveryNoticeChoice> ShowAsync(NTranslate.Core.Recovery.CrashLogSummary summary, CancellationToken token)
    {
        var root = resolveRoot() ?? throw new InvalidOperationException("Recovery notice owner is unavailable.");
        var dialog = new ContentDialog
        {
            Title = "NTranslate recovered from an error",
            Content = $"{summary.ExceptionType}: {summary.Message}",
            PrimaryButtonText = "Open logs",
            CloseButtonText = "Dismiss",
            XamlRoot = root
        };
        return await dialog.ShowAsync().AsTask(token) == ContentDialogResult.Primary
            ? RecoveryNoticeChoice.OpenLogs
            : RecoveryNoticeChoice.Dismiss;
    }
}

internal sealed class ShellLogDirectoryLauncher : ILogDirectoryLauncher
{
    public Task OpenAsync(string path, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        Process.Start(new ProcessStartInfo(path) { UseShellExecute = true });
        return Task.CompletedTask;
    }
}
