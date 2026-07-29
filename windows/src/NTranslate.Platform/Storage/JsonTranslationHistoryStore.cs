using System.Text.Json;
using NTranslate.Core.History;

namespace NTranslate.Platform.Storage;

public sealed class JsonTranslationHistoryStore : ITranslationHistoryStore
{
    private static readonly JsonSerializerOptions JsonOptions = new() { WriteIndented = true };
    private readonly string _root;
    private readonly string _historyPath;
    private readonly IAtomicFileWriter _writer;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private TranslationRecord[] _records = [];

    public JsonTranslationHistoryStore(string root, IAtomicFileWriter? writer = null)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(root);
        _root = Path.GetFullPath(root);
        _historyPath = Path.Combine(_root, "history.json");
        _writer = writer ?? new AtomicFileWriter();
        Load();
    }

    public IReadOnlyList<TranslationRecord> Records => Array.AsReadOnly(_records);
    public string? LoadError { get; private set; }

    public Task AppendAsync(TranslationRecord record, CancellationToken token = default)
    {
        if (!IsSupportedMode(record.Mode))
            throw new ArgumentOutOfRangeException(nameof(record), record.Mode, "Translation mode is not supported by history.");
        return MutateAsync(records =>
        {
            if (records.Any(existing => existing.Id == record.Id))
                throw new InvalidOperationException($"Record '{record.Id}' already exists.");
            return records.Append(record).OrderByDescending(item => item.Timestamp).ToArray();
        }, token);
    }

    public Task SetSavedAsync(Guid id, bool saved, CancellationToken token = default) => MutateAsync(records =>
    {
        var index = FindIndex(records, id);
        var changed = records.ToArray();
        changed[index] = changed[index] with { IsSaved = saved };
        return changed;
    }, token);

    public async Task AttachAudioAsync(Guid id, TranslationAudioKind kind, ReadOnlyMemory<byte> data, CancellationToken token = default)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        string? audioPath = null;
        try
        {
            EnsureWritable();
            var index = FindIndex(_records, id);
            audioPath = Path.Combine("Audio", $"{id:D}-{kind}-{Guid.NewGuid():N}.audio");
            var fullAudioPath = ValidateAudioPath(audioPath, allowMissingLeaf: true);
            await _writer.WriteAsync(fullAudioPath, data, token).ConfigureAwait(false);
            var changed = _records.ToArray();
            var previousPath = kind == TranslationAudioKind.Source ? changed[index].SourceAudioPath : changed[index].ResultAudioPath;
            changed[index] = kind == TranslationAudioKind.Source
                ? changed[index] with { SourceAudioPath = audioPath }
                : changed[index] with { ResultAudioPath = audioPath };
            try
            {
                await PersistAsync(changed, token).ConfigureAwait(false);
                _records = changed;
                DeleteOwnedAudio(previousPath);
            }
            catch
            {
                DeleteOwnedAudio(audioPath);
                throw;
            }
        }
        finally { _gate.Release(); }
    }

    public async Task<byte[]?> ReadAudioAsync(Guid id, TranslationAudioKind kind, CancellationToken token = default)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            var record = _records[FindIndex(_records, id)];
            var relativePath = kind == TranslationAudioKind.Source ? record.SourceAudioPath : record.ResultAudioPath;
            if (relativePath is null) return null;
            var path = ValidateAudioPath(relativePath, allowMissingLeaf: true);
            try { return await File.ReadAllBytesAsync(path, token).ConfigureAwait(false); }
            catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
        }
        finally { _gate.Release(); }
    }

    public async Task RemoveAsync(IReadOnlySet<Guid> ids, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(ids);
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            EnsureWritable();
            if (ids.Count == 0) return;
            var removed = _records.Where(record => ids.Contains(record.Id)).ToArray();
            var changed = _records.Where(record => !ids.Contains(record.Id)).ToArray();
            if (removed.Length == 0) return;
            await PersistAsync(changed, token).ConfigureAwait(false);
            _records = changed;
            foreach (var record in removed)
            {
                DeleteOwnedAudio(record.SourceAudioPath);
                DeleteOwnedAudio(record.ResultAudioPath);
            }
        }
        finally { _gate.Release(); }
    }

    private async Task MutateAsync(Func<TranslationRecord[], TranslationRecord[]> mutation, CancellationToken token)
    {
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            EnsureWritable();
            var changed = mutation(_records);
            await PersistAsync(changed, token).ConfigureAwait(false);
            _records = changed;
        }
        finally { _gate.Release(); }
    }

    private void Load()
    {
        if (!File.Exists(_historyPath)) return;
        try
        {
            var loaded = JsonSerializer.Deserialize<TranslationRecord[]>(File.ReadAllBytes(_historyPath), JsonOptions)
                ?? throw new InvalidDataException("History document cannot be null.");
            if (loaded.GroupBy(record => record.Id).Any(group => group.Count() != 1))
                throw new InvalidDataException("History contains duplicate record IDs.");
            if (loaded.Any(record => !IsSupportedMode(record.Mode)))
                throw new InvalidDataException("History contains an unsupported translation mode.");
            foreach (var audioPath in loaded.SelectMany(record => new[] { record.SourceAudioPath, record.ResultAudioPath }))
                if (audioPath is not null) ValidateAudioPath(audioPath, allowMissingLeaf: true);
            _records = loaded.OrderByDescending(record => record.Timestamp).ToArray();
        }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException or InvalidDataException)
        {
            LoadError = $"Cannot load '{_historyPath}': {error.Message}";
            _records = [];
        }
    }

    private Task PersistAsync(TranslationRecord[] records, CancellationToken token) =>
        _writer.WriteAsync(_historyPath, JsonSerializer.SerializeToUtf8Bytes(records, JsonOptions), token);

    private static bool IsSupportedMode(NTranslate.Core.Translation.TranslationMode mode) =>
        mode is NTranslate.Core.Translation.TranslationMode.Translate or NTranslate.Core.Translation.TranslationMode.ImageTranslate;

    private void EnsureWritable()
    {
        if (LoadError is not null) throw new InvalidOperationException(LoadError);
    }

    private static int FindIndex(TranslationRecord[] records, Guid id)
    {
        var index = Array.FindIndex(records, record => record.Id == id);
        return index >= 0 ? index : throw new KeyNotFoundException($"Record '{id}' was not found.");
    }

    private string ValidateAudioPath(string relativePath, bool allowMissingLeaf)
    {
        if (string.IsNullOrWhiteSpace(relativePath) || Path.IsPathRooted(relativePath))
            throw new InvalidDataException("Audio path must be relative.");
        var normalized = relativePath.Replace(Path.AltDirectorySeparatorChar, Path.DirectorySeparatorChar);
        var parts = normalized.Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2 || !string.Equals(parts[0], "Audio", StringComparison.OrdinalIgnoreCase)
            || parts.Any(part => part is "." or ".."))
            throw new InvalidDataException("Audio path must stay under Audio.");
        var fullPath = Path.GetFullPath(Path.Combine(_root, normalized));
        var audioRoot = Path.GetFullPath(Path.Combine(_root, "Audio"));
        if (!fullPath.StartsWith(audioRoot + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            throw new InvalidDataException("Audio path escapes storage root.");
        ValidateNoReparsePoints(audioRoot, fullPath, allowMissingLeaf);
        return fullPath;
    }

    private static void ValidateNoReparsePoints(string audioRoot, string fullPath, bool allowMissingLeaf)
    {
        var current = audioRoot;
        if (!Directory.Exists(current))
        {
            if (allowMissingLeaf) return;
            throw new DirectoryNotFoundException($"Audio directory '{current}' does not exist.");
        }
        ValidateExistingPath(current);
        var relative = Path.GetRelativePath(audioRoot, fullPath);
        var parts = relative.Split(Path.DirectorySeparatorChar, StringSplitOptions.RemoveEmptyEntries);
        for (var index = 0; index < parts.Length; index++)
        {
            current = Path.Combine(current, parts[index]);
            if (!File.Exists(current) && !Directory.Exists(current))
            {
                if (allowMissingLeaf) return;
                throw new FileNotFoundException("Audio path does not exist.", current);
            }
            ValidateExistingPath(current);
        }
    }

    private static void ValidateExistingPath(string path)
    {
        if ((File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0)
            throw new InvalidDataException($"Audio path contains reparse point '{path}'.");
    }

    private void DeleteOwnedAudio(string? relativePath)
    {
        if (relativePath is null) return;
        try { File.Delete(ValidateAudioPath(relativePath, allowMissingLeaf: true)); }
        catch (FileNotFoundException) { }
        catch (DirectoryNotFoundException) { }
    }
}
