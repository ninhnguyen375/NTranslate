using NTranslate.App.Settings;
using NTranslate.Core.Configuration;
using NTranslate.Core.Settings;

namespace NTranslate.App.Tests.Settings;

public sealed class SettingsViewModelTests
{
    [Fact]
    public async Task FailedSaveKeepsRuntimeDraftAndWindowOpen()
    {
        var original = AppConfig.Default;
        var closeCount = 0;
        var viewModel = new SettingsViewModel(
            original,
            "old-key",
            (_, _) => throw new InvalidOperationException("write failed"),
            () => closeCount++);
        viewModel.Draft.Model = "changed";

        await viewModel.SaveAsync(CancellationToken.None);

        Assert.Equal("changed", viewModel.Draft.Model);
        Assert.Equal("write failed", viewModel.ErrorMessage);
        Assert.Equal(0, closeCount);
    }

    [Fact]
    public async Task SuccessfulSaveRequestsCloseWithConfigAndSeparateKey()
    {
        AppConfig? saved = null;
        string? savedKey = null;
        var closeCount = 0;
        var viewModel = new SettingsViewModel(
            AppConfig.Default,
            "old-key",
            (request, _) => { saved = request.Config; savedKey = request.ApiKey; return Task.CompletedTask; },
            () => closeCount++);
        viewModel.Draft.Model = "changed";
        viewModel.Draft.ApiKey = "new-key";

        await viewModel.SaveAsync(CancellationToken.None);

        Assert.Equal("changed", saved?.Model);
        Assert.Equal("new-key", savedKey);
        Assert.Equal(1, closeCount);
        Assert.Null(viewModel.ErrorMessage);
    }

    [Fact]
    public async Task UnchangedSaveSkipsDelegateAndRequestsClose()
    {
        var closeCount = 0;
        var viewModel = new SettingsViewModel(
            AppConfig.Default,
            "old-key",
            (_, _) => throw new IOException("save should not run"),
            () => closeCount++);

        await viewModel.SaveAsync(CancellationToken.None);

        Assert.Equal(1, closeCount);
        Assert.Null(viewModel.ErrorMessage);
    }

    [Fact]
    public async Task InvalidSaveDoesNoIoAndKeepsWindowOpen()
    {
        var saveCount = 0;
        var closeCount = 0;
        var viewModel = new SettingsViewModel(
            AppConfig.Default,
            "key",
            (_, _) => { saveCount++; return Task.CompletedTask; },
            () => closeCount++);
        viewModel.Draft.Model = " ";

        await viewModel.SaveAsync(CancellationToken.None);

        Assert.Equal(0, saveCount);
        Assert.Equal(0, closeCount);
        Assert.Contains("Model", viewModel.ErrorMessage, StringComparison.Ordinal);
    }

    [Fact]
    public void CancelWritesNothingAndRequestsClose()
    {
        var saveCount = 0;
        var closeCount = 0;
        var viewModel = new SettingsViewModel(
            AppConfig.Default,
            "key",
            (_, _) => { saveCount++; return Task.CompletedTask; },
            () => closeCount++);

        viewModel.Cancel();

        Assert.Equal(0, saveCount);
        Assert.Equal(1, closeCount);
    }

    [Fact]
    public async Task BrowseUsesOwnerHwndAndUpdatesPath()
    {
        nint owner = 0;
        var picker = new StubPicker((nint)42, "C:\\History", hwnd => owner = hwnd);
        var viewModel = new SettingsViewModel(AppConfig.Default, "key", (_, _) => Task.CompletedTask, () => { }, picker);

        await viewModel.BrowseHistoryDirectoryAsync(CancellationToken.None);

        Assert.Equal((nint)42, owner);
        Assert.Equal("C:\\History", viewModel.Draft.HistoryDirectory);
    }

    [Fact]
    public async Task BrowseFailureSetsErrorAndKeepsDraftPath()
    {
        var original = AppConfig.Default with { HistoryDirectory = @"C:\Original" };
        var picker = new ThrowingPicker(new UnauthorizedAccessException("Folder access denied."));
        var viewModel = new SettingsViewModel(original, "key", (_, _) => Task.CompletedTask, () => { }, picker);

        await viewModel.BrowseHistoryDirectoryAsync(CancellationToken.None);

        Assert.Equal(@"C:\Original", viewModel.Draft.HistoryDirectory);
        Assert.Contains("Folder access denied.", viewModel.ErrorMessage, StringComparison.Ordinal);
    }

    [Fact]
    public async Task BrowseCompletionMutatesBoundStateOnCapturedContext()
    {
        await RunOnSingleThreadContext(async context =>
        {
            var picker = new AsyncPicker(@"C:\History");
            var viewModel = new SettingsViewModel(AppConfig.Default, "key", (_, _) => Task.CompletedTask, () => { }, picker);
            var notificationThread = 0;
            viewModel.PropertyChanged += (_, args) =>
            {
                if (args.PropertyName == nameof(viewModel.Draft)) notificationThread = Environment.CurrentManagedThreadId;
            };

            await viewModel.BrowseHistoryDirectoryAsync(CancellationToken.None);

            Assert.Equal(context.ThreadId, notificationThread);
        });
    }

    [Fact]
    public async Task SaveCompletionMutatesBoundStateAndClosesOnCapturedContext()
    {
        await RunOnSingleThreadContext(async context =>
        {
            var closeThread = 0;
            var viewModel = new SettingsViewModel(
                AppConfig.Default,
                "key",
                async (_, _) => await Task.Run(() => { }),
                () => closeThread = Environment.CurrentManagedThreadId);
            viewModel.Draft.Model = "changed";

            await viewModel.SaveAsync(CancellationToken.None);

            Assert.Equal(context.ThreadId, closeThread);
        });
    }

    [Fact]
    public async Task CommitFailureShowsPrimaryCauseAndRollbackFailureOnlyWhenPresent()
    {
        var primary = new IOException("Config file is locked.");
        var rollback = new IOException("Could not restore API key.");
        var viewModel = new SettingsViewModel(
            AppConfig.Default,
            "key",
            (_, _) => throw new SettingsCommitException(primary, [rollback]),
            () => { });
        viewModel.Draft.Model = "changed";

        await viewModel.SaveAsync(CancellationToken.None);

        Assert.Contains("Config file is locked.", viewModel.ErrorMessage, StringComparison.Ordinal);
        Assert.Contains("Could not restore API key.", viewModel.ErrorMessage, StringComparison.Ordinal);
        Assert.DoesNotContain("Settings commit failed.", viewModel.ErrorMessage, StringComparison.Ordinal);
    }

    [Fact]
    public async Task CommitFailureWithoutRollbackFailureShowsOnlyPrimaryCause()
    {
        var viewModel = new SettingsViewModel(
            AppConfig.Default,
            "key",
            (_, _) => throw new SettingsCommitException(new IOException("Config file is locked."), []),
            () => { });
        viewModel.Draft.Model = "changed";

        await viewModel.SaveAsync(CancellationToken.None);

        Assert.Equal("Config file is locked.", viewModel.ErrorMessage);
    }

    [Fact]
    public void LanguageListsCanBeEdited()
    {
        var viewModel = CreateViewModel();
        viewModel.NewLanguage = "French";
        viewModel.AddLanguage();
        viewModel.NewTargetLanguage = "Japanese";
        viewModel.AddTargetLanguage();

        Assert.Contains("French", viewModel.Draft.Languages);
        Assert.Contains("Japanese", viewModel.Draft.TargetLanguages);

        viewModel.RemoveLanguage("French");
        viewModel.RemoveTargetLanguage("Japanese");

        Assert.DoesNotContain("French", viewModel.Draft.Languages);
        Assert.DoesNotContain("Japanese", viewModel.Draft.TargetLanguages);
    }

    [Fact]
    public async Task RefreshUsesLatestRuntimeSnapshotForDraftAndRevert()
    {
        var runtime = AppConfig.Default with { Model = "saved", StartWithWindows = true };
        var key = "saved-key";
        var viewModel = new SettingsViewModel(
            AppConfig.Default,
            "startup-key",
            (request, _) => { runtime = request.Config; key = request.ApiKey; return Task.CompletedTask; },
            () => { },
            refresh: _ => Task.FromResult((runtime, key)));

        await viewModel.RefreshAsync(CancellationToken.None);
        Assert.Equal("saved", viewModel.Draft.Model);
        Assert.True(viewModel.Draft.StartWithWindows);
        Assert.Equal("saved-key", viewModel.Draft.ApiKey);

        viewModel.Draft.Model = "discard";
        viewModel.Draft.StartWithWindows = false;
        viewModel.Draft.ApiKey = "discard-key";
        viewModel.Revert();

        Assert.Equal("saved", viewModel.Draft.Model);
        Assert.True(viewModel.Draft.StartWithWindows);
        Assert.Equal("saved-key", viewModel.Draft.ApiKey);
    }

    [Fact]
    public async Task SaveCloseReopenAndExternalToggleRefreshLatestSnapshot()
    {
        var runtime = AppConfig.Default;
        var key = "old-key";
        var viewModel = new SettingsViewModel(
            runtime,
            key,
            (request, _) => { runtime = request.Config; key = request.ApiKey; return Task.CompletedTask; },
            () => { },
            refresh: _ => Task.FromResult((runtime, key)));
        viewModel.Draft.Model = "saved-model";
        viewModel.Draft.ApiKey = "new-key";

        await viewModel.SaveAsync(CancellationToken.None);
        runtime = runtime with { StartWithWindows = true };
        await viewModel.RefreshAsync(CancellationToken.None);

        Assert.Equal("saved-model", viewModel.Draft.Model);
        Assert.Equal("new-key", viewModel.Draft.ApiKey);
        Assert.True(viewModel.Draft.StartWithWindows);
    }

    private static SettingsViewModel CreateViewModel() =>
        new(AppConfig.Default, "key", (_, _) => Task.CompletedTask, () => { });

    private static Task RunOnSingleThreadContext(Func<SingleThreadContext, Task> action)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            var context = new SingleThreadContext();
            SynchronizationContext.SetSynchronizationContext(context);
            action(context).ContinueWith(task =>
            {
                if (task.Exception is null) completion.TrySetResult();
                else completion.TrySetException(task.Exception.InnerExceptions);
                context.Complete();
            }, TaskScheduler.Default);
            context.Run();
        });
        thread.Start();
        return completion.Task.WaitAsync(TimeSpan.FromSeconds(5));
    }

    private sealed class SingleThreadContext : SynchronizationContext
    {
        private readonly System.Collections.Concurrent.BlockingCollection<(SendOrPostCallback Callback, object? State)> _work = [];
        public int ThreadId { get; } = Environment.CurrentManagedThreadId;
        public override void Post(SendOrPostCallback callback, object? state) => _work.Add((callback, state));
        public void Complete() => _work.CompleteAdding();
        public void Run()
        {
            foreach (var work in _work.GetConsumingEnumerable()) work.Callback(work.State);
        }
    }

    private sealed class AsyncPicker(string result) : ISettingsFolderPicker
    {
        public nint OwnerHwnd => 42;
        public async Task<string?> PickAsync(nint hwnd, CancellationToken token)
        {
            await Task.Run(() => { }, token);
            return result;
        }
    }

    private sealed class ThrowingPicker(Exception exception) : ISettingsFolderPicker
    {
        public nint OwnerHwnd => 42;
        public Task<string?> PickAsync(nint hwnd, CancellationToken token) => Task.FromException<string?>(exception);
    }

    private sealed class StubPicker(nint ownerHwnd, string? result, Action<nint> capture) : ISettingsFolderPicker
    {
        public nint OwnerHwnd => ownerHwnd;
        public Task<string?> PickAsync(nint hwnd, CancellationToken token)
        {
            capture(hwnd);
            return Task.FromResult(result);
        }
    }
}
