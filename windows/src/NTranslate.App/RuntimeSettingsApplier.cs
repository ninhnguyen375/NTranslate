using NTranslate.Core.Configuration;
using NTranslate.Core.Settings;

namespace NTranslate.App;

internal sealed class RuntimeSettingsApplier(
    Func<(AppConfig Config, bool StartWithWindows)> snapshot,
    Func<AppConfig, CancellationToken, Task> applyConfig,
    Func<bool, CancellationToken, Task> applyStartup)
{
    public async Task ApplyRuntimeAsync(AppConfig config, double speechRate, bool startWithWindows, CancellationToken token)
    {
        var previous = snapshot();
        var requested = config with { SpeechRate = speechRate, StartWithWindows = startWithWindows };
        var configChanged = !ConfigEquals(previous.Config, requested);
        var startupChanged = previous.StartWithWindows != startWithWindows;
        var configAttempted = false;
        var startupAttempted = false;
        try
        {
            if (configChanged)
            {
                configAttempted = true;
                await applyConfig(requested, token).ConfigureAwait(false);
            }
            if (startupChanged)
            {
                startupAttempted = true;
                await applyStartup(startWithWindows, token).ConfigureAwait(false);
            }
        }
        catch (Exception primaryException)
        {
            var rollbackExceptions = new List<Exception>();
            if (configAttempted)
                await TryRollbackAsync(() => applyConfig(previous.Config, CancellationToken.None), rollbackExceptions).ConfigureAwait(false);
            if (startupAttempted)
                await TryRollbackAsync(() => applyStartup(previous.StartWithWindows, CancellationToken.None), rollbackExceptions).ConfigureAwait(false);
            if (rollbackExceptions.Count != 0)
                throw new SettingsCommitException(primaryException, rollbackExceptions);
            throw;
        }
    }

    private static async Task TryRollbackAsync(Func<Task> rollback, List<Exception> exceptions)
    {
        try { await rollback().ConfigureAwait(false); }
        catch (Exception exception) { exceptions.Add(exception); }
    }

    private static bool ConfigEquals(AppConfig left, AppConfig right) =>
        left.Languages.SequenceEqual(right.Languages, StringComparer.Ordinal) &&
        left.TargetLanguages.SequenceEqual(right.TargetLanguages, StringComparer.Ordinal) &&
        left with { Languages = right.Languages, TargetLanguages = right.TargetLanguages } == right;
}
