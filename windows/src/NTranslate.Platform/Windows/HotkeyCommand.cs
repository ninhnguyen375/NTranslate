namespace NTranslate.Platform.Windows;

internal sealed record NativeCommandResult<T>(T Value, int LastError);

internal sealed class HotkeyCommand<T>(Func<NativeCommandResult<T>> action) : HotkeyCommandHost.ICommand
{
    private readonly object _gate = new();
    private int _state; // 0 queued, 1 running, 2 completed, 3 cancelled
    private NativeCommandResult<T>? _result;
    private Exception? _error;
    public ManualResetEventSlim Done { get; } = new();

    public bool TryStart() { lock (_gate) { if (_state != 0) return false; _state = 1; return true; } }
    public bool TryCancel() { lock (_gate) { if (_state != 0) return false; _state = 3; Done.Set(); return true; } }
    public void Run()
    {
        if (!TryStart()) return;
        try { lock (_gate) _result = action(); }
        catch (Exception error) { lock (_gate) _error = error; }
        finally { lock (_gate) _state = 2; Done.Set(); }
    }
    public void Fail(Exception error)
    {
        lock (_gate)
        {
            if (_state != 0) return;
            _error = error;
            _state = 2;
            Done.Set();
        }
    }

    public NativeCommandResult<T> GetResult()
    {
        lock (_gate)
        {
            if (_state == 3) throw new HotkeyOperationException("Hotkey command timed out.");
            if (_error is not null) throw _error;
            return _result ?? throw new HotkeyOperationException("Hotkey command did not complete.");
        }
    }
}
