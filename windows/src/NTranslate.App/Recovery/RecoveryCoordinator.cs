using NTranslate.Core.Recovery;
using NTranslate.Platform.Diagnostics;

namespace NTranslate.App.Recovery;

public enum RecoveryNoticeChoice { Dismiss, OpenLogs }

public interface IRecoveryNotice
{
    Task<RecoveryNoticeChoice> ShowAsync(CrashLogSummary summary, CancellationToken token);
}

public interface ILogDirectoryLauncher
{
    Task OpenAsync(string path, CancellationToken token);
}

public sealed class RecoveryCoordinator(
    ICrashLogService crashLogs,
    IRecoveryNotice notice,
    ILogDirectoryLauncher logsLauncher,
    Func<Func<Task<RecoveryNoticeChoice>>, Task<RecoveryNoticeChoice>>? dispatchNotice = null)
{
    private readonly Func<Func<Task<RecoveryNoticeChoice>>, Task<RecoveryNoticeChoice>> _dispatchNotice = dispatchNotice ?? (show => show());
    private readonly SemaphoreSlim _gate = new(1, 1);
    private bool _checked;

    public async Task ShowPendingAsync(CancellationToken token = default)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (_checked) return;
            _checked = true;
            var summary = await crashLogs.GetNewestUnacknowledgedAsync(token).ConfigureAwait(false);
            if (summary is null) return;
            var choice = await _dispatchNotice(() => notice.ShowAsync(summary, token)).ConfigureAwait(false);
            if (choice == RecoveryNoticeChoice.OpenLogs)
                await logsLauncher.OpenAsync(crashLogs.LogsDirectory, token).ConfigureAwait(false);
            await crashLogs.AcknowledgeAsync(summary.FileName, token).ConfigureAwait(false);
        }
        finally { _gate.Release(); }
    }
}
