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
        Assert.Contains("KeyboardAccelerator Key=\"Enter\" Invoked=\"HistoryEnter_Invoked\"", text, StringComparison.Ordinal);
        Assert.Contains("DoubleTapped=\"History_DoubleTapped\"", text, StringComparison.Ordinal);
        Assert.DoesNotContain("ItemClick=", text, StringComparison.Ordinal);
        Assert.Contains("Play source audio", text, StringComparison.Ordinal);
        Assert.Contains("Play result audio", text, StringComparison.Ordinal);
        Assert.Contains("ToggleButton", text, StringComparison.Ordinal);
        Assert.Contains("IsChecked=\"{Binding IsSaved, Mode=OneWay}\"", text, StringComparison.Ordinal);
        Assert.Contains("AutomationProperties.Name=\"Saved translation\"", text, StringComparison.Ordinal);
        Assert.Contains("Delete translation", text, StringComparison.Ordinal);
        Assert.Contains("Text=\"{Binding Timestamp}\"", text, StringComparison.Ordinal);
        Assert.Contains("Message=\"{Binding ErrorMessage}\"", text, StringComparison.Ordinal);
        Assert.Contains("IsOpen=\"{Binding HasError}\"", text, StringComparison.Ordinal);
        Assert.Equal(3, Count(text, "CanMutate"));
    }

    private static int Count(string text, string value) => text.Split(value, StringSplitOptions.None).Length - 1;

    [Fact]
    public void WindowCodeBehindKeepsSingletonAliveAcrossUserClose()
    {
        var path = Path.Combine(FindRepositoryRoot(), "windows", "src", "NTranslate.App", "History", "HistoryWindow.xaml.cs");
        var text = File.ReadAllText(path);

        Assert.Contains("_appWindow.Closing += AppWindow_Closing", text, StringComparison.Ordinal);
        Assert.Contains("args.Cancel = true", text, StringComparison.Ordinal);
        Assert.Contains("_appWindow.Hide()", text, StringComparison.Ordinal);
        Assert.Contains("CloseForShutdown", text, StringComparison.Ordinal);
        Assert.Contains("PrepareToShow", text, StringComparison.Ordinal);
        Assert.Contains("_lifetime = new()", text, StringComparison.Ordinal);
        Assert.Equal(2, Count(text, "_lifetime.Cancel()"));
    }

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null && !Directory.Exists(Path.Combine(directory.FullName, "windows", "src")))
            directory = directory.Parent;
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }
}
