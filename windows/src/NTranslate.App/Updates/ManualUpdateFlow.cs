using NTranslate.Core.Updates;

namespace NTranslate.App.Updates;

public interface IUpdateDialog
{
    Task<bool> ShowAsync(UpdateState state, string? message, string? releaseNotes, CancellationToken token);
}

public sealed class ManualUpdateFlow(UpdateCoordinator coordinator, IUpdateDialog dialog)
{
    public async Task RunAsync(CancellationToken token)
    {
        await dialog.ShowAsync(UpdateState.Checking, "Checking for updates…", null, token).ConfigureAwait(false);
        await coordinator.CheckAsync(manual: true, token).ConfigureAwait(false);
        if (await dialog.ShowAsync(coordinator.State, coordinator.StatusMessage, coordinator.ReleaseNotes, token).ConfigureAwait(false) &&
            coordinator.State == UpdateState.Available)
            await coordinator.InstallAsync(token).ConfigureAwait(false);
    }
}

public static class CurrentVersionResolver
{
    public static SemanticVersion Resolve(Func<Version> packagedVersion, Version? assemblyVersion)
    {
        try
        {
            var version = packagedVersion();
            return new(version.Major, version.Minor, version.Build);
        }
        catch (Exception error) when (error is InvalidOperationException or TypeInitializationException)
        {
            return assemblyVersion is null ? new(0, 0, 0) : new(assemblyVersion.Major, assemblyVersion.Minor, Math.Max(0, assemblyVersion.Build));
        }
    }
}
