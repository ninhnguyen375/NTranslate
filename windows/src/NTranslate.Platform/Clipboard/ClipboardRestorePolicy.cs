namespace NTranslate.Platform.Clipboard;

internal static class ClipboardRestorePolicy
{
    public static bool ShouldRestore(uint currentSequence, uint? ownedSequence) =>
        ownedSequence is { } sequence && currentSequence == sequence;
}
