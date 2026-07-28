using System.Security.Cryptography;
using System.Text.Json;
using NTranslate.Core.History;
using NTranslate.Core.Settings;

namespace NTranslate.Platform.Storage;

public sealed class HistoryDirectoryMigrator : IHistoryDirectoryMigrator
{
    private const string OwnershipMarker = ".ntranslate-migration-owner";
    private static readonly JsonSerializerOptions JsonOptions = new();
    private readonly object _gate = new();
    private readonly HashSet<HistoryMigrationReceipt> _owned = new(ReferenceEqualityComparer.Instance);
    private readonly Dictionary<HistoryMigrationReceipt, string> _committed = new(ReferenceEqualityComparer.Instance);

    public async Task<HistoryMigrationReceipt?> PrepareAsync(
        string currentRoot,
        string requestedRoot,
        CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        var source = Normalize(currentRoot);
        var destination = Normalize(requestedRoot);
        if (PathEquals(source, destination)) return null;
        if (Contains(source, destination) || Contains(destination, source))
            throw new InvalidOperationException("History roots cannot contain each other.");
        if (!Directory.Exists(source))
            throw new DirectoryNotFoundException($"History source '{source}' does not exist.");
        RejectReparse(source);
        EnsureEmptyOrMissing(destination);

        var destinationParent = Path.GetDirectoryName(destination)
            ?? throw new InvalidOperationException("History destination needs a parent directory.");
        Directory.CreateDirectory(destinationParent);
        RejectReparseAncestors(destinationParent);
        var staging = Path.Combine(destinationParent, $".{Path.GetFileName(destination)}.ntranslate-stage-{Guid.NewGuid():N}");
        var receipt = new HistoryMigrationReceipt(source, destination, staging);

        Directory.CreateDirectory(staging);
        lock (_gate) _owned.Add(receipt);
        try
        {
            var sourceHistory = Path.Combine(source, "history.json");
            if (File.Exists(sourceHistory))
            {
                RejectReparse(sourceHistory);
                await CopyFileAsync(sourceHistory, Path.Combine(staging, "history.json"), token).ConfigureAwait(false);
            }

            var sourceAudio = Path.Combine(source, "Audio");
            if (Directory.Exists(sourceAudio))
                await CopyAudioTreeAsync(sourceAudio, Path.Combine(staging, "Audio"), token).ConfigureAwait(false);

            await File.WriteAllTextAsync(Path.Combine(staging, OwnershipMarker), Guid.NewGuid().ToString("N"), token).ConfigureAwait(false);
            await ValidateStagingAsync(staging, token).ConfigureAwait(false);
            return receipt;
        }
        catch
        {
            DeleteOwnedStaging(receipt);
            throw;
        }
    }

    public Task CommitAsync(HistoryMigrationReceipt receipt, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(receipt);
        token.ThrowIfCancellationRequested();
        EnsureOwned(receipt);
        try
        {
            EnsureEmptyOrMissing(receipt.DestinationRoot);
        }
        catch (InvalidOperationException error)
        {
            throw new IOException($"Cannot commit history migration to '{receipt.DestinationRoot}'.", error);
        }
        if (Directory.Exists(receipt.DestinationRoot))
            Directory.Delete(receipt.DestinationRoot, false);
        try
        {
            Directory.Move(receipt.StagingRoot, receipt.DestinationRoot);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            throw new IOException($"Cannot commit history migration to '{receipt.DestinationRoot}'.", error);
        }
        var identity = ComputeTreeIdentity(receipt.DestinationRoot);
        lock (_gate) _committed.Add(receipt, identity);
        return Task.CompletedTask;
    }

    public Task RollbackAsync(HistoryMigrationReceipt receipt, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(receipt);
        token.ThrowIfCancellationRequested();
        EnsureOwned(receipt);
        string? committedIdentity;
        lock (_gate) _committed.TryGetValue(receipt, out committedIdentity);
        if (committedIdentity is not null && Directory.Exists(receipt.DestinationRoot))
        {
            try
            {
                RejectReparse(receipt.DestinationRoot);
                if (!CryptographicOperations.FixedTimeEquals(
                        Convert.FromHexString(committedIdentity),
                        Convert.FromHexString(ComputeTreeIdentity(receipt.DestinationRoot))))
                    throw new InvalidDataException("Committed destination content changed.");
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidDataException)
            {
                throw new IOException($"Cannot rollback history migration because destination '{receipt.DestinationRoot}' changed.", error);
            }
            Directory.Delete(receipt.DestinationRoot, true);
        }
        if (Directory.Exists(receipt.StagingRoot))
            Directory.Delete(receipt.StagingRoot, true);
        lock (_gate)
        {
            _owned.Remove(receipt);
            _committed.Remove(receipt);
        }
        return Task.CompletedTask;
    }

    private static async Task CopyAudioTreeAsync(string source, string destination, CancellationToken token)
    {
        RejectReparse(source);
        Directory.CreateDirectory(destination);
        foreach (var entry in Directory.EnumerateFileSystemEntries(source))
        {
            token.ThrowIfCancellationRequested();
            RejectReparse(entry);
            var target = Path.Combine(destination, Path.GetFileName(entry));
            if (Directory.Exists(entry))
                await CopyAudioTreeAsync(entry, target, token).ConfigureAwait(false);
            else
                await CopyFileAsync(entry, target, token).ConfigureAwait(false);
        }
    }

    private static async Task CopyFileAsync(string source, string destination, CancellationToken token)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        await using var input = new FileStream(source, FileMode.Open, FileAccess.Read, FileShare.Read, 81920,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        await using var output = new FileStream(destination, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920,
            FileOptions.Asynchronous | FileOptions.WriteThrough);
        await input.CopyToAsync(output, token).ConfigureAwait(false);
        await output.FlushAsync(token).ConfigureAwait(false);
        output.Flush(flushToDisk: true);
        if (input.Length != output.Length)
            throw new InvalidDataException($"Copied file size differs for '{source}'.");
    }

    private static async Task ValidateStagingAsync(string staging, CancellationToken token)
    {
        var historyPath = Path.Combine(staging, "history.json");
        if (!File.Exists(historyPath)) return;
        TranslationRecord[] records;
        try
        {
            await using var stream = new FileStream(historyPath, FileMode.Open, FileAccess.Read, FileShare.Read, 81920, FileOptions.Asynchronous);
            records = await JsonSerializer.DeserializeAsync<TranslationRecord[]>(stream, JsonOptions, token).ConfigureAwait(false)
                ?? throw new InvalidDataException("History document cannot be null.");
        }
        catch (JsonException error)
        {
            throw new InvalidDataException("Staged history JSON is malformed.", error);
        }
        if (records.GroupBy(record => record.Id).Any(group => group.Count() != 1))
            throw new InvalidDataException("Staged history contains duplicate record IDs.");

        foreach (var reference in records.SelectMany(record => new[] { record.SourceAudioPath, record.ResultAudioPath }).Where(path => path is not null))
        {
            var relative = ValidateAudioReference(reference!);
            var fullPath = Path.Combine(staging, relative);
            if (!File.Exists(fullPath))
                throw new InvalidDataException($"Referenced audio file '{reference}' is missing.");
            RejectReparsePath(staging, fullPath);
            _ = new FileInfo(fullPath).Length;
        }
    }

    private static string ValidateAudioReference(string reference)
    {
        if (string.IsNullOrWhiteSpace(reference) || Path.IsPathRooted(reference))
            throw new InvalidDataException("Audio path must be relative.");
        var normalized = reference.Replace(Path.AltDirectorySeparatorChar, Path.DirectorySeparatorChar);
        var parts = normalized.Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || !string.Equals(parts[0], "Audio", StringComparison.OrdinalIgnoreCase)
            || parts.Any(part => part is "." or ".."))
            throw new InvalidDataException("Audio path must stay under Audio.");
        return Path.Combine(parts);
    }

    private static string ComputeTreeIdentity(string root)
    {
        RejectReparse(root);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        foreach (var path in Directory.EnumerateFileSystemEntries(root, "*", SearchOption.AllDirectories)
                     .OrderBy(path => Path.GetRelativePath(root, path), StringComparer.OrdinalIgnoreCase))
        {
            RejectReparse(path);
            var relative = Path.GetRelativePath(root, path).Replace(Path.DirectorySeparatorChar, '/');
            hash.AppendData(System.Text.Encoding.UTF8.GetBytes((Directory.Exists(path) ? "D:" : "F:") + relative + "\0"));
            if (File.Exists(path))
            {
                using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
                var buffer = new byte[81920];
                int read;
                while ((read = stream.Read(buffer)) != 0) hash.AppendData(buffer.AsSpan(0, read));
            }
        }
        return Convert.ToHexString(hash.GetHashAndReset());
    }

    private static void EnsureEmptyOrMissing(string path)
    {
        if (File.Exists(path)) throw new InvalidOperationException($"History destination '{path}' already exists as a file.");
        if (Directory.Exists(path) && Directory.EnumerateFileSystemEntries(path).Any())
            throw new InvalidOperationException($"History destination '{path}' is not empty.");
    }

    private void EnsureOwned(HistoryMigrationReceipt receipt)
    {
        lock (_gate)
        {
            if (!_owned.Contains(receipt))
                throw new InvalidOperationException("Migration receipt is not owned by this migrator.");
        }
    }

    private void DeleteOwnedStaging(HistoryMigrationReceipt receipt)
    {
        lock (_gate)
        {
            if (!_owned.Remove(receipt)) return;
        }
        if (Directory.Exists(receipt.StagingRoot)) Directory.Delete(receipt.StagingRoot, true);
    }

    private static string Normalize(string path)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        return Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
    }

    private static bool PathEquals(string left, string right) =>
        string.Equals(left, right, StringComparison.OrdinalIgnoreCase);

    private static bool Contains(string parent, string child) =>
        child.StartsWith(parent + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase);

    private static void RejectReparsePath(string root, string path)
    {
        var current = root;
        RejectReparse(current);
        foreach (var part in Path.GetRelativePath(root, path).Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries))
        {
            current = Path.Combine(current, part);
            RejectReparse(current);
        }
    }

    private static void RejectReparseAncestors(string path)
    {
        for (DirectoryInfo? current = new(path); current is not null && current.Exists; current = current.Parent)
            RejectReparse(current.FullName);
    }

    private static void RejectReparse(string path)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException($"History migration does not follow reparse point '{path}'.");
    }
}
