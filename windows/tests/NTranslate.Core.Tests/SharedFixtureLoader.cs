using System.Text.Json;

namespace NTranslate.Core.Tests;

internal static class SharedFixtureLoader
{
    internal static JsonDocument Load(string name)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var path = Path.Combine(directory.FullName, "shared", "contracts", name);
            var gitPath = Path.Combine(directory.FullName, ".git");
            if ((Directory.Exists(gitPath) || File.Exists(gitPath)) && File.Exists(path))
                return JsonDocument.Parse(File.ReadAllText(path));
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException($"Repository root not found for fixture {name}.");
    }
}
