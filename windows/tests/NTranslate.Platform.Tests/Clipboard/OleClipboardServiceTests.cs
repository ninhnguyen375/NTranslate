using NTranslate.Platform.Clipboard;

namespace NTranslate.Platform.Tests.Clipboard;

public sealed class OleClipboardServiceTests
{
    [ClipboardIntegrationFact]
    [Trait("Category", "ClipboardIntegration")]
    public void Round_trip_requires_provable_clipboard_ownership()
    {
    }

    [ClipboardIntegrationFact]
    [Trait("Category", "ClipboardIntegration")]
    public void Changed_sequence_cleanup_requires_provable_clipboard_ownership()
    {
    }
}

internal sealed class ClipboardIntegrationFactAttribute : FactAttribute
{
    public ClipboardIntegrationFactAttribute() =>
        Skip = "Live clipboard mutation disabled: current APIs cannot prove ownership without a race.";
}
