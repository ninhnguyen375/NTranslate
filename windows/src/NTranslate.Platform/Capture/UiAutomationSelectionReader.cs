using System.Windows.Automation;

namespace NTranslate.Platform.Capture;

public sealed class UiAutomationSelectionReader : IUiAutomationSelectionReader
{
    public Task<string?> ReadSelectedTextAsync(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        return Task.Run(() => ReadSelectedText(token), token);
    }

    internal static string? JoinSelectionRanges(IEnumerable<string> ranges)
    {
        var text = string.Concat(ranges);
        return text.Length == 0 ? null : text;
    }

    private static string? ReadSelectedText(CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var focused = AutomationElement.FocusedElement;
        if (focused is null || !focused.TryGetCurrentPattern(TextPattern.Pattern, out var pattern))
            return null;

        token.ThrowIfCancellationRequested();
        var ranges = ((TextPattern)pattern).GetSelection();
        var texts = new string[ranges.Length];
        for (var index = 0; index < ranges.Length; index++)
        {
            token.ThrowIfCancellationRequested();
            texts[index] = ranges[index].GetText(-1);
        }

        return JoinSelectionRanges(texts);
    }
}
