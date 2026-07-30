using NTranslate.Core.Configuration;
using NTranslate.Core.Credentials;

namespace NTranslate.Core.Settings;

public interface IConfigStore
{
    Task<AppConfig> LoadAsync(CancellationToken token = default);
    Task SaveAsync(AppConfig config, CancellationToken token = default);
}

public sealed record HistoryMigrationReceipt(string SourceRoot, string DestinationRoot, string StagingRoot);

public interface IHistoryDirectoryMigrator
{
    Task<HistoryMigrationReceipt?> PrepareAsync(string currentRoot, string requestedRoot, CancellationToken token = default);
    Task CommitAsync(HistoryMigrationReceipt receipt, CancellationToken token = default);
    Task RollbackAsync(HistoryMigrationReceipt receipt, CancellationToken token = default);
}

public sealed class SettingsValidationException(IReadOnlyList<ConfigValidationIssue> issues)
    : Exception("Settings validation failed.")
{
    public IReadOnlyList<ConfigValidationIssue> Issues { get; } = issues;
}

public sealed class SettingsCommitException(Exception primaryException, IReadOnlyList<Exception> rollbackExceptions)
    : Exception("Settings commit failed.", primaryException)
{
    public Exception PrimaryException { get; } = primaryException;
    public IReadOnlyList<Exception> RollbackExceptions { get; } = rollbackExceptions;
}

public sealed class SettingsSaveCoordinator
{
    private readonly IConfigStore _configStore;
    private readonly IApiKeyStore _apiKeyStore;
    private readonly IHistoryDirectoryMigrator _historyMigrator;
    private readonly Func<AppConfig, double, bool, CancellationToken, Task> _applyRuntime;
    private readonly SemaphoreSlim _saveGate = new(1, 1);

    public SettingsSaveCoordinator(
        IConfigStore configStore,
        IApiKeyStore apiKeyStore,
        IHistoryDirectoryMigrator historyMigrator,
        Func<AppConfig, double, bool, CancellationToken, Task> applyRuntime)
    {
        _configStore = configStore;
        _apiKeyStore = apiKeyStore;
        _historyMigrator = historyMigrator;
        _applyRuntime = applyRuntime;
    }

    public async Task SaveAsync(
        AppConfig config,
        string apiKey,
        double speechRate,
        bool startWithWindows,
        string currentHistoryRoot,
        string requestedHistoryRoot,
        CancellationToken token = default)
    {
        var issues = Validate(config, speechRate, currentHistoryRoot, requestedHistoryRoot);
        if (issues.Count != 0)
            throw new SettingsValidationException(issues);

        await _saveGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            await SaveSerializedAsync(config, apiKey, speechRate, startWithWindows, currentHistoryRoot, requestedHistoryRoot, token).ConfigureAwait(false);
        }
        finally
        {
            _saveGate.Release();
        }
    }

    private async Task SaveSerializedAsync(
        AppConfig config,
        string apiKey,
        double speechRate,
        bool startWithWindows,
        string currentHistoryRoot,
        string requestedHistoryRoot,
        CancellationToken token)
    {
        var currentRoot = NormalizeRoot(currentHistoryRoot);
        var requestedRoot = NormalizeRoot(requestedHistoryRoot);
        HistoryMigrationReceipt? receipt = null;
        string? oldApiKey = null;
        AppConfig? oldConfig = null;
        var credentialAttempted = false;
        var configAttempted = false;

        try
        {
            if (!string.Equals(currentRoot, requestedRoot, StringComparison.OrdinalIgnoreCase))
                receipt = await _historyMigrator.PrepareAsync(currentRoot, requestedRoot, token).ConfigureAwait(false);

            oldApiKey = await _apiKeyStore.LoadAsync(token).ConfigureAwait(false);
            var credentialChanged = !string.Equals(oldApiKey ?? string.Empty, apiKey, StringComparison.Ordinal);

            if (credentialChanged)
            {
                credentialAttempted = true;
                if (string.IsNullOrEmpty(apiKey))
                    await _apiKeyStore.DeleteAsync(token).ConfigureAwait(false);
                else
                    await _apiKeyStore.SaveAsync(apiKey, token).ConfigureAwait(false);
            }

            oldConfig = await _configStore.LoadAsync(token).ConfigureAwait(false);
            var configChanged = !ConfigEquals(oldConfig, config);
            if (configChanged)
            {
                configAttempted = true;
                await _configStore.SaveAsync(config, token).ConfigureAwait(false);
            }

            if (receipt is not null)
                await _historyMigrator.CommitAsync(receipt, token).ConfigureAwait(false);

            if (configChanged)
                await _applyRuntime(config, speechRate, startWithWindows, token).ConfigureAwait(false);
        }
        catch (Exception primaryException)
        {
            var rollbackExceptions = new List<Exception>();
            var rollbackToken = CancellationToken.None;

            if (configAttempted && oldConfig is not null)
                await TryRollbackAsync(() => _configStore.SaveAsync(oldConfig, rollbackToken), rollbackExceptions).ConfigureAwait(false);

            if (credentialAttempted)
            {
                await TryRollbackAsync(
                    () => oldApiKey is null
                        ? _apiKeyStore.DeleteAsync(rollbackToken)
                        : _apiKeyStore.SaveAsync(oldApiKey, rollbackToken),
                    rollbackExceptions).ConfigureAwait(false);
            }

            if (receipt is not null)
                await TryRollbackAsync(() => _historyMigrator.RollbackAsync(receipt, rollbackToken), rollbackExceptions).ConfigureAwait(false);

            if (primaryException is OperationCanceledException && token.IsCancellationRequested && rollbackExceptions.Count == 0)
                throw;

            throw new SettingsCommitException(primaryException, rollbackExceptions);
        }
    }

    private static IReadOnlyList<ConfigValidationIssue> Validate(
        AppConfig config,
        double speechRate,
        string currentHistoryRoot,
        string requestedHistoryRoot)
    {
        var issues = config.Validate().ToList();
        if (!double.IsFinite(speechRate) || speechRate is < 0.5 or > 1.5)
            issues.Add(new(nameof(speechRate), "Must be between 0.5 and 1.5."));
        if (!Path.IsPathFullyQualified(currentHistoryRoot))
            issues.Add(new(nameof(currentHistoryRoot), "Must be an absolute path."));
        if (!Path.IsPathFullyQualified(requestedHistoryRoot))
            issues.Add(new(nameof(requestedHistoryRoot), "Must be an absolute path."));
        return issues;
    }

    private static string NormalizeRoot(string path) =>
        Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));

    private static bool ConfigEquals(AppConfig left, AppConfig right) =>
        left.Languages.SequenceEqual(right.Languages, StringComparer.Ordinal) &&
        left.TargetLanguages.SequenceEqual(right.TargetLanguages, StringComparer.Ordinal) &&
        left with { Languages = right.Languages, TargetLanguages = right.TargetLanguages } == right;

    private static async Task TryRollbackAsync(Func<Task> rollback, List<Exception> exceptions)
    {
        try
        {
            await rollback().ConfigureAwait(false);
        }
        catch (Exception exception)
        {
            exceptions.Add(exception);
        }
    }
}
