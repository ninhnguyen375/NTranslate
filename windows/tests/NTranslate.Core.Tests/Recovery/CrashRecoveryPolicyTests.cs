using NTranslate.Core.Recovery;

namespace NTranslate.Core.Tests.Recovery;

public sealed class CrashRecoveryPolicyTests
{
    [Fact]
    public void Selects_newest_unacknowledged_log()
    {
        var old = Summary("old.json", "2026-07-28T01:00:00Z");
        var newest = Summary("new.json", "2026-07-28T02:00:00Z");

        Assert.Equal(newest, CrashRecoveryPolicy.SelectUnacknowledged([old, newest], null));
    }

    [Fact]
    public void Acknowledgement_suppresses_that_file_and_all_older_files()
    {
        var old = Summary("old.json", "2026-07-28T01:00:00Z");
        var acknowledged = Summary("ack.json", "2026-07-28T02:00:00Z");

        Assert.Null(CrashRecoveryPolicy.SelectUnacknowledged([old, acknowledged], acknowledged.FileName));
    }

    private static CrashLogSummary Summary(string file, string timestamp) =>
        new(file, DateTimeOffset.Parse(timestamp), "System.Exception", "failure", null);
}
