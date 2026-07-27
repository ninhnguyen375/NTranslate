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
