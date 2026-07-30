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
    public async Task UnchangedSaveSkipsEveryMutation()
    {
        var fixture = new Fixture();

        await fixture.Coordinator.SaveAsync(
            fixture.OldConfig, fixture.OldApiKey!, fixture.OldConfig.SpeechRate, fixture.OldConfig.StartWithWindows,
            @"C:\same-root\", @"c:\same-root");

        Assert.Equal(["credential.load", "config.load"], fixture.Events);
    }

    [Fact]
    public async Task CancellationAfterMutationRollsBackThenPropagatesCancellation()
    {
        var fixture = new Fixture { CancelDuringConfigSave = true };

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => fixture.SaveAsync(fixture.Cancellation.Token));

        Assert.Equal(
            ["migration.prepare", "credential.load", "credential.save", "config.load", "config.save", "config.restore", "credential.save-old", "migration.rollback"],
            fixture.Events);
    }

    [Fact]
    public async Task CancellationWithRollbackFailureSurfacesCommitException()
    {
        var fixture = new Fixture
        {
            CancelDuringConfigSave = true,
            ConfigRestoreException = new IOException("rollback failed")
        };

        var exception = await Assert.ThrowsAsync<SettingsCommitException>(() => fixture.SaveAsync(fixture.Cancellation.Token));

        Assert.IsAssignableFrom<OperationCanceledException>(exception.PrimaryException);
        Assert.Equal(["rollback failed"], exception.RollbackExceptions.Select(error => error.Message));
    }

    [Fact]
    public async Task RuntimeFailureRollsBackCommittedState()
    {
        var fixture = new Fixture { RuntimeException = new IOException("runtime") };

        var exception = await Assert.ThrowsAsync<SettingsCommitException>(() => fixture.SaveAsync());

        Assert.Equal("runtime", exception.PrimaryException.Message);
        Assert.Equal(["config.restore", "credential.save-old", "migration.rollback"], fixture.Events[^3..]);
    }

    [Fact]
    public async Task OverlappingSavesAreSerializedAndCannotStaleRollbackSuccessfulSave()
    {
        var fixture = new Fixture { BlockFirstRuntime = true, FailFirstRuntime = true };
        var first = fixture.SaveAsync(fixture.NewConfig with { Model = "first" }, "first-key");
        await fixture.RuntimeStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
        var second = fixture.SaveAsync(fixture.NewConfig with { Model = "second" }, "second-key");

        Assert.False(second.IsCompleted);
        fixture.ReleaseRuntime();
        await Assert.ThrowsAsync<SettingsCommitException>(() => first);
        await second;

        Assert.Equal("second", fixture.CurrentConfig.Model);
        Assert.Equal("second-key", fixture.CurrentApiKey);
    }

    [Fact]
    public async Task CancellationWhileWaitingForSaveDoesNotEnterTransaction()
    {
        var fixture = new Fixture { BlockFirstRuntime = true };
        var first = fixture.SaveAsync(fixture.NewConfig with { Model = "first" }, "first-key");
        await fixture.RuntimeStarted.Task.WaitAsync(TimeSpan.FromSeconds(1));
        using var cancellation = new CancellationTokenSource();
        var waiting = fixture.SaveAsync(fixture.NewConfig with { Model = "second" }, "second-key", cancellation.Token);

        cancellation.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => waiting);
        fixture.ReleaseRuntime();
        await first;

        Assert.Equal("first", fixture.CurrentConfig.Model);
        Assert.Equal("first-key", fixture.CurrentApiKey);
    }

    private sealed class Fixture
    {
        private readonly FakeConfigStore _config;
        private readonly FakeCredentialStore _credential;
        private readonly FakeMigrator _migrator;

        public Fixture()
        {
            OldConfig = AppConfig.Default;
            CurrentConfig = OldConfig;
            NewConfig = OldConfig with { Model = "new-model", HistoryDirectory = "new-root" };
            _config = new(this);
            _credential = new(this);
            _migrator = new(this);
            Coordinator = new(_config, _credential, _migrator, ApplyRuntimeAsync);
        }

        public List<string> Events { get; } = [];
        public AppConfig OldConfig { get; }
        public AppConfig NewConfig { get; }
        public AppConfig CurrentConfig { get; private set; }
        public string? OldApiKey { get; set; } = "old-key";
        public string? CurrentApiKey { get; private set; } = "old-key";
        public Exception? CredentialSaveException { get; set; }
        public Exception? ConfigSaveException { get; set; }
        public Exception? MigrationCommitException { get; set; }
        public Exception? ConfigRestoreException { get; set; }
        public Exception? CredentialRestoreException { get; set; }
        public Exception? MigrationRollbackException { get; set; }
        public Exception? RuntimeException { get; set; }
        public bool CancelDuringConfigSave { get; set; }
        public bool BlockFirstRuntime { get; set; }
        public bool FailFirstRuntime { get; set; }
        public TaskCompletionSource RuntimeStarted { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private readonly TaskCompletionSource _runtimeRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private int _runtimeCount;
        public CancellationTokenSource Cancellation { get; } = new();
        public SettingsSaveCoordinator Coordinator { get; }

        public Task SaveAsync(CancellationToken token = default) => SaveAsync(NewConfig, "new-key", token);

        public Task SaveAsync(AppConfig config, string apiKey, CancellationToken token = default) =>
            Coordinator.SaveAsync(config, apiKey, 1.25, true, @"C:\old-root", @"C:\new-root", token);

        public void ReleaseRuntime() => _runtimeRelease.TrySetResult();

        private async Task ApplyRuntimeAsync(AppConfig config, double speechRate, bool startWithWindows, CancellationToken token)
        {
            Events.Add("runtime");
            var call = Interlocked.Increment(ref _runtimeCount);
            Assert.Equal(1.25, speechRate);
            Assert.True(startWithWindows);
            if (call == 1 && BlockFirstRuntime)
            {
                RuntimeStarted.TrySetResult();
                await _runtimeRelease.Task;
            }
            if (call == 1 && FailFirstRuntime) throw new IOException("runtime");
            if (RuntimeException is not null) throw RuntimeException;
        }

        private sealed class FakeConfigStore(Fixture fixture) : IConfigStore
        {
            private int _saveCount;

            public Task<AppConfig> LoadAsync(CancellationToken token = default)
            {
                fixture.Events.Add("config.load");
                return Task.FromResult(fixture.CurrentConfig);
            }

            public Task SaveAsync(AppConfig config, CancellationToken token = default)
            {
                _saveCount++;
                fixture.Events.Add(config == fixture.OldConfig ? "config.restore" : "config.save");
                if (_saveCount == 1 && fixture.CancelDuringConfigSave)
                {
                    fixture.Cancellation.Cancel();
                    return Task.FromCanceled(fixture.Cancellation.Token);
                }

                var error = config == fixture.OldConfig ? fixture.ConfigRestoreException : fixture.ConfigSaveException;
                if (error is not null) return Task.FromException(error);
                fixture.CurrentConfig = config;
                return Task.CompletedTask;
            }
        }

        private sealed class FakeCredentialStore(Fixture fixture) : IApiKeyStore
        {
            private int _saveCount;

            public Task<string?> LoadAsync(CancellationToken cancellationToken = default)
            {
                fixture.Events.Add("credential.load");
                return Task.FromResult(_saveCount == 0 ? fixture.OldApiKey : fixture.CurrentApiKey);
            }

            public Task SaveAsync(string apiKey, CancellationToken cancellationToken = default)
            {
                _saveCount++;
                var restoring = apiKey == fixture.OldApiKey;
                fixture.Events.Add(restoring ? "credential.save-old" : "credential.save");
                var error = restoring ? fixture.CredentialRestoreException : fixture.CredentialSaveException;
                if (error is not null) return Task.FromException(error);
                fixture.CurrentApiKey = apiKey;
                return Task.CompletedTask;
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
