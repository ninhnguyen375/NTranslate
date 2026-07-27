namespace NTranslate.Platform.Capture;

public enum SelectionSource
{
    UiAutomation,
    SimulatedCopy,
    Clipboard
}

public sealed record SelectionCapture(string Text, SelectionSource Source, string? Diagnostic);

public interface IUiAutomationSelectionReader
{
    Task<string?> ReadSelectedTextAsync(CancellationToken token);
}

public interface ISelectionCaptureService
{
    Task<SelectionCapture?> CaptureAsync(bool simulateCopy, CancellationToken token);
}
