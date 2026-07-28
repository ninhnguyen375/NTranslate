using System.Xml.Linq;

namespace NTranslate.App.Tests.History;

public sealed class HistoryWindowXamlTests
{
    [Fact]
    public void WindowExposesSearchFiltersActionsAndAccessibleNames()
    {
        var path = Path.Combine(FindRepositoryRoot(), "windows", "src", "NTranslate.App", "History", "HistoryWindow.xaml");
        var text = File.ReadAllText(path);
        _ = XDocument.Parse(text);

        Assert.Contains("Search history", text, StringComparison.Ordinal);
        Assert.Contains("All history", text, StringComparison.Ordinal);
        Assert.Contains("Saved", text, StringComparison.Ordinal);
        Assert.Contains("Today", text, StringComparison.Ordinal);
        Assert.Contains("Last 24 hours", text, StringComparison.Ordinal);
        Assert.Contains("Week", text, StringComparison.Ordinal);
        Assert.Contains("Month", text, StringComparison.Ordinal);
        Assert.Contains("Delete visible", text, StringComparison.Ordinal);
        Assert.Contains("KeyboardAccelerator Key=\"Enter\"", text, StringComparison.Ordinal);
        Assert.Contains("Play source audio", text, StringComparison.Ordinal);
        Assert.Contains("Play result audio", text, StringComparison.Ordinal);
        Assert.Contains("Toggle saved", text, StringComparison.Ordinal);
        Assert.Contains("Delete translation", text, StringComparison.Ordinal);
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !Directory.Exists(Path.Combine(directory.FullName, "windows", "src")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }
}
