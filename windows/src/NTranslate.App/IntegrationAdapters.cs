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
using NTranslate.Platform.Diagnostics;
using NTranslate.Platform.Media;
using NTranslate.Platform.Storage;
using NTranslate.App.Updates;

namespace NTranslate.App;

internal sealed class HistoryRuntime(string root) : ITranslationHistoryStore, ICrashLogService
{
    private sealed record Services(string Root, JsonTranslationHistoryStore History, CrashLogService Crashes);
    private Services _services = Create(root);

    public string Root => Volatile.Read(ref _services).Root;
    public IReadOnlyList<TranslationRecord> Records => Volatile.Read(ref _services).History.Records;
    public string? LoadError => Volatile.Read(ref _services).History.LoadError;
    public string LogsDirectory => Volatile.Read(ref _services).Crashes.LogsDirectory;

    public void SwitchHistoryRuntime(string root) => Interlocked.Exchange(ref _services, Create(root));
    public Task AppendAsync(TranslationRecord record, CancellationToken token = default) => Volatile.Read(ref _services).History.AppendAsync(record, token);
    public Task SetSavedAsync(Guid id, bool saved, CancellationToken token = default) => Volatile.Read(ref _services).History.SetSavedAsync(id, saved, token);
    public Task AttachAudioAsync(Guid id, TranslationAudioKind kind, ReadOnlyMemory<byte> data, CancellationToken token = default) => Volatile.Read(ref _services).History.AttachAudioAsync(id, kind, data, token);
    public Task<byte[]?> ReadAudioAsync(Guid id, TranslationAudioKind kind, CancellationToken token = default) => Volatile.Read(ref _services).History.ReadAudioAsync(id, kind, token);
    public Task RemoveAsync(IReadOnlySet<Guid> ids, CancellationToken token = default) => Volatile.Read(ref _services).History.RemoveAsync(ids, token);
    public Task RecordAsync(Exception exception, CancellationToken token = default) => Volatile.Read(ref _services).Crashes.RecordAsync(exception, token);
    public Task<NTranslate.Core.Recovery.CrashLogSummary?> GetNewestUnacknowledgedAsync(CancellationToken token = default) => Volatile.Read(ref _services).Crashes.GetNewestUnacknowledgedAsync(token);
    public Task AcknowledgeAsync(string fileName, CancellationToken token = default) => Volatile.Read(ref _services).Crashes.AcknowledgeAsync(fileName, token);

    private static Services Create(string root)
    {
        var fullRoot = Path.GetFullPath(root);
        return new(fullRoot, new JsonTranslationHistoryStore(fullRoot), new CrashLogService(fullRoot, new AtomicFileWriter()));
    }
}

internal sealed class JsonConfigStore(string path) : IConfigStore
{
    public async Task<AppConfig> LoadAsync(CancellationToken token = default) =>
        File.Exists(path)
            ? ConfigJson.Parse(await File.ReadAllTextAsync(path, token).ConfigureAwait(false)).Config
            : AppConfig.Default;

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

internal sealed class HistoryDeleteConfirmation(Func<XamlRoot?> resolveRoot)
{
    public async Task<bool> ConfirmAsync(IReadOnlyList<TranslationRecord> records, CancellationToken token)
    {
        var root = resolveRoot() ?? throw new InvalidOperationException("History delete confirmation owner is unavailable.");
        var scope = records.Count == 1 ? "this translation" : $"these {records.Count} visible translations";
        var dialog = new ContentDialog
        {
            Title = "Delete history?",
            Content = $"Permanently delete {scope}?",
            PrimaryButtonText = "Delete",
            CloseButtonText = "Cancel",
            DefaultButton = ContentDialogButton.Close,
            XamlRoot = root
        };
        return await dialog.ShowAsync().AsTask(token) == ContentDialogResult.Primary;
    }
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

internal sealed class UpdateDialog(Func<XamlRoot?> resolveRoot) : IUpdateDialog
{
    public async Task<bool> ShowAsync(UpdateState state, string? message, string? releaseNotes, CancellationToken token)
    {
        var dialog = new ContentDialog
        {
            Title = state switch
            {
                UpdateState.Checking => "Checking for updates",
                UpdateState.Available => "Update available",
                UpdateState.Error => "Update check failed",
                _ => "NTranslate is current"
            },
            Content = string.IsNullOrWhiteSpace(releaseNotes) ? message : $"{message}\n\n{releaseNotes}",
            PrimaryButtonText = state == UpdateState.Available ? "Install" : null,
            CloseButtonText = "Close",
            XamlRoot = resolveRoot() ?? throw new InvalidOperationException("Update dialog owner is unavailable.")
        };
        return await dialog.ShowAsync().AsTask(token) == ContentDialogResult.Primary;
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
