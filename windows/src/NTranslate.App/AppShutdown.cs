namespace NTranslate.App;

internal sealed class AppShutdown(
    Action cancel,
    Action unregisterHotkey,
    Action deleteTray,
    Action restoreWndProc,
    Action closeWindow)
{
    private int _started;

    public void Run()
    {
        if (Interlocked.Exchange(ref _started, 1) != 0)
            return;

        List<Exception> errors = [];
        foreach (var step in new[] { cancel, unregisterHotkey, deleteTray, restoreWndProc, closeWindow })
        {
            try { step(); }
            catch (Exception error) { errors.Add(error); }
        }
        if (errors.Count > 0)
            throw new AggregateException("Application shutdown failed.", errors);
    }
}
