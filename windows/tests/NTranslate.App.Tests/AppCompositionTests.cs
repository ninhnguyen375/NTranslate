namespace NTranslate.App.Tests;

public sealed class AppCompositionTests
{
    [Fact]
    public void CompositionRegistersIntegratedRuntimeSurfaces()
    {
        var root = FindRepositoryRoot();
        var composition = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "AppComposition.cs"))
            + File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "IntegrationAdapters.cs"));
        var project = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "NTranslate.App.csproj"));

        foreach (var required in new[]
        {
            "JsonTranslationHistoryStore", "AcceptedTranslationSink", "SettingsSaveCoordinator",
            "HistoryDirectoryMigrator", "CrashLogService", "RecoveryCoordinator", "HistoryWindow",
            "SettingsWindow", "WindowsImageNormalizer", "WindowsBrowserLauncher", "WindowsSpeechPlayer",
            "SpeechCoordinator", "GitHubReleaseClient", "UpdateCoordinator", "CheckForUpdatesRequested",
            "CrashHandlerRegistration", "WinUiUnhandledExceptionSource", "AppDomainUnhandledExceptionSource",
            "TaskSchedulerUnobservedExceptionSource", "StartupRegistration", "ToggleStartWithWindowsAsync",
            "ApplyRuntimeAsync"
        })
            Assert.Contains(required, composition, StringComparison.Ordinal);
        Assert.Contains("History\\HistoryWindow.xaml", project, StringComparison.Ordinal);
        Assert.Contains("Settings\\SettingsWindow.xaml", project, StringComparison.Ordinal);
    }

    [Fact]
    public void CompositionSwitchesRootServicesAndUsesOwnedExplicitDeleteDialog()
    {
        var root = FindRepositoryRoot();
        var composition = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "AppComposition.cs"));
        var adapters = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "IntegrationAdapters.cs"));

        Assert.Contains("HistoryRuntime", composition, StringComparison.Ordinal);
        Assert.Contains("SwitchHistoryRuntime", composition, StringComparison.Ordinal);
        Assert.Contains("ShowHistoryRecord", composition, StringComparison.Ordinal);
        Assert.Contains("HistoryDeleteConfirmation", composition, StringComparison.Ordinal);
        Assert.Contains("ContentDialogResult.Primary", adapters, StringComparison.Ordinal);
        Assert.Contains("XamlRoot = root", adapters, StringComparison.Ordinal);
        Assert.Contains("records.Count", adapters, StringComparison.Ordinal);
    }

    [Fact]
    public void CompositionPersistsModeAndUsesHistorySpecificPopupPath()
    {
        var root = FindRepositoryRoot();
        var composition = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "AppComposition.cs"));
        var window = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "Popup", "TranslationWindow.xaml.cs"));

        Assert.Contains("accepted.TargetLanguage, null, null, false, entry.Mode)", composition, StringComparison.Ordinal);
        Assert.Contains("_window.ShowHistoryRecord(record)", composition, StringComparison.Ordinal);
        Assert.Contains("internal void ShowHistoryRecord(TranslationRecord record)", window, StringComparison.Ordinal);
        Assert.Contains("ImagePreview.Source = null", window, StringComparison.Ordinal);
    }

    [Fact]
    public void WindowsExposeBoundActionsAndAccessibleKeyboardRoutes()
    {
        var root = FindRepositoryRoot();
        var history = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "History", "HistoryWindow.xaml"));
        var settings = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "Settings", "SettingsWindow.xaml"));
        var historyCode = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "History", "HistoryWindow.xaml.cs"));
        var settingsCode = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "Settings", "SettingsWindow.xaml.cs"));

        foreach (var value in new[] { "ItemsSource=\"{Binding VisibleRecords}\"", "Text=\"{Binding Query, Mode=TwoWay", "DoubleTapped=\"History_DoubleTapped\"", "HistoryEnter_Invoked", "DeleteVisible_Click", "ToggleSaved_Click", "PlaySource_Click", "PlayResult_Click", "Delete_Click" })
            Assert.Contains(value, history + historyCode, StringComparison.Ordinal);
        foreach (var value in new[] { "PasswordChanged=\"ApiKeyBox_PasswordChanged\"", "Save_Click", "Cancel_Click", "Revert_Click", "Browse_Click", "KeyboardAccelerator Key=\"S\" Modifiers=\"Control\"", "RefreshAsync", "ShowSettingsAsync" })
            Assert.Contains(value, settings + settingsCode + File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "AppComposition.cs")), StringComparison.Ordinal);
    }

    [Fact]
    public void ReopeningSettingsRenewsWindowLifetimeBeforeRefresh()
    {
        var root = FindRepositoryRoot();
        var composition = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "AppComposition.cs"));
        var prepare = composition.IndexOf("_settingsWindow.PrepareToShow();", StringComparison.Ordinal);
        var refresh = composition.IndexOf("await _settingsViewModel.RefreshAsync(_lifetime.Token);", StringComparison.Ordinal);

        Assert.True(prepare >= 0 && prepare < refresh);
    }

    [Fact]
    public void TranslationWindowHasSingleTrayInitializer()
    {
        var root = FindRepositoryRoot();
        var window = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "Popup", "TranslationWindow.xaml.cs"));

        Assert.Equal(1, window.Split("internal void InitializeForTray()", StringSplitOptions.None).Length - 1);
    }

    [Fact]
    public void CompositionUsesChecksumVerifiedPerUserInstaller()
    {
        var root = FindRepositoryRoot();
        var composition = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "AppComposition.cs"));

        Assert.Contains("InstallerChecksumVerifier", composition, StringComparison.Ordinal);
        Assert.Contains("_shutdown.Run", composition, StringComparison.Ordinal);
        Assert.DoesNotContain("MsixPackageVerifier", composition, StringComparison.Ordinal);
    }

    [Fact]
    public void SettingsWindowInitializesAndSynchronizesApiKeyBox()
    {
        var root = FindRepositoryRoot();
        var window = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "Settings", "SettingsWindow.xaml.cs"));

        Assert.Contains("SyncApiKeyBox();", window, StringComparison.Ordinal);
        Assert.Contains("private void SyncApiKeyBox() => ApiKeyBox.Password = _viewModel.Draft.ApiKey;", window, StringComparison.Ordinal);
        Assert.Equal(2, window.Split("SyncApiKeyBox();", StringSplitOptions.None).Length - 1);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !Directory.Exists(Path.Combine(directory.FullName, "windows", "src")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }
}
