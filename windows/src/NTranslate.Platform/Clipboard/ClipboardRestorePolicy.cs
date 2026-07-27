namespace NTranslate.Platform.Clipboard;

internal static class ClipboardRestorePolicy
{
    public static bool ShouldRestore(uint currentSequence, uint copiedSequence) => currentSequence == copiedSequence;
}
