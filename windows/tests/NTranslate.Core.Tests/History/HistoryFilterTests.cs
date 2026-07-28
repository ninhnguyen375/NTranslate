using NTranslate.Core.History;

namespace NTranslate.Core.Tests.History;

public sealed class HistoryFilterTests
{
    private static readonly DateTimeOffset Now = new(2026, 7, 28, 15, 0, 0, TimeSpan.Zero);
    private static readonly TimeZoneInfo PlusSeven = TimeZoneInfo.CreateCustomTimeZone("Test UTC+7", TimeSpan.FromHours(7), "Test UTC+7", "Test UTC+7");

    [Fact]
    public void Apply_SearchesSourceAndResultCaseInsensitively()
    {
        var sourceMatch = Record("Hello WORLD", "unrelated", Now.AddMinutes(-1));
        var resultMatch = Record("unrelated", "HELLO there", Now.AddMinutes(-2));
        var miss = Record("goodbye", "farewell", Now.AddMinutes(-3));

        var result = HistoryFilter.Apply([sourceMatch, resultMatch, miss], new("hello", false, HistoryTimeRange.All), Now, TimeZoneInfo.Utc);

        Assert.Equal([sourceMatch, resultMatch], result);
    }

    [Fact]
    public void Apply_ReturnsOnlySavedRecordsWhenRequested()
    {
        var saved = Record("saved", "result", Now, isSaved: true);
        var unsaved = Record("unsaved", "result", Now.AddMinutes(-1));

        var result = HistoryFilter.Apply([saved, unsaved], new("", true, HistoryTimeRange.All), Now, TimeZoneInfo.Utc);

        Assert.Equal([saved], result);
    }

    [Fact]
    public void Apply_TodayUsesMidnightInProvidedTimeZone()
    {
        var atLocalMidnight = Record("included", "result", new DateTimeOffset(2026, 7, 27, 17, 0, 0, TimeSpan.Zero));
        var beforeLocalMidnight = Record("excluded", "result", atLocalMidnight.Timestamp.AddTicks(-1));

        var result = HistoryFilter.Apply([beforeLocalMidnight, atLocalMidnight], new("", false, HistoryTimeRange.Today), Now, PlusSeven);

        Assert.Equal([atLocalMidnight], result);
    }

    [Theory]
    [InlineData(HistoryTimeRange.Last24Hours, 24)]
    [InlineData(HistoryTimeRange.Week, 24 * 7)]
    [InlineData(HistoryTimeRange.Month, 24 * 30)]
    public void Apply_RollingRangesIncludeExactBoundaryAndExcludeOlder(HistoryTimeRange range, int hours)
    {
        var boundary = Record("included", "result", Now.AddHours(-hours));
        var older = Record("excluded", "result", boundary.Timestamp.AddTicks(-1));

        var result = HistoryFilter.Apply([older, boundary], new("", false, range), Now, TimeZoneInfo.Utc);

        Assert.Equal([boundary], result);
    }

    [Fact]
    public void Apply_ComposesQuerySavedAndTimeRangeWithAnd()
    {
        var match = Record("Needle", "result", Now.AddHours(-1), isSaved: true);
        var wrongQuery = Record("other", "result", Now.AddHours(-1), isSaved: true);
        var unsaved = Record("Needle", "result", Now.AddHours(-1));
        var tooOld = Record("Needle", "result", Now.AddHours(-25), isSaved: true);

        var result = HistoryFilter.Apply([wrongQuery, tooOld, match, unsaved], new("needle", true, HistoryTimeRange.Last24Hours), Now, TimeZoneInfo.Utc);

        Assert.Equal([match], result);
    }

    [Fact]
    public void Apply_ReturnsNewestFirstWithoutMutatingInput()
    {
        var oldest = Record("oldest", "result", Now.AddHours(-2));
        var newest = Record("newest", "result", Now);
        var middle = Record("middle", "result", Now.AddHours(-1));
        var records = new List<TranslationRecord> { oldest, newest, middle };
        var originalOrder = records.ToArray();

        var result = HistoryFilter.Apply(records, new("", false, HistoryTimeRange.All), Now, TimeZoneInfo.Utc);

        Assert.Equal([newest, middle, oldest], result);
        Assert.Equal(originalOrder, records);
    }

    private static TranslationRecord Record(string source, string result, DateTimeOffset timestamp, bool isSaved = false) =>
        new(Guid.NewGuid(), timestamp, source, result, "en", "vi", null, null, isSaved);
}
