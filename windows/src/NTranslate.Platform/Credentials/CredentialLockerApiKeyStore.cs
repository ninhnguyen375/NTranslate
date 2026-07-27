using NTranslate.Core.Credentials;
using Windows.Security.Credentials;

namespace NTranslate.Platform.Credentials;

public sealed class CredentialLockerApiKeyStore : IApiKeyStore
{
    public const string DefaultResource = "local.ninh.ntranslate";
    public const string DefaultUserName = "apiKey";

    private const uint ElementNotFound = 0x80070490;
    private readonly string _resource;
    private readonly string _userName;
    private readonly PasswordVault _vault = new();

    public CredentialLockerApiKeyStore(
        string resource = DefaultResource,
        string userName = DefaultUserName)
    {
        _resource = resource;
        _userName = userName;
    }

    public Task<string?> LoadAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        try
        {
            var credential = _vault.Retrieve(_resource, _userName);
            credential.RetrievePassword();
            return Task.FromResult<string?>(credential.Password);
        }
        catch (Exception exception) when (IsNotFound(exception))
        {
            return Task.FromResult<string?>(null);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new CredentialStoreException("Failed to load API key from Credential Locker.", exception);
        }
    }

    public Task SaveAsync(string apiKey, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(apiKey);
        cancellationToken.ThrowIfCancellationRequested();
        var trimmedApiKey = apiKey.Trim();

        if (trimmedApiKey.Length == 0)
        {
            return DeleteAsync(cancellationToken);
        }

        try
        {
            RemoveExisting();
            _vault.Add(new PasswordCredential(_resource, _userName, trimmedApiKey));
            return Task.CompletedTask;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new CredentialStoreException("Failed to save API key to Credential Locker.", exception);
        }
    }

    public Task DeleteAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        try
        {
            RemoveExisting();
            return Task.CompletedTask;
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new CredentialStoreException("Failed to delete API key from Credential Locker.", exception);
        }
    }

    private void RemoveExisting()
    {
        try
        {
            _vault.Remove(_vault.Retrieve(_resource, _userName));
        }
        catch (Exception exception) when (IsNotFound(exception))
        {
        }
    }

    private static bool IsNotFound(Exception exception) => (uint)exception.HResult == ElementNotFound;
}
