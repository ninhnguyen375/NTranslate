namespace NTranslate.Platform.Windows;

internal class HotkeyCommandHost
{
    private readonly object _gate = new();
    private readonly Queue<ICommand> _queue = [];
    private Exception? _terminal;
    private bool _running;

    public HotkeyCommand<T> Enqueue<T>(Func<NativeCommandResult<T>> action)
    {
        lock (_gate)
        {
            if (_terminal is not null) throw new HotkeyOperationException(_terminal.Message);
            var command = new HotkeyCommand<T>(action);
            _queue.Enqueue(command);
            return command;
        }
    }

    public bool RunNext()
    {
        ICommand? command;
        lock (_gate)
        {
            if (_running || _queue.Count == 0) return false;
            command = _queue.Dequeue();
            _running = true;
        }
        try { command.Run(); }
        finally { lock (_gate) _running = false; }
        return true;
    }

    public void Terminal(Exception error)
    {
        ICommand[] pending;
        lock (_gate)
        {
            if (_terminal is not null) return;
            _terminal = error;
            pending = _queue.ToArray();
            _queue.Clear();
        }
        foreach (var command in pending) command.Fail(error);
    }

    internal interface ICommand { void Run(); void Fail(Exception error); }
}

internal sealed class NativeMessageCommandQueue : HotkeyCommandHost;
