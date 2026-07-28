using System.Text.Json;
using NTranslate.Core.History;
using NTranslate.Core.Settings;
using NTranslate.Platform.Storage;

namespace NTranslate.Platform.Tests.Storage;

public sealed class HistoryDirectoryMigratorTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"ntranslate-migration-{Guid.NewGuid():N}");

    [Fact]
    public async Task Same_path_is_case_insensitive_and_needs_no_migration()
    {
        var source = Path.Combine(_root, "History");
        Directory.CreateDirectory(source);
        var migrator = new HistoryDirectoryMigrator();

        Assert.Null(await migrator.PrepareAsync(source, source.ToUpperInvariant()));
    }

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public async Task Nested_roots_are_rejected(bool destinationUnderSource)
    {
        var parent = Path.Combine(_root, "parent");
        var child = Path.Combine(parent, "child");
        Directory.CreateDirectory(parent);
        var migrator = new HistoryDirectoryMigrator();

        await Assert.ThrowsAsync<InvalidOperationException>(() => migrator.PrepareAsync(
            destinationUnderSource ? parent : child,
            destinationUnderSource ? child : parent));
    }

    [Fact]
    public async Task Nonempty_destination_is_rejected_without_changes()
    {
        var (source, destination, _) = await CreateValidSourceAsync();
        Directory.CreateDirectory(destination);
        var existing = Path.Combine(destination, "keep.txt");
        await File.WriteAllTextAsync(existing, "keep");

        await Assert.ThrowsAsync<InvalidOperationException>(() => new HistoryDirectoryMigrator().PrepareAsync(source, destination));

        Assert.Equal("keep", await File.ReadAllTextAsync(existing));
        Assert.True(File.Exists(Path.Combine(source, "history.json")));
    }

    [Fact]
    public async Task Prepare_copies_only_history_and_audio_beside_destination_and_preserves_source()
    {
        var (source, destination, audioPath) = await CreateValidSourceAsync();
        await File.WriteAllTextAsync(Path.Combine(source, "ignore.txt"), "ignore");
        var migrator = new HistoryDirectoryMigrator();

        var receipt = Assert.IsType<HistoryMigrationReceipt>(await migrator.PrepareAsync(source, destination));

        Assert.Equal(Path.GetDirectoryName(destination), Path.GetDirectoryName(receipt.StagingRoot));
        Assert.True(File.Exists(Path.Combine(receipt.StagingRoot, "history.json")));
        Assert.True(File.Exists(Path.Combine(receipt.StagingRoot, audioPath)));
        Assert.False(File.Exists(Path.Combine(receipt.StagingRoot, "ignore.txt")));
        Assert.True(File.Exists(Path.Combine(source, "history.json")));
        Assert.True(File.Exists(Path.Combine(source, audioPath)));
    }

    [Fact]
    public async Task Malformed_history_fails_prepare_and_cleans_owned_staging()
    {
        var source = Path.Combine(_root, "source");
        var destination = Path.Combine(_root, "destination");
        Directory.CreateDirectory(source);
        await File.WriteAllTextAsync(Path.Combine(source, "history.json"), "not json");
        var migrator = new HistoryDirectoryMigrator();

        await Assert.ThrowsAsync<InvalidDataException>(() => migrator.PrepareAsync(source, destination));

        Assert.True(File.Exists(Path.Combine(source, "history.json")));
        Assert.DoesNotContain(Directory.GetDirectories(_root), path => Path.GetFileName(path).StartsWith(".destination.ntranslate-stage-", StringComparison.Ordinal));
    }

    [Fact]
    public async Task Missing_referenced_audio_fails_prepare()
    {
        var source = Path.Combine(_root, "source");
        var destination = Path.Combine(_root, "destination");
        Directory.CreateDirectory(source);
        var record = Record(@"Audio\missing.audio");
        await File.WriteAllBytesAsync(Path.Combine(source, "history.json"), JsonSerializer.SerializeToUtf8Bytes(new[] { record }));

        await Assert.ThrowsAsync<InvalidDataException>(() => new HistoryDirectoryMigrator().PrepareAsync(source, destination));
    }

    [Fact]
    public async Task Unsafe_audio_reference_fails_prepare()
    {
        var source = Path.Combine(_root, "source");
        var destination = Path.Combine(_root, "destination");
        Directory.CreateDirectory(source);
        await File.WriteAllBytesAsync(Path.Combine(source, "history.json"), JsonSerializer.SerializeToUtf8Bytes(new[] { Record(@"Audio\..\escape.audio") }));

        await Assert.ThrowsAsync<InvalidDataException>(() => new HistoryDirectoryMigrator().PrepareAsync(source, destination));
    }

    [Fact]
    public async Task Reparse_points_under_audio_are_rejected_when_supported()
    {
        var source = Path.Combine(_root, "source");
        var destination = Path.Combine(_root, "destination");
        var outside = Path.Combine(_root, "outside");
        Directory.CreateDirectory(Path.Combine(source, "Audio"));
        Directory.CreateDirectory(outside);
        var link = Path.Combine(source, "Audio", "link");
        try { Directory.CreateSymbolicLink(link, outside); }
        catch (Exception error) when (error is UnauthorizedAccessException or IOException or PlatformNotSupportedException) { return; }
        await File.WriteAllBytesAsync(Path.Combine(source, "history.json"), JsonSerializer.SerializeToUtf8Bytes(Array.Empty<TranslationRecord>()));

        await Assert.ThrowsAsync<InvalidDataException>(() => new HistoryDirectoryMigrator().PrepareAsync(source, destination));
    }

    [Fact]
    public async Task Commit_atomically_renames_staging_to_destination_and_preserves_source()
    {
        var (source, destination, audioPath) = await CreateValidSourceAsync();
        var migrator = new HistoryDirectoryMigrator();
        var receipt = Assert.IsType<HistoryMigrationReceipt>(await migrator.PrepareAsync(source, destination));

        await migrator.CommitAsync(receipt);

        Assert.False(Directory.Exists(receipt.StagingRoot));
        Assert.True(File.Exists(Path.Combine(destination, "history.json")));
        Assert.True(File.Exists(Path.Combine(destination, audioPath)));
        Assert.True(File.Exists(Path.Combine(source, "history.json")));
    }

    [Fact]
    public async Task Existing_empty_destination_can_be_replaced_at_commit()
    {
        var (source, destination, _) = await CreateValidSourceAsync();
        Directory.CreateDirectory(destination);
        var migrator = new HistoryDirectoryMigrator();
        var receipt = Assert.IsType<HistoryMigrationReceipt>(await migrator.PrepareAsync(source, destination));

        await migrator.CommitAsync(receipt);

        Assert.True(File.Exists(Path.Combine(destination, "history.json")));
    }

    [Fact]
    public async Task Late_destination_collision_fails_without_deleting_collision_or_source()
    {
        var (source, destination, _) = await CreateValidSourceAsync();
        var migrator = new HistoryDirectoryMigrator();
        var receipt = Assert.IsType<HistoryMigrationReceipt>(await migrator.PrepareAsync(source, destination));
        Directory.CreateDirectory(destination);
        var collision = Path.Combine(destination, "foreign.txt");
        await File.WriteAllTextAsync(collision, "foreign");

        await Assert.ThrowsAsync<IOException>(() => migrator.CommitAsync(receipt));
        await migrator.RollbackAsync(receipt);

        Assert.Equal("foreign", await File.ReadAllTextAsync(collision));
        Assert.False(Directory.Exists(receipt.StagingRoot));
        Assert.True(File.Exists(Path.Combine(source, "history.json")));
    }

    [Fact]
    public async Task Rollback_removes_only_owned_paths_and_rejects_forged_receipts()
    {
        var (source, destination, _) = await CreateValidSourceAsync();
        var migrator = new HistoryDirectoryMigrator();
        var receipt = Assert.IsType<HistoryMigrationReceipt>(await migrator.PrepareAsync(source, destination));
        var foreign = Path.Combine(_root, "foreign");
        Directory.CreateDirectory(foreign);
        await File.WriteAllTextAsync(Path.Combine(foreign, "keep.txt"), "keep");

        await Assert.ThrowsAsync<InvalidOperationException>(() => migrator.RollbackAsync(receipt with { StagingRoot = foreign }));
        await Assert.ThrowsAsync<InvalidOperationException>(() => migrator.RollbackAsync(
            new HistoryMigrationReceipt(receipt.SourceRoot, receipt.DestinationRoot, receipt.StagingRoot)));
        await migrator.RollbackAsync(receipt);

        Assert.True(File.Exists(Path.Combine(foreign, "keep.txt")));
        Assert.False(Directory.Exists(receipt.StagingRoot));
        Assert.True(File.Exists(Path.Combine(source, "history.json")));
        Assert.False(Directory.Exists(destination));
    }

    [Fact]
    public async Task Cancellation_is_observed_before_prepare_io()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => new HistoryDirectoryMigrator().PrepareAsync(
            Path.Combine(_root, "missing-source"), Path.Combine(_root, "destination"), cancellation.Token));
        Assert.False(Directory.Exists(_root));
    }

    private async Task<(string Source, string Destination, string AudioPath)> CreateValidSourceAsync()
    {
        var source = Path.Combine(_root, "source");
        var destination = Path.Combine(_root, "destination");
        var audioPath = Path.Combine("Audio", "voice.audio");
        Directory.CreateDirectory(Path.Combine(source, "Audio"));
        await File.WriteAllBytesAsync(Path.Combine(source, audioPath), [1, 2, 3, 4]);
        await File.WriteAllBytesAsync(Path.Combine(source, "history.json"), JsonSerializer.SerializeToUtf8Bytes(new[] { Record(audioPath) }));
        return (source, destination, audioPath);
    }

    private static TranslationRecord Record(string audioPath) =>
        new(Guid.NewGuid(), DateTimeOffset.UtcNow, "source", "result", "en", "vi", audioPath, null, false);

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
    }
}
