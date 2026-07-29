namespace NTranslate.Platform.Capture;

public enum SelectionSource
{
    UiAutomation,
    SimulatedCopy,
    Clipboard
}

public sealed record SelectionCapture
{
    public SelectionCapture(string? text, byte[]? imagePng, SelectionSource source, string? diagnostic)
    {
        if (text is not null && imagePng is not null)
            throw new ArgumentException("Text and image payloads are mutually exclusive.");

        Text = text;
        ImagePng = imagePng;
        Source = source;
        Diagnostic = diagnostic;
    }

    public SelectionCapture(string text, SelectionSource source, string? diagnostic)
        : this(text, null, source, diagnostic) { }

    public string? Text { get; }
    public byte[]? ImagePng { get; }
    public SelectionSource Source { get; }
    public string? Diagnostic { get; }
}

public interface IUiAutomationSelectionReader
{
    Task<string?> ReadSelectedTextAsync(CancellationToken token);
}

public interface ISelectionCaptureService
{
    Task<SelectionCapture?> CaptureAsync(bool simulateCopy, CancellationToken token);
}
