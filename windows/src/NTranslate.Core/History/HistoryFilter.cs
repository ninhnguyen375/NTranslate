namespace NTranslate.Core.History;

public sealed record TranslationRecord(
    Guid Id,
    DateTimeOffset Timestamp,
    string SourceText,
    string ResultText,
    string SourceLanguage,
    string TargetLanguage,
    string? SourceAudioPath,
    string? ResultAudioPath,
    bool IsSaved);

public enum HistoryTimeRange
{
    All,
    Today,
    Last24Hours,
    Week,
    Month
}

public sealed record HistoryFilterOptions(string Query, bool SavedOnly, HistoryTimeRange TimeRange);

public static class HistoryFilter
{
    public static IReadOnlyList<TranslationRecord> Apply(
        IEnumerable<TranslationRecord> records,
        HistoryFilterOptions options,
        DateTimeOffset now,
        TimeZoneInfo timeZone)
    {
        var minimumTimestamp = options.TimeRange switch
        {
            HistoryTimeRange.All => DateTimeOffset.MinValue,
            HistoryTimeRange.Today => StartOfLocalDay(now, timeZone),
            HistoryTimeRange.Last24Hours => now.AddHours(-24),
            HistoryTimeRange.Week => now.AddDays(-7),
            HistoryTimeRange.Month => now.AddDays(-30),
            _ => throw new ArgumentOutOfRangeException(nameof(options), options.TimeRange, null)
        };

        return records
            .Where(record => !options.SavedOnly || record.IsSaved)
            .Where(record => record.Timestamp >= minimumTimestamp)
            .Where(record => string.IsNullOrEmpty(options.Query)
                || record.SourceText.Contains(options.Query, StringComparison.OrdinalIgnoreCase)
                || record.ResultText.Contains(options.Query, StringComparison.OrdinalIgnoreCase))
            .OrderByDescending(record => record.Timestamp)
            .ToArray();
    }

    private static DateTimeOffset StartOfLocalDay(DateTimeOffset now, TimeZoneInfo timeZone)
    {
        var localDate = TimeZoneInfo.ConvertTime(now, timeZone).Date;
        var utc = TimeZoneInfo.ConvertTimeToUtc(localDate, timeZone);
        return new DateTimeOffset(utc);
    }
}
