using NTranslate.Platform.Clipboard;

namespace NTranslate.Platform.Tests.Clipboard;

public sealed class OleClipboardServiceTests
{
    [Fact]
    [Trait("Category", "ClipboardIntegration")]
    public void Round_trip_restores_original_clipboard_in_finally()
    {
        var service = new OleClipboardService();
        using var original = service.CaptureSnapshot();
        var originalText = service.ReadUnicodeText();
        const string temporary = "NTranslate clipboard integration test";

        try
        {
            service.WriteUnicodeText(temporary);
            Assert.Equal(temporary, service.ReadUnicodeText());
        }
        finally
        {
            Assert.True(service.RestoreIfUnchanged(original, service.GetSequenceNumber()));
        }

        Assert.Equal(originalText, service.ReadUnicodeText());
    }
}
