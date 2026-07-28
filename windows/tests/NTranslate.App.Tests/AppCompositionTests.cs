namespace NTranslate.App.Tests;

public sealed class AppCompositionTests
{
    [Fact]
    public void CompositionRegistersIntegratedRuntimeSurfaces()
    {
        var root = FindRepositoryRoot();
        var composition = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "AppComposition.cs"));
        var project = File.ReadAllText(Path.Combine(root, "windows", "src", "NTranslate.App", "NTranslate.App.csproj"));

        foreach (var required in new[]
        {
            "JsonTranslationHistoryStore", "AcceptedTranslationSink", "SettingsSaveCoordinator",
            "HistoryDirectoryMigrator", "CrashLogService", "RecoveryCoordinator", "HistoryWindow",
            "SettingsWindow", "WindowsImageNormalizer", "WindowsBrowserLauncher", "WindowsSpeechPlayer",
            "SpeechCoordinator", "GitHubReleaseClient", "UpdateCoordinator", "CheckForUpdatesRequested"
        })
            Assert.Contains(required, composition, StringComparison.Ordinal);
        Assert.Contains("History\\HistoryWindow.xaml", project, StringComparison.Ordinal);
        Assert.Contains("Settings\\SettingsWindow.xaml", project, StringComparison.Ordinal);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !Directory.Exists(Path.Combine(directory.FullName, "windows", "src")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }
}
