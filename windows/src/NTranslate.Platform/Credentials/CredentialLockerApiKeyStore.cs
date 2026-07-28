using NTranslate.Core.Credentials;
using Windows.Security.Credentials;

namespace NTranslate.Platform.Credentials;

internal interface ICredentialVault
{
    string? Retrieve(string resource, string userName);
    void Add(string resource, string userName, string password);
    void Remove(string resource, string userName);
}

internal sealed class PasswordCredentialVault : ICredentialVault
{
    private readonly PasswordVault _vault = new();

    public string? Retrieve(string resource, string userName)
    {
        try
        {
            var credential = _vault.Retrieve(resource, userName);
            credential.RetrievePassword();
            return credential.Password;
        }
        catch (Exception exception) when ((uint)exception.HResult == 0x80070490)
        {
            return null;
        }
    }

    public void Add(string resource, string userName, string password) =>
        _vault.Add(new PasswordCredential(resource, userName, password));

    public void Remove(string resource, string userName)
    {
        try { _vault.Remove(_vault.Retrieve(resource, userName)); }
        catch (Exception exception) when ((uint)exception.HResult == 0x80070490) { }
    }
}

public sealed class CredentialLockerApiKeyStore : IApiKeyStore
{
    public const string DefaultResource = "local.ninh.ntranslate";
    public const string DefaultUserName = "apiKey";

    private readonly string _resource;
    private readonly string _userName;
    private readonly ICredentialVault _vault;

    public CredentialLockerApiKeyStore(
        string resource = DefaultResource,
        string userName = DefaultUserName)
        : this(resource, userName, new PasswordCredentialVault()) { }

    internal CredentialLockerApiKeyStore(string resource, string userName, ICredentialVault vault)
    {
        _resource = resource;
        _userName = userName;
        _vault = vault;
    }

    public Task<string?> LoadAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        try
        {
            return Task.FromResult(_vault.Retrieve(_resource, _userName));
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
            var existing = _vault.Retrieve(_resource, _userName);
            if (existing is null)
            {
                _vault.Add(_resource, _userName, trimmedApiKey);
                return Task.CompletedTask;
            }

            _vault.Remove(_resource, _userName);
            try
            {
                _vault.Add(_resource, _userName, trimmedApiKey);
            }
            catch
            {
                _vault.Add(_resource, _userName, existing);
                throw;
            }
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

    private void RemoveExisting() => _vault.Remove(_resource, _userName);
}
