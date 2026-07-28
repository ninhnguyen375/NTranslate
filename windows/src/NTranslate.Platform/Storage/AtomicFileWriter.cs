namespace NTranslate.Platform.Storage;

public interface IAtomicFileWriter
{
    Task WriteAsync(string path, ReadOnlyMemory<byte> data, CancellationToken token = default);
}

public sealed class AtomicFileWriter : IAtomicFileWriter
{
    private readonly Action<string, string>? _replace;

    public AtomicFileWriter(Action<string, string>? replace = null) => _replace = replace;

    public async Task WriteAsync(string path, ReadOnlyMemory<byte> data, CancellationToken token = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var fullPath = Path.GetFullPath(path);
        var directory = Path.GetDirectoryName(fullPath)!;
        Directory.CreateDirectory(directory);
        var temporaryPath = Path.Combine(directory, $".{Path.GetFileName(path)}.{Guid.NewGuid():N}.tmp");

        try
        {
            await using (var stream = new FileStream(
                temporaryPath,
                FileMode.CreateNew,
                FileAccess.Write,
                FileShare.None,
                4096,
                FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                File.SetAttributes(temporaryPath, FileAttributes.Hidden);
                await stream.WriteAsync(data, token).ConfigureAwait(false);
                await stream.FlushAsync(token).ConfigureAwait(false);
                stream.Flush(flushToDisk: true);
            }

            token.ThrowIfCancellationRequested();
            if (File.Exists(fullPath))
            {
                if (_replace is null)
                    File.Replace(temporaryPath, fullPath, null);
                else
                    _replace(temporaryPath, fullPath);
            }
            else
            {
                File.Move(temporaryPath, fullPath);
            }
        }
        finally
        {
            try { File.Delete(temporaryPath); }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
    }
}
