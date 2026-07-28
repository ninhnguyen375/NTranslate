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
        uint? ownedSequence = null;

        try
        {
            service.WriteUnicodeText(syntheticOriginal);
            ownedSequence = service.GetSequenceNumber();
            using var syntheticSnapshot = service.CaptureSnapshot();
            uint writtenSequence = 0;

            try
            {
                service.WriteUnicodeText(temporary);
                writtenSequence = service.GetSequenceNumber();
                Assert.Equal(temporary, service.ReadUnicodeText());
            }
            finally
            {
                var restored = service.RestoreIfUnchanged(syntheticSnapshot, writtenSequence);
                if (restored)
                    ownedSequence = service.GetSequenceNumber();
                Assert.True(restored);
            }

            Assert.Equal(syntheticOriginal, service.ReadUnicodeText());
        }
        finally
        {
            if (ownedSequence is { } sequence)
                service.RestoreIfUnchanged(userSnapshot, sequence);
        }
    }

    [ClipboardIntegrationFact]
    [Trait("Category", "ClipboardIntegration")]
    public void Restore_refuses_changed_sequence()
    {
        var service = new OleClipboardService();
        using var userSnapshot = service.CaptureSnapshot();
        const string temporary = "NTranslate changed sequence test";
        uint? ownedSequence = null;

        try
        {
            service.WriteUnicodeText(temporary);
            var writtenSequence = service.GetSequenceNumber();
            ownedSequence = writtenSequence;
            service.WriteUnicodeText(temporary + " external");
            ownedSequence = service.GetSequenceNumber();
            Assert.False(service.RestoreIfUnchanged(userSnapshot, writtenSequence));
        }
        finally
        {
            if (ownedSequence is { } sequence)
                service.RestoreIfUnchanged(userSnapshot, sequence);
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
