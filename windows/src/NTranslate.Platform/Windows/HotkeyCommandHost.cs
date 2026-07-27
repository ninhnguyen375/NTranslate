namespace NTranslate.Platform.Windows;

internal sealed class HotkeyCommandHost
{
    private readonly Queue<ICommand> _queue = [];
    private Exception? _terminal;

    public HotkeyCommand<T> Enqueue<T>(Func<NativeCommandResult<T>> action)
    {
        if (_terminal is not null) throw new HotkeyOperationException(_terminal.Message);
        var command = new HotkeyCommand<T>(action);
        _queue.Enqueue(command);
        return command;
    }

    public void RunNext()
    {
        if (_queue.Count == 0) return;
        _queue.Dequeue().Run();
    }

    public void Terminal(Exception error)
    {
        _terminal ??= error;
        while (_queue.TryDequeue(out var command)) command.Fail(_terminal);
    }

    internal interface ICommand { void Run(); void Fail(Exception error); }
}
