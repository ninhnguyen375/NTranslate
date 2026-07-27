using NTranslate.Platform.Clipboard;

namespace NTranslate.Platform.Tests.Clipboard;

public sealed class ClipboardRestorePolicyTests
{
    [Theory]
    [InlineData(12u, 12u, true)]
    [InlineData(12u, 13u, false)]
    public void Restore_only_when_clipboard_still_has_copied_sequence(uint currentSequence, uint copiedSequence, bool expected)
    {
        Assert.Equal(expected, ClipboardRestorePolicy.ShouldRestore(currentSequence, copiedSequence));
    }
}
