using System.Windows.Input;

namespace NTranslate.App.Popup;

/// <summary>
/// Minimal async-capable <see cref="ICommand"/>. Written locally instead of
/// pulling in a third-party MVVM package: <see cref="ExecuteAsync"/> lets
/// callers await completion (e.g. from tests), while <see cref="CanExecute"/>
/// reflects whether the command is already running.
/// </summary>
public interface IAsyncCommand : ICommand
{
    Task ExecuteAsync();
}

public sealed class AsyncRelayCommand(Func<Task> execute, Func<bool>? canExecute = null) : IAsyncCommand
{
    private bool _isExecuting;

    public event EventHandler? CanExecuteChanged;

    public bool CanExecute(object? parameter) => !_isExecuting && (canExecute?.Invoke() ?? true);

    public async Task ExecuteAsync()
    {
        if (!CanExecute(null))
            return;

        _isExecuting = true;
        RaiseCanExecuteChanged();
        try
        {
            await execute().ConfigureAwait(true);
        }
        finally
        {
            _isExecuting = false;
            RaiseCanExecuteChanged();
        }
    }

    public void Execute(object? parameter) => _ = ExecuteAsync();

    public void RaiseCanExecuteChanged() => CanExecuteChanged?.Invoke(this, EventArgs.Empty);
}
