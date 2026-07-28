using NTranslate.App.Settings;
using NTranslate.Core.Configuration;

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
