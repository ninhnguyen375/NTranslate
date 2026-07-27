namespace NTranslate.Core.Credentials;

public interface IApiKeyStore
{
    Task<string?> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(string apiKey, CancellationToken cancellationToken = default);
    Task DeleteAsync(CancellationToken cancellationToken = default);
}

public sealed class CredentialStoreException(string message, Exception innerException)
    : Exception(message, innerException);
