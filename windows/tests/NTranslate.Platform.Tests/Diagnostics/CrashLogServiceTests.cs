using System.Text.Json;
using NTranslate.Platform.Diagnostics;
using NTranslate.Platform.Storage;

namespace NTranslate.Platform.Tests.Diagnostics;

public sealed class CrashLogServiceTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"ntranslate-crash-{Guid.NewGuid():N}");

    [Fact]
    public async Task Writes_parseable_redacted_crash_json_without_content_fields()
    {
        var service = new CrashLogService(_root, new AtomicFileWriter());
        var error = new InvalidOperationException("Bearer abc.def key=secret password: hunter2 token xyz clipboardText=private translation=private {\"apiKey\":\"quoted-secret\",\"resultText\":\"quoted-result\"}");

        await service.RecordAsync(error, CancellationToken.None);

        var path = Assert.Single(Directory.GetFiles(Path.Combine(_root, "Logs"), "crash-*.json"));
        var json = await File.ReadAllTextAsync(path);
        using var document = JsonDocument.Parse(json);
        var root = document.RootElement;
        Assert.Equal("System.InvalidOperationException", root.GetProperty("exceptionType").GetString());
        Assert.Contains("[REDACTED]", root.GetProperty("message").GetString());
        Assert.DoesNotContain("abc.def", json, StringComparison.Ordinal);
        Assert.DoesNotContain("secret", json, StringComparison.Ordinal);
        Assert.DoesNotContain("hunter2", json, StringComparison.Ordinal);
        Assert.DoesNotContain("quoted-secret", json, StringComparison.Ordinal);
        Assert.DoesNotContain("quoted-result", json, StringComparison.Ordinal);
        Assert.DoesNotContain("clipboard", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("translation", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("sourceText", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("resultText", json, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task Ignores_malformed_json_and_selects_newest_unacknowledged()
    {
        var logs = Path.Combine(_root, "Logs");
        Directory.CreateDirectory(logs);
        await File.WriteAllTextAsync(Path.Combine(logs, "crash-bad.json"), "{");
        await WriteCrashAsync(logs, "crash-old.json", "2026-07-28T01:00:00Z");
        await WriteCrashAsync(logs, "crash-new.json", "2026-07-28T02:00:00Z");
        var service = new CrashLogService(_root, new AtomicFileWriter());

        var newest = await service.GetNewestUnacknowledgedAsync(CancellationToken.None);
        await service.AcknowledgeAsync(newest!.FileName, CancellationToken.None);
        var next = await service.GetNewestUnacknowledgedAsync(CancellationToken.None);

        Assert.Equal("crash-new.json", newest.FileName);
        Assert.Null(next);
        using var state = JsonDocument.Parse(await File.ReadAllTextAsync(Path.Combine(logs, "recovery-state.json")));
        Assert.Equal("crash-new.json", state.RootElement.GetProperty("acknowledgedFileName").GetString());
        Assert.Empty(Directory.GetFiles(logs, "*.tmp"));
    }

    [Fact]
    public async Task Swallows_logging_failures()
    {
        var service = new CrashLogService(_root, new ThrowingWriter());
        await service.RecordAsync(new Exception("failure"), CancellationToken.None);
    }

    private static Task WriteCrashAsync(string logs, string file, string timestamp) =>
        File.WriteAllTextAsync(Path.Combine(logs, file), $$"""{"timestamp":"{{timestamp}}","exceptionType":"System.Exception","message":"failure","stackTrace":null}""");

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
    }

    private sealed class ThrowingWriter : IAtomicFileWriter
    {
        public Task WriteAsync(string path, ReadOnlyMemory<byte> data, CancellationToken token = default) =>
            Task.FromException(new IOException("injected"));
    }
}
