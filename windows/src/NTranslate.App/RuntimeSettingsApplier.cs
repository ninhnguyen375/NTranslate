using NTranslate.Core.Configuration;

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
        try
        {
            await applyConfig(requested, token).ConfigureAwait(false);
            await applyStartup(startWithWindows, token).ConfigureAwait(false);
        }
        catch
        {
            await applyConfig(previous.Config, CancellationToken.None).ConfigureAwait(false);
            await applyStartup(previous.StartWithWindows, CancellationToken.None).ConfigureAwait(false);
            throw;
        }
    }
}
