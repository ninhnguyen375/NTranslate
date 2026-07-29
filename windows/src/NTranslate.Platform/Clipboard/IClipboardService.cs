namespace NTranslate.Platform.Clipboard;

public interface IClipboardSnapshot : IDisposable
{
    uint SequenceNumber { get; }
}

public interface IClipboardService
{
    uint GetSequenceNumber();
    IClipboardSnapshot CaptureSnapshot();
    string? ReadUnicodeText();
    byte[]? ReadImagePng() => null;
    void WriteUnicodeText(string text);
    bool RestoreIfUnchanged(IClipboardSnapshot snapshot, uint copiedSequenceNumber);
}
