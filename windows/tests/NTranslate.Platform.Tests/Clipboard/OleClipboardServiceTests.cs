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
        uint writtenSequence = 0;

        try
        {
            service.WriteUnicodeText(temporary);
            writtenSequence = service.GetSequenceNumber();
            Assert.Equal(temporary, service.ReadUnicodeText());
        }
        finally
        {
            Assert.True(service.RestoreIfUnchanged(original, writtenSequence));
        }

        Assert.Equal(originalText, service.ReadUnicodeText());
    }

    [Fact]
    [Trait("Category", "ClipboardIntegration")]
    public void Restore_refuses_changed_sequence()
    {
        var service = new OleClipboardService();
        using var original = service.CaptureSnapshot();
        const string temporary = "NTranslate changed sequence test";
        uint writtenSequence = 0;

        try
        {
            service.WriteUnicodeText(temporary);
            writtenSequence = service.GetSequenceNumber();
            service.WriteUnicodeText(temporary + " external");
            Assert.False(service.RestoreIfUnchanged(original, writtenSequence));
        }
        finally
        {
            service.RestoreIfUnchanged(original, service.GetSequenceNumber());
        }
    }

}
