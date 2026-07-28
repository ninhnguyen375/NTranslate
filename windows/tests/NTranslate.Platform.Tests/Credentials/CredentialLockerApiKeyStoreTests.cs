using NTranslate.Core.Credentials;
using NTranslate.Platform.Credentials;
using Windows.Security.Credentials;

namespace NTranslate.Platform.Tests.Credentials;

[Collection("Credential Locker")]
public sealed class CredentialLockerApiKeyStoreTests
{
    [Fact]
    public async Task Store_round_trips_updates_and_deletes_isolated_credential()
    {
        var resource = $"local.ninh.ntranslate.tests.{Guid.NewGuid():N}";
        const string userName = "apiKey";
        var store = new CredentialLockerApiKeyStore(resource, userName);

        try
        {
            Assert.Null(await store.LoadAsync());

            await store.SaveAsync("  first-secret  ");
            Assert.Equal("first-secret", await store.LoadAsync());

            await store.SaveAsync("second-secret");
            Assert.Equal("second-secret", await store.LoadAsync());

            await store.SaveAsync(" \t\r\n ");
            Assert.Null(await store.LoadAsync());

            await store.DeleteAsync();
            Assert.Null(await store.LoadAsync());
        }
        finally
        {
            RemoveExactCredential(resource, userName);
        }
    }

    [Fact]
    public async Task FailedReplacementRestoresExistingCredential()
    {
        var vault = new FailingReplacementVault("old-secret");
        var store = new CredentialLockerApiKeyStore("resource", "apiKey", vault);

        var error = await Assert.ThrowsAsync<CredentialStoreException>(() => store.SaveAsync("new-secret"));

        Assert.Equal("old-secret", await store.LoadAsync());
        Assert.IsType<InvalidOperationException>(error.InnerException);
        Assert.Equal(2, vault.AddCalls);
    }

    private sealed class FailingReplacementVault(string password) : ICredentialVault
    {
        private string? _password = password;
        public int AddCalls { get; private set; }

        public string? Retrieve(string resource, string userName) => _password;
        public void Remove(string resource, string userName) => _password = null;
        public void Add(string resource, string userName, string value)
        {
            AddCalls++;
            if (AddCalls == 1)
                throw new InvalidOperationException("replacement failed");
            _password = value;
        }
    }

    private static void RemoveExactCredential(string resource, string userName)
    {
        var vault = new PasswordVault();

        try
        {
            vault.Remove(vault.Retrieve(resource, userName));
        }
        catch (Exception exception) when ((uint)exception.HResult == 0x80070490)
        {
        }
    }
}

[CollectionDefinition("Credential Locker", DisableParallelization = true)]
public sealed class CredentialLockerCollection;
