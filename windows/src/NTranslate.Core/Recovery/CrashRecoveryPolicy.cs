namespace NTranslate.Core.Recovery;

public sealed record CrashLogSummary(
    string FileName,
    DateTimeOffset Timestamp,
    string ExceptionType,
    string Message,
    string? StackTrace);

public static class CrashRecoveryPolicy
{
    public static CrashLogSummary? SelectUnacknowledged(
        IEnumerable<CrashLogSummary> logs,
        string? acknowledgedFileName)
    {
        ArgumentNullException.ThrowIfNull(logs);
        var ordered = logs.OrderByDescending(log => log.Timestamp).ThenByDescending(log => log.FileName, StringComparer.Ordinal).ToArray();
        if (acknowledgedFileName is null) return ordered.FirstOrDefault();
        var acknowledged = ordered.FirstOrDefault(log => string.Equals(log.FileName, acknowledgedFileName, StringComparison.Ordinal));
        return acknowledged is null
            ? ordered.FirstOrDefault()
            : ordered.FirstOrDefault(log => log.Timestamp > acknowledged.Timestamp);
    }
}
