using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using NTranslate.Core.Recovery;
using NTranslate.Platform.Storage;

namespace NTranslate.Platform.Diagnostics;

public interface ICrashLogService
{
    string LogsDirectory { get; }
    Task RecordAsync(Exception exception, CancellationToken token = default);
    Task<CrashLogSummary?> GetNewestUnacknowledgedAsync(CancellationToken token = default);
    Task AcknowledgeAsync(string fileName, CancellationToken token = default);
}

public sealed partial class CrashLogService : ICrashLogService
{
    public const int MessageByteLimit = 8 * 1024;
    public const int StackTraceByteLimit = 64 * 1024;
    public const int FileByteLimit = 80 * 1024;
    public const int RetainedFileLimit = 10;

    private readonly IAtomicFileWriter _writer;
    private readonly string _statePath;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public CrashLogService(string rootDirectory, IAtomicFileWriter writer)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(rootDirectory);
        _writer = writer ?? throw new ArgumentNullException(nameof(writer));
        LogsDirectory = Path.Combine(Path.GetFullPath(rootDirectory), "Logs");
        _statePath = Path.Combine(LogsDirectory, "recovery-state.json");
    }

    public string LogsDirectory { get; }

    public async Task RecordAsync(Exception exception, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(exception);
        try
        {
            token.ThrowIfCancellationRequested();
            var timestamp = DateTimeOffset.UtcNow;
            var message = TruncateUtf8(Redact(exception.Message), MessageByteLimit) ?? string.Empty;
            var stackTrace = TruncateUtf8(Redact(exception.StackTrace), StackTraceByteLimit);
            var payload = new CrashPayload(timestamp, exception.GetType().FullName ?? exception.GetType().Name, message, stackTrace);
            var data = JsonSerializer.SerializeToUtf8Bytes(payload, JsonOptions);
            while (data.Length > FileByteLimit && stackTrace?.Length > 0)
            {
                stackTrace = TruncateUtf8(stackTrace, Math.Max(0, Encoding.UTF8.GetByteCount(stackTrace) - (data.Length - FileByteLimit) - 64));
                data = JsonSerializer.SerializeToUtf8Bytes(payload with { StackTrace = stackTrace }, JsonOptions);
            }
            var path = Path.Combine(LogsDirectory, $"crash-{timestamp:yyyyMMddTHHmmssfffffffZ}-{Guid.NewGuid():N}.json");
            await _writer.WriteAsync(path, data, token).ConfigureAwait(false);
            RetainNewest();
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { }
        catch (Exception) { }
    }

    public async Task<CrashLogSummary?> GetNewestUnacknowledgedAsync(CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        if (!Directory.Exists(LogsDirectory)) return null;
        var logs = new List<CrashLogSummary>();
        foreach (var path in Directory.EnumerateFiles(LogsDirectory, "crash-*.json"))
        {
            token.ThrowIfCancellationRequested();
            try
            {
                await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.Asynchronous);
                var payload = await JsonSerializer.DeserializeAsync<CrashPayload>(stream, JsonOptions, token).ConfigureAwait(false);
                if (payload is not null && !string.IsNullOrWhiteSpace(payload.ExceptionType) && payload.Message is not null)
                    logs.Add(new(Path.GetFileName(path), payload.Timestamp, payload.ExceptionType, payload.Message, payload.StackTrace));
            }
            catch (JsonException) { }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        return CrashRecoveryPolicy.SelectUnacknowledged(logs, await ReadAcknowledgementAsync(token).ConfigureAwait(false));
    }

    public Task AcknowledgeAsync(string fileName, CancellationToken token = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(fileName);
        if (!string.Equals(Path.GetFileName(fileName), fileName, StringComparison.Ordinal))
            throw new ArgumentException("Crash file name must not contain a path.", nameof(fileName));
        var data = JsonSerializer.SerializeToUtf8Bytes(new RecoveryState(fileName), JsonOptions);
        return _writer.WriteAsync(_statePath, data, token);
    }

    private async Task<string?> ReadAcknowledgementAsync(CancellationToken token)
    {
        if (!File.Exists(_statePath)) return null;
        try
        {
            await using var stream = new FileStream(_statePath, FileMode.Open, FileAccess.Read, FileShare.Read, 4096, FileOptions.Asynchronous);
            return (await JsonSerializer.DeserializeAsync<RecoveryState>(stream, JsonOptions, token).ConfigureAwait(false))?.AcknowledgedFileName;
        }
        catch (JsonException) { return null; }
        catch (IOException) { return null; }
        catch (UnauthorizedAccessException) { return null; }
    }

    private void RetainNewest()
    {
        foreach (var path in Directory.EnumerateFiles(LogsDirectory, "crash-*.json")
                     .OrderByDescending(Path.GetFileName, StringComparer.Ordinal)
                     .Skip(RetainedFileLimit))
        {
            try { File.Delete(path); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }

    private static string? TruncateUtf8(string? value, int byteLimit)
    {
        if (value is null || Encoding.UTF8.GetByteCount(value) <= byteLimit) return value;
        var bytes = Encoding.UTF8.GetBytes(value);
        var length = byteLimit;
        while (length > 0 && (bytes[length] & 0xC0) == 0x80) length--;
        return Encoding.UTF8.GetString(bytes, 0, length);
    }

    private static string? Redact(string? value)
    {
        if (value is null) return null;
        value = ContentFieldLineRegex().Replace(value, "[REDACTED]");
        value = StructuredFieldRegex().Replace(value, "$1[REDACTED]");
        return BearerRegex().Replace(value, "$1[REDACTED]");
    }

    [GeneratedRegex("(?im)\\\"?(?:clipboard(?:Text|Content)?|translation|sourceText|resultText)\\\"?\\s*[:=]\\s*(?:\\\"(?:\\\\.|[^\\\"])*\\\"|[^\\r\\n,;}]+)")]
    private static partial Regex ContentFieldLineRegex();
    [GeneratedRegex(@"(?i)(\bBearer\s+)[^\s,;]+")]
    private static partial Regex BearerRegex();
    [GeneratedRegex("(?im)(\\\"?(?:api[_-]?key|key|password|token|clipboard(?:Text|Content)?|translation|sourceText|resultText)\\\"?\\s*[:=]\\s*)(?:\\\"(?:\\\\.|[^\\\"])*\\\"|[^\\r\\n,;}]+)")]
    private static partial Regex StructuredFieldRegex();

    private sealed record CrashPayload(DateTimeOffset Timestamp, string ExceptionType, string Message, string? StackTrace);
    private sealed record RecoveryState(string AcknowledgedFileName);
}
