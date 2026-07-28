namespace NTranslate.Core.Requests;

/// <summary>
/// Monotonic generation counter that gates stale async completions. Mirrors
/// the macOS app's <c>AsyncGeneration</c>/<c>beginRequest</c>/<c>finishRequest</c>
/// pattern (Sources/translate/PopoverController.swift): starting a request
/// advances the generation; a completion only applies if the generation it
/// was started with still matches current. Invalidating (e.g. source text or
/// language changed) also advances the generation, discarding any in-flight
/// completion even if no new request has started yet. Pure and synchronous;
/// callers own thread affinity (e.g. UI dispatcher) and any cancellation.
/// </summary>
public sealed class RequestCoordinator
{
    private int _generation;

    /// <summary>Starts a new request and returns its generation.</summary>
    public int Begin() => Interlocked.Increment(ref _generation);

    /// <summary>True if <paramref name="generation"/> is still the current one.</summary>
    public bool IsCurrent(int generation) => Volatile.Read(ref _generation) == generation;

    /// <summary>Advances the generation without starting a new request, discarding any in-flight result.</summary>
    public void Invalidate() => Interlocked.Increment(ref _generation);
}
