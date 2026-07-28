using System.Diagnostics;
using NTranslate.Platform.Shell;

namespace NTranslate.Platform.Tests.Shell;

public sealed class WindowsBrowserLauncherTests
{
    [Theory]
    [InlineData("http://www.google.com/search?tbm=isch&q=cat")]
    [InlineData("https://evilgoogle.com/search?tbm=isch&q=cat")]
    [InlineData("https://example.com/search?tbm=isch&q=cat")]
    public async Task OpenAsync_rejects_non_https_or_non_google_uri(string value)
    {
        var launches = 0;
        var launcher = new WindowsBrowserLauncher(_ =>
        {
            launches++;
            return null;
        });

        await Assert.ThrowsAsync<ArgumentException>(() => launcher.OpenAsync(new Uri(value), CancellationToken.None));

        Assert.Equal(0, launches);
    }

    [Fact]
    public async Task OpenAsync_honors_pre_cancellation_before_launch()
    {
        var launches = 0;
        var launcher = new WindowsBrowserLauncher(_ =>
        {
            launches++;
            return null;
        });
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            launcher.OpenAsync(new Uri("https://www.google.com/search?tbm=isch&q=cat"), cancellation.Token));

        Assert.Equal(0, launches);
    }

    [Fact]
    public async Task OpenAsync_launches_valid_google_uri_through_shell()
    {
        ProcessStartInfo? captured = null;
        var launcher = new WindowsBrowserLauncher(startInfo =>
        {
            captured = startInfo;
            return null;
        });
        var uri = new Uri("https://www.google.com/search?tbm=isch&q=cat");

        await launcher.OpenAsync(uri, CancellationToken.None);

        Assert.NotNull(captured);
        Assert.Equal(uri.AbsoluteUri, captured.FileName);
        Assert.True(captured.UseShellExecute);
    }
}
