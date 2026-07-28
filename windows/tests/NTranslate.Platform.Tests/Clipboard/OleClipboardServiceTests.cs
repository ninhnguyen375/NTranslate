using NTranslate.Platform.Clipboard;

namespace NTranslate.Platform.Tests.Clipboard;

public sealed class OleClipboardServiceTests
{
    [ClipboardIntegrationFact]
    [Trait("Category", "ClipboardIntegration")]
    public void Round_trip_restores_synthetic_clipboard_in_finally()
    {
        const string syntheticOriginal = "NTranslate synthetic original";
        const string temporary = "NTranslate clipboard integration test";
        var service = new OleClipboardService();
        using var userSnapshot = service.CaptureSnapshot();
        uint cleanupSequence = 0;

        try
        {
            service.WriteUnicodeText(syntheticOriginal);
            cleanupSequence = service.GetSequenceNumber();
            using var syntheticSnapshot = service.CaptureSnapshot();
            uint writtenSequence = 0;

            try
            {
                service.WriteUnicodeText(temporary);
                writtenSequence = cleanupSequence = service.GetSequenceNumber();
                Assert.Equal(temporary, service.ReadUnicodeText());
            }
            finally
            {
                Assert.True(service.RestoreIfUnchanged(syntheticSnapshot, writtenSequence));
                cleanupSequence = service.GetSequenceNumber();
            }

            Assert.Equal(syntheticOriginal, service.ReadUnicodeText());
        }
        finally
        {
            service.RestoreIfUnchanged(userSnapshot, cleanupSequence);
        }
    }

    [ClipboardIntegrationFact]
    [Trait("Category", "ClipboardIntegration")]
    public void Restore_refuses_changed_sequence()
    {
        var service = new OleClipboardService();
        using var userSnapshot = service.CaptureSnapshot();
        const string temporary = "NTranslate changed sequence test";
        uint writtenSequence = 0;
        uint cleanupSequence = 0;

        try
        {
            service.WriteUnicodeText(temporary);
            writtenSequence = cleanupSequence = service.GetSequenceNumber();
            service.WriteUnicodeText(temporary + " external");
            cleanupSequence = service.GetSequenceNumber();
            Assert.False(service.RestoreIfUnchanged(userSnapshot, writtenSequence));
        }
        finally
        {
            service.RestoreIfUnchanged(userSnapshot, cleanupSequence);
        }
    }
}

internal sealed class ClipboardIntegrationFactAttribute : FactAttribute
{
    public ClipboardIntegrationFactAttribute()
    {
        if (Environment.GetEnvironmentVariable("NTRANSLATE_RUN_CLIPBOARD_INTEGRATION") != "1")
            Skip = "Set NTRANSLATE_RUN_CLIPBOARD_INTEGRATION=1 to run live clipboard integration tests.";
    }
}
