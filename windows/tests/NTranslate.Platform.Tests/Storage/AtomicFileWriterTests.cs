using NTranslate.Platform.Storage;

namespace NTranslate.Platform.Tests.Storage;

public sealed class AtomicFileWriterTests : IDisposable
{
    private readonly string _root = Path.Combine(Path.GetTempPath(), $"ntranslate-atomic-{Guid.NewGuid():N}");

    [Fact]
    public async Task Writes_new_and_replaces_existing_without_temp_residue()
    {
        Directory.CreateDirectory(_root);
        var path = Path.Combine(_root, "history.json");
        var writer = new AtomicFileWriter();

        await writer.WriteAsync(path, new byte[] { 1 });
        await writer.WriteAsync(path, new byte[] { 2, 3 });

        Assert.Equal(new byte[] { 2, 3 }, await File.ReadAllBytesAsync(path));
        Assert.Equal(["history.json"], Directory.GetFiles(_root).Select(Path.GetFileName));
    }

    [Fact]
    public async Task Failure_preserves_existing_bytes_and_cleans_hidden_temp()
    {
        Directory.CreateDirectory(_root);
        var path = Path.Combine(_root, "history.json");
        await File.WriteAllBytesAsync(path, new byte[] { 7 });
        var writer = new AtomicFileWriter((_, _) => throw new IOException("Injected replace failure"));

        await Assert.ThrowsAsync<IOException>(() => writer.WriteAsync(path, new byte[] { 8 }));

        Assert.Equal(new byte[] { 7 }, await File.ReadAllBytesAsync(path));
        Assert.Equal(["history.json"], Directory.GetFiles(_root).Select(Path.GetFileName));
    }

    public void Dispose()
    {
        if (Directory.Exists(_root)) Directory.Delete(_root, true);
    }
}
