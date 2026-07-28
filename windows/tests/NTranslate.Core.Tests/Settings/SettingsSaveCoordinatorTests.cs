using NTranslate.Core.Configuration;
using NTranslate.Core.Credentials;
using NTranslate.Core.Settings;

namespace NTranslate.Core.Tests.Settings;

public sealed class SettingsSaveCoordinatorTests
{
    [Fact]
    public async Task InvalidRequestPerformsNoIo()
    {
        var fixture = new Fixture();
        var invalid = fixture.NewConfig with { ApiBaseUrl = "http://example.test" };

        var exception = await Assert.ThrowsAsync<SettingsValidationException>(() =>
            fixture.Coordinator.SaveAsync(invalid, "new-key", 1, false, @"C:\old-root", @"C:\new-root"));

        Assert.Contains(exception.Issues, issue => issue.Field == nameof(AppConfig.ApiBaseUrl));
        Assert.Empty(fixture.Events);
    }

    [Fact]
    public async Task CredentialFailureDoesNotSaveConfigOrApplyRuntimeAndRollsBackPreparedMigration()
    {
        var fixture = new Fixture { CredentialSaveException = new IOException("credential") };

        var exception = await Assert.ThrowsAsync<SettingsCommitException>(() => fixture.SaveAsync());

        Assert.Equal("credential", exception.PrimaryException.Message);
        Assert.Equal(["migration.prepare", "credential.load", "credential.save", "credential.save-old", "migration.rollback"], fixture.Events);
        Assert.DoesNotContain("config.save", fixture.Events);
        Assert.DoesNotContain("runtime", fixture.Events);
    }

    [Theory]
    [InlineData("old-key", "credential.save-old")]
    [InlineData(null, "credential.delete")]
    public async Task ConfigFailureRestoresPriorCredential(string? oldKey, string expectedRollback)
    {
        var fixture = new Fixture { OldApiKey = oldKey, ConfigSaveException = new IOException("config") };

        var exception = await Assert.ThrowsAsync<SettingsCommitException>(() => fixture.SaveAsync());

        Assert.Equal("config", exception.PrimaryException.Message);
        Assert.Contains(expectedRollback, fixture.Events);
        Assert.Equal("migration.rollback", fixture.Events[^1]);
        Assert.DoesNotContain("runtime", fixture.Events);
    }

    [Fact]
    public async Task MigrationCommitFailureRollsBackConfigCredentialAndMigrationInReverseOrder()
    {
        var fixture = new Fixture { MigrationCommitException = new IOException("migration") };

        var exception = await Assert.ThrowsAsync<SettingsCommitException>(() => fixture.SaveAsync());

        Assert.Equal("migration", exception.PrimaryException.Message);
        Assert.Equal(
            ["migration.prepare", "credential.load", "credential.save", "config.load", "config.save", "migration.commit", "config.restore", "credential.save-old", "migration.rollback"],
            fixture.Events);
        Assert.DoesNotContain("runtime", fixture.Events);
    }

    [Fact]
    public async Task RollbackFailurePreservesPrimaryAndEveryRollbackException()
    {
        var fixture = new Fixture
        {
            MigrationCommitException = new IOException("primary"),
            ConfigRestoreException = new IOException("config rollback"),
            CredentialRestoreException = new IOException("credential rollback"),
            MigrationRollbackException = new IOException("migration rollback")
        };

        var exception = await Assert.ThrowsAsync<SettingsCommitException>(() => fixture.SaveAsync());

        Assert.Equal("primary", exception.PrimaryException.Message);
        Assert.Equal(["config rollback", "credential rollback", "migration rollback"], exception.RollbackExceptions.Select(error => error.Message));
        Assert.Same(exception.PrimaryException, exception.InnerException);
    }

    [Fact]
    public async Task SuccessUsesRequiredOrderAndAppliesRuntimeOnlyAfterEveryCommit()
    {
        var fixture = new Fixture();

        await fixture.SaveAsync();

        Assert.Equal(
            ["migration.prepare", "credential.load", "credential.save", "config.load", "config.save", "migration.commit", "runtime"],
            fixture.Events);
    }

    [Fact]
    public async Task RuntimeFailureRollsBackCommittedState()
    {
        var fixture = new Fixture { RuntimeException = new IOException("runtime") };

        var exception = await Assert.ThrowsAsync<SettingsCommitException>(() => fixture.SaveAsync());

        Assert.Equal("runtime", exception.PrimaryException.Message);
        Assert.Equal(["config.restore", "credential.save-old", "migration.rollback"], fixture.Events[^3..]);
    }

    private sealed class Fixture
    {
        private readonly FakeConfigStore _config;
        private readonly FakeCredentialStore _credential;
        private readonly FakeMigrator _migrator;

        public Fixture()
        {
            OldConfig = AppConfig.Default;
            NewConfig = OldConfig with { Model = "new-model", HistoryDirectory = "new-root" };
            _config = new(this);
            _credential = new(this);
            _migrator = new(this);
            Coordinator = new(_config, _credential, _migrator, ApplyRuntimeAsync);
        }

        public List<string> Events { get; } = [];
        public AppConfig OldConfig { get; }
        public AppConfig NewConfig { get; }
        public string? OldApiKey { get; set; } = "old-key";
        public Exception? CredentialSaveException { get; set; }
        public Exception? ConfigSaveException { get; set; }
        public Exception? MigrationCommitException { get; set; }
        public Exception? ConfigRestoreException { get; set; }
        public Exception? CredentialRestoreException { get; set; }
        public Exception? MigrationRollbackException { get; set; }
        public Exception? RuntimeException { get; set; }
        public SettingsSaveCoordinator Coordinator { get; }

        public Task SaveAsync() => Coordinator.SaveAsync(NewConfig, "new-key", 1.25, true, @"C:\old-root", @"C:\new-root");

        private Task ApplyRuntimeAsync(AppConfig config, double speechRate, bool startWithWindows, CancellationToken token)
        {
            Events.Add("runtime");
            Assert.Same(NewConfig, config);
            Assert.Equal(1.25, speechRate);
            Assert.True(startWithWindows);
            return RuntimeException is null ? Task.CompletedTask : Task.FromException(RuntimeException);
        }

        private sealed class FakeConfigStore(Fixture fixture) : IConfigStore
        {
            private int _saveCount;

            public Task<AppConfig> LoadAsync(CancellationToken token = default)
            {
                fixture.Events.Add("config.load");
                return Task.FromResult(fixture.OldConfig);
            }

            public Task SaveAsync(AppConfig config, CancellationToken token = default)
            {
                _saveCount++;
                fixture.Events.Add(_saveCount == 1 ? "config.save" : "config.restore");
                var error = _saveCount == 1 ? fixture.ConfigSaveException : fixture.ConfigRestoreException;
                return error is null ? Task.CompletedTask : Task.FromException(error);
            }
        }

        private sealed class FakeCredentialStore(Fixture fixture) : IApiKeyStore
        {
            private int _saveCount;

            public Task<string?> LoadAsync(CancellationToken cancellationToken = default)
            {
                fixture.Events.Add("credential.load");
                return Task.FromResult(fixture.OldApiKey);
            }

            public Task SaveAsync(string apiKey, CancellationToken cancellationToken = default)
            {
                _saveCount++;
                fixture.Events.Add(_saveCount == 1 ? "credential.save" : "credential.save-old");
                var error = _saveCount == 1 ? fixture.CredentialSaveException : fixture.CredentialRestoreException;
                return error is null ? Task.CompletedTask : Task.FromException(error);
            }

            public Task DeleteAsync(CancellationToken cancellationToken = default)
            {
                fixture.Events.Add("credential.delete");
                return fixture.CredentialRestoreException is null
                    ? Task.CompletedTask
                    : Task.FromException(fixture.CredentialRestoreException);
            }
        }

        private sealed class FakeMigrator(Fixture fixture) : IHistoryDirectoryMigrator
        {
            public Task<HistoryMigrationReceipt?> PrepareAsync(string currentRoot, string requestedRoot, CancellationToken token = default)
            {
                fixture.Events.Add("migration.prepare");
                return Task.FromResult<HistoryMigrationReceipt?>(new(currentRoot, requestedRoot, "staging"));
            }

            public Task CommitAsync(HistoryMigrationReceipt receipt, CancellationToken token = default)
            {
                fixture.Events.Add("migration.commit");
                return fixture.MigrationCommitException is null
                    ? Task.CompletedTask
                    : Task.FromException(fixture.MigrationCommitException);
            }

            public Task RollbackAsync(HistoryMigrationReceipt receipt, CancellationToken token = default)
            {
                fixture.Events.Add("migration.rollback");
                return fixture.MigrationRollbackException is null
                    ? Task.CompletedTask
                    : Task.FromException(fixture.MigrationRollbackException);
            }
        }
    }
}
