using NTranslate.Core.Configuration;

namespace NTranslate.App.Tests;

public sealed class JsonConfigStoreTests
{
    [Fact]
    public async Task Missing_file_loads_default_config()
    {
        var path = Path.Combine(Path.GetTempPath(), $"ntranslate-config-{Guid.NewGuid():N}", "config.json");

        var config = await new JsonConfigStore(path).LoadAsync();

        Assert.Equal(AppConfig.Default, config);
    }
}
