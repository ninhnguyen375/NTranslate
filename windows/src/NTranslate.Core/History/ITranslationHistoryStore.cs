namespace NTranslate.Core.History;

public enum TranslationAudioKind
{
    Source,
    Result
}

public interface ITranslationHistoryStore
{
    IReadOnlyList<TranslationRecord> Records { get; }
    string? LoadError { get; }
    Task AppendAsync(TranslationRecord record, CancellationToken token = default);
    Task SetSavedAsync(Guid id, bool saved, CancellationToken token = default);
    Task AttachAudioAsync(Guid id, TranslationAudioKind kind, ReadOnlyMemory<byte> data, CancellationToken token = default);
    Task<byte[]?> ReadAudioAsync(Guid id, TranslationAudioKind kind, CancellationToken token = default);
    Task RemoveAsync(IReadOnlySet<Guid> ids, CancellationToken token = default);
}
