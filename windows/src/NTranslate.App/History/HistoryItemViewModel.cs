using NTranslate.Core.History;

namespace NTranslate.App.History;

public sealed class HistoryItemViewModel(TranslationRecord record)
{
    public TranslationRecord Record { get; } = record;
    public string SourceText => Record.SourceText;
    public string ResultText => Record.ResultText;
    public string TimestampText => Record.Timestamp.ToLocalTime().ToString("g");
}
