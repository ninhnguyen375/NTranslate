using NTranslate.Platform.Clipboard;
using NTranslate.Platform.Input;

namespace NTranslate.Platform.Capture;

public sealed class SelectionCaptureService : ISelectionCaptureService
{
    public static readonly TimeSpan CopyTimeout = TimeSpan.FromMilliseconds(250);
    public static readonly TimeSpan CopyPollInterval = TimeSpan.FromMilliseconds(10);

    private static readonly SemaphoreSlim SimulatedCopyMutex = new(1, 1);

    private readonly IUiAutomationSelectionReader _uiAutomation;
    private readonly IClipboardService _clipboard;
    private readonly ISimulatedCopyCommand _copy;
    private readonly TimeSpan _copyTimeout;
    private readonly TimeSpan _pollInterval;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay;

    public SelectionCaptureService(
        IUiAutomationSelectionReader uiAutomation,
        IClipboardService clipboard,
        ISimulatedCopyCommand copy,
        TimeSpan? copyTimeout = null,
        TimeSpan? pollInterval = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null)
    {
        _uiAutomation = uiAutomation;
        _clipboard = clipboard;
        _copy = copy;
        _copyTimeout = copyTimeout ?? CopyTimeout;
        _pollInterval = pollInterval ?? CopyPollInterval;
        _delay = delay ?? Task.Delay;
    }

    public async Task<SelectionCapture?> CaptureAsync(bool simulateCopy, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        string? diagnostic = null;

        try
        {
            var selectedText = Normalize(await _uiAutomation.ReadSelectedTextAsync(token).ConfigureAwait(false));
            if (selectedText is not null)
                return new(selectedText, SelectionSource.UiAutomation, null);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested)
        {
            throw;
        }
        catch (Exception exception)
        {
            diagnostic = $"UI Automation failed ({exception.GetType().Name})";
        }

        if (simulateCopy)
            return await CaptureSimulatedCopyAsync(diagnostic, token).ConfigureAwait(false);

        token.ThrowIfCancellationRequested();
        var clipboardText = Normalize(_clipboard.ReadUnicodeText());
        return clipboardText is null ? null : new(clipboardText, SelectionSource.Clipboard, diagnostic);
    }

    private async Task<SelectionCapture?> CaptureSimulatedCopyAsync(string? diagnostic, CancellationToken token)
    {
        await SimulatedCopyMutex.WaitAsync(token).ConfigureAwait(false);
        try
        {
            using var snapshot = _clipboard.CaptureSnapshot();
            var originalSequence = snapshot.SequenceNumber;
            uint? copiedSequence = null;
            string? copiedText = null;

            try
            {
                _copy.SendCopy();
                copiedSequence = _clipboard.GetSequenceNumber();
                if (copiedSequence == originalSequence)
                    copiedSequence = null;

                var elapsed = TimeSpan.Zero;
                while (elapsed < _copyTimeout)
                {
                    token.ThrowIfCancellationRequested();
                    var delay = _copyTimeout - elapsed < _pollInterval ? _copyTimeout - elapsed : _pollInterval;
                    await _delay(delay, token).ConfigureAwait(false);
                    elapsed += delay;

                    copiedSequence = _clipboard.GetSequenceNumber();
                    if (copiedSequence == originalSequence)
                    {
                        copiedSequence = null;
                        continue;
                    }

                    copiedText = Normalize(_clipboard.ReadUnicodeText());
                    break;
                }
            }
            finally
            {
                if (copiedSequence is uint sequence)
                    _clipboard.RestoreIfUnchanged(snapshot, sequence);
            }

            if (copiedText is not null)
                return new(copiedText, SelectionSource.SimulatedCopy, diagnostic);

            var clipboardText = Normalize(_clipboard.ReadUnicodeText());
            return clipboardText is null ? null : new(clipboardText, SelectionSource.Clipboard, diagnostic);
        }
        finally
        {
            SimulatedCopyMutex.Release();
        }
    }

    private static string? Normalize(string? text)
    {
        var trimmed = text?.Trim();
        return string.IsNullOrEmpty(trimmed) ? null : trimmed;
    }
}
