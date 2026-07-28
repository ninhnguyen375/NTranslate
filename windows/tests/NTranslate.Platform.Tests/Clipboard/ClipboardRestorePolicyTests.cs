using NTranslate.Platform.Clipboard;

namespace NTranslate.Platform.Tests.Clipboard;

public sealed class ClipboardRestorePolicyTests
{
    [Theory]
    [InlineData(12u, 12u, true)]
    [InlineData(12u, 13u, false)]
    [InlineData(12u, null, false)]
    public void Restore_only_when_clipboard_still_has_owned_sequence(uint currentSequence, uint? ownedSequence, bool expected)
    {
        Assert.Equal(expected, ClipboardRestorePolicy.ShouldRestore(currentSequence, ownedSequence));
    }
}
