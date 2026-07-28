using NTranslate.Core.History;

namespace NTranslate.App.History;

public interface IAcceptedTranslationSink
{
    Task AcceptAsync(TranslationRecord record, CancellationToken token);
}

public sealed class AcceptedTranslationSink(ITranslationHistoryStore store) : IAcceptedTranslationSink
{
    public Task AcceptAsync(TranslationRecord record, CancellationToken token) => store.AppendAsync(record, token);
}
