using System.Text;
using System.Text.Json;
using NTranslate.Core.History;
using NTranslate.Platform.Storage;

namespace NTranslate.Platform.Tests.Storage;

public sealed class TranslationHistoryStoreTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"ntranslate-history-{Guid.NewGuid():N}");

    [Fact]
    public async Task Round_trip_preserves_empty_fields_order_and_bookmark()
    {
        var store = new JsonTranslationHistoryStore(_root);
        var older = Record(Guid.NewGuid(), DateTimeOffset.Parse("2026-07-27T01:00:00Z"), source: "", result: "");
        var newer = Record(Guid.NewGuid(), DateTimeOffset.Parse("2026-07-28T01:00:00Z"));

        await store.AppendAsync(older);
        await store.AppendAsync(newer);
        await store.SetSavedAsync(older.Id, true);

        var loaded = new JsonTranslationHistoryStore(_root);
        Assert.Null(loaded.LoadError);
        Assert.Equal([newer.Id, older.Id], loaded.Records.Select(record => record.Id));
        Assert.True(loaded.Records.Single(record => record.Id == older.Id).IsSaved);
        Assert.Equal("", loaded.Records.Single(record => record.Id == older.Id).SourceText);
    }

    [Fact]
    public async Task Records_snapshot_cannot_mutate_store_memory()
    {
        var record = Record(Guid.NewGuid());
        var store = new JsonTranslationHistoryStore(_root);
        await store.AppendAsync(record);

        var exposed = Assert.IsAssignableFrom<IList<TranslationRecord>>(store.Records);
        Assert.Throws<NotSupportedException>(() => exposed[0] = Record(Guid.NewGuid()));
        Assert.Equal(record.Id, Assert.Single(store.Records).Id);
    }

    [Fact]
    public async Task Malformed_or_duplicate_history_locks_mutations_and_preserves_exact_bytes()
    {
        Directory.CreateDirectory(_root);
        var historyPath = Path.Combine(_root, "history.json");
        var malformed = Encoding.UTF8.GetBytes("{ definitely not json");
        await File.WriteAllBytesAsync(historyPath, malformed);
        var malformedStore = new JsonTranslationHistoryStore(_root);

        Assert.NotNull(malformedStore.LoadError);
        await Assert.ThrowsAsync<InvalidOperationException>(() => malformedStore.AppendAsync(Record(Guid.NewGuid())));
        Assert.Equal(malformed, await File.ReadAllBytesAsync(historyPath));

        var duplicate = Record(Guid.NewGuid());
        var duplicateBytes = JsonSerializer.SerializeToUtf8Bytes(new[] { duplicate, duplicate });
        await File.WriteAllBytesAsync(historyPath, duplicateBytes);
        var duplicateStore = new JsonTranslationHistoryStore(_root);

        Assert.NotNull(duplicateStore.LoadError);
        await Assert.ThrowsAsync<InvalidOperationException>(() => duplicateStore.SetSavedAsync(duplicate.Id, true));
        Assert.Equal(duplicateBytes, await File.ReadAllBytesAsync(historyPath));
    }

    [Fact]
    public async Task Audio_is_owned_relative_round_trips_and_missing_file_returns_null()
    {
        var record = Record(Guid.NewGuid());
        var store = new JsonTranslationHistoryStore(_root);
        await store.AppendAsync(record);

        await store.AttachAudioAsync(record.Id, TranslationAudioKind.Source, new byte[] { 1, 2, 3 });

        var updated = Assert.Single(store.Records);
        Assert.Matches($@"^Audio\\{record.Id:D}-Source-[0-9a-f]{{32}}\.audio$", updated.SourceAudioPath!);
        Assert.Equal(new byte[] { 1, 2, 3 }, await store.ReadAudioAsync(record.Id, TranslationAudioKind.Source));
        File.Delete(Path.Combine(_root, updated.SourceAudioPath!));
        Assert.Null(await store.ReadAudioAsync(record.Id, TranslationAudioKind.Source));
    }

    [Theory]
    [InlineData("C:\\escape.audio")]
    [InlineData("..\\escape.audio")]
    [InlineData("Audio\\..\\escape.audio")]
    public async Task Unsafe_audio_metadata_is_rejected(string unsafePath)
    {
        Directory.CreateDirectory(_root);
        var record = Record(Guid.NewGuid()) with { SourceAudioPath = unsafePath };
        await File.WriteAllBytesAsync(Path.Combine(_root, "history.json"), JsonSerializer.SerializeToUtf8Bytes(new[] { record }));
        var store = new JsonTranslationHistoryStore(_root);

        Assert.NotNull(store.LoadError);
    }

    [Theory]
    [InlineData("append")]
    [InlineData("bookmark")]
    [InlineData("delete")]
    public async Task Unsafe_loaded_audio_metadata_locks_all_mutations_and_preserves_exact_bytes(string mutation)
    {
        Directory.CreateDirectory(_root);
        var record = Record(Guid.NewGuid()) with { SourceAudioPath = @"Audio\..\escape.audio" };
        var historyPath = Path.Combine(_root, "history.json");
        var original = JsonSerializer.SerializeToUtf8Bytes(new[] { record });
        await File.WriteAllBytesAsync(historyPath, original);
        var store = new JsonTranslationHistoryStore(_root);

        Assert.NotNull(store.LoadError);
        await Assert.ThrowsAsync<InvalidOperationException>(() => mutation switch
        {
            "append" => store.AppendAsync(Record(Guid.NewGuid())),
            "bookmark" => store.SetSavedAsync(record.Id, true),
            "delete" => store.RemoveAsync(new HashSet<Guid> { record.Id }),
            _ => throw new ArgumentOutOfRangeException(nameof(mutation)),
        });
        Assert.Equal(original, await File.ReadAllBytesAsync(historyPath));
    }

    [Fact]
    public async Task Loaded_reparse_audio_metadata_locks_mutations_and_preserves_exact_bytes_when_supported()
    {
        var outside = Path.Combine(Path.GetTempPath(), $"ntranslate-outside-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(_root, "Audio"));
        Directory.CreateDirectory(outside);
        var link = Path.Combine(_root, "Audio", "link");
        try
        {
            try { Directory.CreateSymbolicLink(link, outside); }
            catch (Exception error) when (error is UnauthorizedAccessException or IOException or PlatformNotSupportedException) { return; }
            var record = Record(Guid.NewGuid()) with { ResultAudioPath = @"Audio\link\escape.audio" };
            var historyPath = Path.Combine(_root, "history.json");
            var original = JsonSerializer.SerializeToUtf8Bytes(new[] { record });
            await File.WriteAllBytesAsync(historyPath, original);
            var store = new JsonTranslationHistoryStore(_root);

            Assert.NotNull(store.LoadError);
            await Assert.ThrowsAsync<InvalidOperationException>(() => store.AppendAsync(Record(Guid.NewGuid())));
            Assert.Equal(original, await File.ReadAllBytesAsync(historyPath));
        }
        finally { Directory.Delete(outside, true); }
    }

    [Fact]
    public async Task Reparse_point_audio_escape_is_rejected_when_supported()
    {
        var outside = Path.Combine(Path.GetTempPath(), $"ntranslate-outside-{Guid.NewGuid():N}");
        Directory.CreateDirectory(Path.Combine(_root, "Audio"));
        Directory.CreateDirectory(outside);
        var link = Path.Combine(_root, "Audio", "link");
        try
        {
            try { Directory.CreateSymbolicLink(link, outside); }
            catch (Exception error) when (error is UnauthorizedAccessException or IOException or PlatformNotSupportedException) { return; }
            var record = Record(Guid.NewGuid()) with { SourceAudioPath = @"Audio\link\escape.audio" };
            await File.WriteAllBytesAsync(Path.Combine(_root, "history.json"), JsonSerializer.SerializeToUtf8Bytes(new[] { record }));
            var store = new JsonTranslationHistoryStore(_root);

            Assert.NotNull(store.LoadError);
        }
        finally { Directory.Delete(outside, true); }
    }

    [Fact]
    public async Task Failed_metadata_write_rolls_back_audio_and_memory()
    {
        var writer = new FailingWriter();
        var store = new JsonTranslationHistoryStore(_root, writer);
        var record = Record(Guid.NewGuid());
        await store.AppendAsync(record);
        writer.FailHistory = true;

        await Assert.ThrowsAsync<IOException>(() => store.AttachAudioAsync(record.Id, TranslationAudioKind.Result, new byte[] { 9 }));

        Assert.Null(Assert.Single(store.Records).ResultAudioPath);
        Assert.Empty(Directory.GetFiles(Path.Combine(_root, "Audio")));
    }

    [Fact]
    public async Task Unknown_record_operations_fail_without_writes()
    {
        var store = new JsonTranslationHistoryStore(_root);
        var unknown = Guid.NewGuid();

        await Assert.ThrowsAsync<KeyNotFoundException>(() => store.SetSavedAsync(unknown, true));
        await Assert.ThrowsAsync<KeyNotFoundException>(() => store.AttachAudioAsync(unknown, TranslationAudioKind.Source, new byte[] { 1 }));
        await Assert.ThrowsAsync<KeyNotFoundException>(() => store.ReadAudioAsync(unknown, TranslationAudioKind.Source));
        Assert.False(File.Exists(Path.Combine(_root, "history.json")));
    }

    [Fact]
    public async Task Cancellation_before_append_writes_nothing()
    {
        var store = new JsonTranslationHistoryStore(_root);
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => store.AppendAsync(Record(Guid.NewGuid()), cancellation.Token));

        Assert.Empty(store.Records);
        Assert.False(File.Exists(Path.Combine(_root, "history.json")));
    }

    [Fact]
    public async Task Replacing_audio_persists_new_metadata_before_deleting_old_file()
    {
        var writer = new FailingWriter();
        var store = new JsonTranslationHistoryStore(_root, writer);
        var record = Record(Guid.NewGuid());
        await store.AppendAsync(record);
        await store.AttachAudioAsync(record.Id, TranslationAudioKind.Source, new byte[] { 1 });
        var oldPath = Assert.Single(store.Records).SourceAudioPath!;
        writer.FailHistory = true;

        await Assert.ThrowsAsync<IOException>(() => store.AttachAudioAsync(record.Id, TranslationAudioKind.Source, new byte[] { 2 }));

        Assert.Equal(oldPath, Assert.Single(store.Records).SourceAudioPath);
        Assert.True(File.Exists(Path.Combine(_root, oldPath)));
        Assert.Single(Directory.GetFiles(Path.Combine(_root, "Audio")));
    }

    [Fact]
    public async Task Multi_delete_persists_before_deleting_owned_audio()
    {
        var writer = new FailingWriter();
        var store = new JsonTranslationHistoryStore(_root, writer);
        var first = Record(Guid.NewGuid());
        var second = Record(Guid.NewGuid());
        await store.AppendAsync(first);
        await store.AppendAsync(second);
        await store.AttachAudioAsync(first.Id, TranslationAudioKind.Source, new byte[] { 1 });
        await store.AttachAudioAsync(second.Id, TranslationAudioKind.Result, new byte[] { 2 });
        var paths = store.Records.SelectMany(record => new[] { record.SourceAudioPath, record.ResultAudioPath }).Where(path => path is not null).Cast<string>().ToArray();
        writer.FailHistory = true;

        await Assert.ThrowsAsync<IOException>(() => store.RemoveAsync(new HashSet<Guid> { first.Id, second.Id }));
        Assert.Equal(2, store.Records.Count);
        Assert.All(paths, path => Assert.True(File.Exists(Path.Combine(_root, path))));

        writer.FailHistory = false;
        await store.RemoveAsync(new HashSet<Guid> { first.Id, second.Id });
        Assert.Empty(store.Records);
        Assert.All(paths, path => Assert.False(File.Exists(Path.Combine(_root, path))));
    }

    private static TranslationRecord Record(Guid id, DateTimeOffset? timestamp = null, string source = "source", string result = "result") =>
        new(id, timestamp ?? DateTimeOffset.UtcNow, source, result, "en", "vi", null, null, false);

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
    }

    private sealed class FailingWriter : IAtomicFileWriter
    {
        private readonly AtomicFileWriter _inner = new();
        public bool FailHistory { get; set; }

        public Task WriteAsync(string path, ReadOnlyMemory<byte> data, CancellationToken token = default)
        {
            if (FailHistory && Path.GetFileName(path) == "history.json") throw new IOException("Injected history failure");
            return _inner.WriteAsync(path, data, token);
        }
    }
}
