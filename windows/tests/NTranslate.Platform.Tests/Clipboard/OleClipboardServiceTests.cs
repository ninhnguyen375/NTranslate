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
            ownedSequence = service.WriteUnicodeTextAndGetSequence(syntheticOriginal);
            using var syntheticSnapshot = service.CaptureSnapshot();
            uint? writtenSequence = null;

            try
            {
                writtenSequence = service.WriteUnicodeTextAndGetSequence(temporary);
                Assert.Equal(temporary, service.ReadUnicodeText());
            }
            finally
            {
                ownedSequence = service.RestoreIfUnchangedAndGetSequence(syntheticSnapshot, writtenSequence);
                Assert.NotNull(ownedSequence);
            }

            Assert.Equal(syntheticOriginal, service.ReadUnicodeText());
        }
        finally
        {
            service.RestoreIfUnchangedAndGetSequence(userSnapshot, ownedSequence);
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
            var writtenSequence = service.WriteUnicodeTextAndGetSequence(temporary);
            ownedSequence = writtenSequence;
            ownedSequence = service.WriteUnicodeTextAndGetSequence(temporary + " external");
            Assert.Null(service.RestoreIfUnchangedAndGetSequence(userSnapshot, writtenSequence));
        }
        finally
        {
            service.RestoreIfUnchangedAndGetSequence(userSnapshot, ownedSequence);
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
