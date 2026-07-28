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
        Assert.Contains("OpenHistoryRecord", composition, StringComparison.Ordinal);
        Assert.Contains("HistoryDeleteConfirmation", composition, StringComparison.Ordinal);
        Assert.Contains("ContentDialogResult.Primary", adapters, StringComparison.Ordinal);
        Assert.Contains("XamlRoot = root", adapters, StringComparison.Ordinal);
        Assert.Contains("records.Count", adapters, StringComparison.Ordinal);
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
        foreach (var value in new[] { "Password=\"{Binding Draft.ApiKey, Mode=TwoWay}", "Save_Click", "Cancel_Click", "Revert_Click", "Browse_Click", "KeyboardAccelerator Key=\"S\" Modifiers=\"Control\"", "RefreshAsync", "ShowSettingsAsync" })
            Assert.Contains(value, settings + settingsCode + File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "AppComposition.cs")), StringComparison.Ordinal);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !Directory.Exists(Path.Combine(directory.FullName, "windows", "src")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }
}
