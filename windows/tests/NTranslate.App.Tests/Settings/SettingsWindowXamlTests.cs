using System.Xml.Linq;

namespace NTranslate.App.Tests.Settings;

public sealed class SettingsWindowXamlTests
{
    [Fact]
    public void WindowHasFluentTabsAllFieldsAndAccessibleActions()
    {
        var path = Path.Combine(FindRepositoryRoot(), "windows", "src", "NTranslate.App", "Settings", "SettingsWindow.xaml");
        var text = File.ReadAllText(path);
        _ = XDocument.Parse(text);

        Assert.Contains("NavigationView", text, StringComparison.Ordinal);
        foreach (var tab in new[] { "General", "Prompts", "Languages", "Advanced" })
            Assert.Contains($"Content=\"{tab}\"", text, StringComparison.Ordinal);
        foreach (var field in new[]
        {
            "API key", "API base URL", "Speech API URL", "Model", "System prompt", "Learn prompt",
            "Sentence learn prompt", "Grammar prompt", "Source language", "Target language", "Native language",
            "Languages", "Target languages", "Maximum translation length", "Speech source model",
            "Vietnamese speech source model", "Chinese speech source model", "Japanese speech source model", "Speech target model", "Speech rate",
            "History directory", "Hotkey", "Window width", "Window height", "Auto-copy", "Simulate copy",
            "Auto-prefetch speech", "Start with Windows"
        })
            Assert.Contains(field, text, StringComparison.Ordinal);
        foreach (var action in new[] { "Browse history directory", "Revert", "Cancel", "Save settings" })
            Assert.Contains($"AutomationProperties.Name=\"{action}\"", text, StringComparison.Ordinal);
        Assert.Contains("PasswordBox", text, StringComparison.Ordinal);
        Assert.Contains("SelectionChanged=\"Navigation_SelectionChanged\"", text, StringComparison.Ordinal);
        foreach (var section in new[] { "GeneralSection", "PromptsSection", "LanguagesSection", "AdvancedSection" })
            Assert.Contains($"x:Name=\"{section}\"", text, StringComparison.Ordinal);
        foreach (var action in new[] { "Add language", "Remove language", "Add target language", "Remove target language" })
            Assert.Contains($"AutomationProperties.Name=\"{action}\"", text, StringComparison.Ordinal);
        foreach (var modifier in new[] { "Option hotkey modifier", "Control hotkey modifier", "Shift hotkey modifier" })
            Assert.Contains($"AutomationProperties.Name=\"{modifier}\"", text, StringComparison.Ordinal);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !Directory.Exists(Path.Combine(directory.FullName, "windows", "src")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }
}
