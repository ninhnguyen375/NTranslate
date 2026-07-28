namespace NTranslate.Core.Requests;

public readonly record struct RequestGeneration(long Value);

public sealed class RequestCoordinator : IDisposable
{
    private readonly object _gate = new();
    private long _generation;
    private CancellationTokenSource? _current;
    private bool _disposed;

    public RequestGeneration Current
    {
        get { lock (_gate) return new(_generation); }
    }

    public bool IsInFlight
    {
        get { lock (_gate) return _current is not null; }
    }

    public RequestLease Begin(CancellationToken outerCancellationToken = default)
    {
        CancellationTokenSource? previous;
        RequestLease lease;
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            previous = _current;
            _current = CancellationTokenSource.CreateLinkedTokenSource(outerCancellationToken);
            lease = new RequestLease(this, new(++_generation), _current);
        }
        previous?.Cancel();
        return lease;
    }

    public bool Accepts(RequestGeneration generation)
    {
        lock (_gate) return !_disposed && _current is not null && generation.Value == _generation;
    }

    public void CancelCurrent()
    {
        CancellationTokenSource? current;
        lock (_gate)
        {
            if (_disposed)
                return;
            current = _current;
            _current = null;
            _generation++;
        }
        current?.Cancel();
    }

    internal bool TryComplete(RequestGeneration generation, CancellationTokenSource source)
    {
        lock (_gate)
        {
            if (_disposed || generation.Value != _generation || !ReferenceEquals(_current, source))
                return false;
            _current = null;
            return true;
        }
    }

    public void Dispose()
    {
        CancellationTokenSource? current;
        lock (_gate)
        {
            if (_disposed)
                return;
            _disposed = true;
            current = _current;
            _current = null;
            _generation++;
        }
        current?.Cancel();
    }
}

public sealed class RequestLease : IDisposable
{
    private readonly RequestCoordinator _coordinator;
    private readonly CancellationTokenSource _source;
    private int _completed;

    internal RequestLease(RequestCoordinator coordinator, RequestGeneration generation, CancellationTokenSource source)
    {
        _coordinator = coordinator;
        Generation = generation;
        _source = source;
    }

    public RequestGeneration Generation { get; }
    public CancellationToken Token => _source.Token;

    public bool TryComplete() =>
        Interlocked.Exchange(ref _completed, 1) == 0 && _coordinator.TryComplete(Generation, _source);

    public void Dispose() => TryComplete();
}
