using System.ComponentModel;
using System.Runtime.CompilerServices;
using NTranslate.Core.History;

namespace NTranslate.App.History;

public interface IHistoryAudioPlayer : IAsyncDisposable
{
    Task PlayAsync(ReadOnlyMemory<byte> audio, CancellationToken token);
    void Stop();
}

public sealed class HistoryViewModel : INotifyPropertyChanged, IAsyncDisposable
{
    private readonly ITranslationHistoryStore _store;
    private readonly IHistoryAudioPlayer _audioPlayer;
    private readonly Func<IReadOnlyList<TranslationRecord>, CancellationToken, Task<bool>> _confirmDelete;
    private readonly Func<TranslationRecord, CancellationToken, Task> _reopen;
    private readonly Func<DateTimeOffset> _now;
    private readonly TimeZoneInfo _timeZone;
    private readonly Func<Action, Task> _dispatchUi;
    private TranslationRecord[] _records = [];
    private IReadOnlyList<TranslationRecord> _visibleRecords = [];
    private string _query = string.Empty;
    private bool _savedOnly;
    private HistoryTimeRange _timeRange;
    private string? _errorMessage;
    private int _generation;
    private bool _disposed;

    public HistoryViewModel(
        ITranslationHistoryStore store,
        IHistoryAudioPlayer audioPlayer,
        Func<IReadOnlyList<TranslationRecord>, CancellationToken, Task<bool>> confirmDelete,
        Func<TranslationRecord, CancellationToken, Task> reopen,
        Func<DateTimeOffset>? now = null,
        TimeZoneInfo? timeZone = null,
        Func<Action, Task>? dispatchUi = null)
    {
        _store = store;
        _audioPlayer = audioPlayer;
        _confirmDelete = confirmDelete;
        _reopen = reopen;
        _now = now ?? (() => DateTimeOffset.Now);
        _timeZone = timeZone ?? TimeZoneInfo.Local;
        _dispatchUi = dispatchUi ?? (action => { action(); return Task.CompletedTask; });
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public IReadOnlyList<TranslationRecord> VisibleRecords
    {
        get => _visibleRecords;
        private set { _visibleRecords = value; OnPropertyChanged(); }
    }

    public string Query
    {
        get => _query;
        set { if (_query == value) return; _query = value; OnPropertyChanged(); ApplyFilter(); }
    }

    public bool SavedOnly
    {
        get => _savedOnly;
        set { if (_savedOnly == value) return; _savedOnly = value; OnPropertyChanged(); ApplyFilter(); }
    }

    public HistoryTimeRange TimeRange
    {
        get => _timeRange;
        set { if (_timeRange == value) return; _timeRange = value; OnPropertyChanged(); ApplyFilter(); }
    }

    public string? ErrorMessage
    {
        get => _errorMessage;
        private set { _errorMessage = value; OnPropertyChanged(); }
    }

    public bool CanMutate => !_disposed && _store.LoadError is null;

    public async Task ReloadAsync(CancellationToken token)
    {
        ThrowIfDisposed();
        token.ThrowIfCancellationRequested();
        var generation = Interlocked.Increment(ref _generation);
        var records = _store.Records.ToArray();
        var loadError = _store.LoadError;
        await _dispatchUi(() =>
        {
            if (_disposed || generation != Volatile.Read(ref _generation) || token.IsCancellationRequested) return;
            _records = records;
            ErrorMessage = loadError;
            OnPropertyChanged(nameof(CanMutate));
            ApplyFilter();
        }).ConfigureAwait(false);
    }

    public async Task SetSavedAsync(TranslationRecord record, bool saved, CancellationToken token)
    {
        ThrowIfDisposed();
        if (!CanMutate) return;
        var generation = Interlocked.Increment(ref _generation);
        try
        {
            await _store.SetSavedAsync(record.Id, saved, token).ConfigureAwait(false);
            await RefreshAfterMutationAsync(generation, token).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            await SetErrorAsync(ex.Message, generation, token).ConfigureAwait(false);
        }
    }

    public async Task PlayAudioAsync(TranslationRecord record, TranslationAudioKind kind, CancellationToken token)
    {
        ThrowIfDisposed();
        var generation = Interlocked.Increment(ref _generation);
        try
        {
            var audio = await _store.ReadAudioAsync(record.Id, kind, token).ConfigureAwait(false);
            if (audio is null)
            {
                await SetErrorAsync("Cached audio is unavailable.", generation, token).ConfigureAwait(false);
                return;
            }
            await _audioPlayer.PlayAsync(audio, token).ConfigureAwait(false);
            await SetErrorAsync(null, generation, token).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            await SetErrorAsync(ex.Message, generation, token).ConfigureAwait(false);
        }
    }

    public Task DeleteAsync(TranslationRecord record, CancellationToken token) => DeleteSnapshotAsync([record], token);

    public Task DeleteVisibleAsync(CancellationToken token) => DeleteSnapshotAsync(VisibleRecords.ToArray(), token);

    public async Task ReopenAsync(TranslationRecord record, CancellationToken token)
    {
        ThrowIfDisposed();
        token.ThrowIfCancellationRequested();
        _audioPlayer.Stop();
        await _reopen(record, token).ConfigureAwait(false);
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        _disposed = true;
        Interlocked.Increment(ref _generation);
        _audioPlayer.Stop();
        await _audioPlayer.DisposeAsync().ConfigureAwait(false);
    }

    private async Task DeleteSnapshotAsync(IReadOnlyList<TranslationRecord> snapshot, CancellationToken token)
    {
        ThrowIfDisposed();
        if (!CanMutate || snapshot.Count == 0) return;
        var generation = Interlocked.Increment(ref _generation);
        if (!await _confirmDelete(snapshot, token).ConfigureAwait(false)) return;
        try
        {
            await _store.RemoveAsync(snapshot.Select(record => record.Id).ToHashSet(), token).ConfigureAwait(false);
            await RefreshAfterMutationAsync(generation, token).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            await SetErrorAsync(ex.Message, generation, token).ConfigureAwait(false);
        }
    }

    private Task RefreshAfterMutationAsync(int generation, CancellationToken token)
    {
        var records = _store.Records.ToArray();
        return _dispatchUi(() =>
        {
            if (_disposed || generation != Volatile.Read(ref _generation) || token.IsCancellationRequested) return;
            _records = records;
            ErrorMessage = null;
            ApplyFilter();
        });
    }

    private Task SetErrorAsync(string? error, int generation, CancellationToken token) => _dispatchUi(() =>
    {
        if (_disposed || generation != Volatile.Read(ref _generation) || token.IsCancellationRequested) return;
        ErrorMessage = error;
    });

    private void ApplyFilter() => VisibleRecords = HistoryFilter.Apply(
        _records,
        new HistoryFilterOptions(Query, SavedOnly, TimeRange),
        _now(),
        _timeZone);

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
