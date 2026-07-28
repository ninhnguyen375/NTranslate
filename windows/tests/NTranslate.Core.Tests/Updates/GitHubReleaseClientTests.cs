using System.Net;
using System.Text;
using NTranslate.Core.Updates;

namespace NTranslate.Core.Tests.Updates;

public sealed class GitHubReleaseClientTests
{
    [Fact]
    public async Task FetchesExactApiUrlHeadersAndParsesRelease()
    {
        var handler = new StubHandler((request, _) =>
        {
            Assert.Equal("https://api.github.com/repos/ninhnguyen375/NTranslate/releases", request.RequestUri!.AbsoluteUri);
            Assert.Equal("application/vnd.github+json", request.Headers.Accept.Single().MediaType);
            Assert.Equal("NTranslate-Windows-Updater", request.Headers.UserAgent.ToString());
            Assert.Equal("2022-11-28", request.Headers.GetValues("X-GitHub-Api-Version").Single());
            return Response(HttpStatusCode.OK, """
                [{"tag_name":"v1.2.3","body":"notes","draft":false,"prerelease":false,
                  "assets":[{"name":"NTranslate-1.2.3-win-x64.msix","browser_download_url":"https://github.com/ninhnguyen375/NTranslate/releases/download/v1.2.3/NTranslate-1.2.3-win-x64.msix"}]}]
                """);
        });

        var releases = await Client(handler).GetReleasesAsync(CancellationToken.None);

        var release = Assert.Single(releases);
        Assert.Equal("v1.2.3", release.Tag);
        Assert.Equal("notes", release.Notes);
        Assert.Equal("NTranslate-1.2.3-win-x64.msix", Assert.Single(release.Assets).Name);
    }

    [Theory]
    [InlineData("")]
    [InlineData("null")]
    public async Task RejectsMissingResponseBody(string body)
    {
        var error = await Assert.ThrowsAsync<UpdateClientException>(() => Client(new StubHandler((_, _) => Response(HttpStatusCode.OK, body))).GetReleasesAsync(CancellationToken.None));
        Assert.Equal("GitHub returned an empty response.", error.Message);
    }

    [Fact]
    public async Task SanitizesNonSuccessErrors()
    {
        var error = await Assert.ThrowsAsync<UpdateClientException>(() => Client(new StubHandler((_, _) => Response(HttpStatusCode.InternalServerError, "secret token"))).GetReleasesAsync(CancellationToken.None));
        Assert.Equal("GitHub request failed with HTTP 500.", error.Message);
        Assert.DoesNotContain("secret", error.ToString(), StringComparison.OrdinalIgnoreCase);
    }

    [Theory]
    [InlineData("not-json")]
    [InlineData("[{}]")]
    [InlineData("[{\"tag_name\":\"v1.2.3\",\"body\":\"\",\"draft\":false,\"prerelease\":false,\"assets\":null}]")]
    [InlineData("[{\"tag_name\":\"v1.2.3\",\"body\":\"\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"name\":\"x\",\"browser_download_url\":\"not-url\"}]}]")]
    [InlineData("[{\"tag_name\":\"v1.2.3\",\"body\":\"\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"name\":\"x\",\"browser_download_url\":\"http://github.com/x\"}]}]")]
    [InlineData("[{\"tag_name\":\"v1.2.3\",\"body\":\"\",\"draft\":false,\"prerelease\":false,\"assets\":[{\"name\":\"x\",\"browser_download_url\":\"https://evil.example/x\"}]}]")]
    public async Task RejectsInvalidJsonUrlsAndHosts(string body) =>
        await Assert.ThrowsAsync<UpdateClientException>(() => Client(new StubHandler((_, _) => Response(HttpStatusCode.OK, body))).GetReleasesAsync(CancellationToken.None));

    [Fact]
    public async Task DownloadsThroughPartialThenAtomicallyReplacesDestination()
    {
        using var directory = new TemporaryDirectory();
        var destination = Path.Combine(directory.Path, "update.msix");
        await File.WriteAllTextAsync(destination, "old");
        var handler = new StubHandler((request, _) =>
        {
            Assert.Equal("https://objects.githubusercontent.com/update.msix", request.RequestUri!.AbsoluteUri);
            return Response(HttpStatusCode.OK, "new package");
        });

        await Client(handler).DownloadAsync(new Uri("https://objects.githubusercontent.com/update.msix"), destination, CancellationToken.None);

        Assert.Equal("new package", await File.ReadAllTextAsync(destination));
        Assert.False(File.Exists(destination + ".partial"));
    }

    [Fact]
    public async Task CancellationRemovesPartialAndPreservesExistingDestination()
    {
        using var directory = new TemporaryDirectory();
        var destination = Path.Combine(directory.Path, "update.msix");
        await File.WriteAllTextAsync(destination, "installed");
        var handler = new StubHandler((_, token) => Task.FromCanceled<HttpResponseMessage>(token));
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => Client(handler).DownloadAsync(new Uri("https://github.com/update.msix"), destination, cancellation.Token));

        Assert.Equal("installed", await File.ReadAllTextAsync(destination));
        Assert.False(File.Exists(destination + ".partial"));
    }

    [Fact]
    public async Task FailedDownloadRemovesPartialAndPreservesExistingDestination()
    {
        using var directory = new TemporaryDirectory();
        var destination = Path.Combine(directory.Path, "update.msix");
        await File.WriteAllTextAsync(destination, "installed");

        await Assert.ThrowsAsync<UpdateClientException>(() => Client(new StubHandler((_, _) => Response(HttpStatusCode.BadGateway, "private"))).DownloadAsync(new Uri("https://github.com/update.msix"), destination, CancellationToken.None));

        Assert.Equal("installed", await File.ReadAllTextAsync(destination));
        Assert.False(File.Exists(destination + ".partial"));
    }

    private static GitHubReleaseClient Client(HttpMessageHandler handler) => new(new HttpClient(handler), "ninhnguyen375", "NTranslate");

    private static HttpResponseMessage Response(HttpStatusCode status, string body) => new(status)
    {
        Content = new StringContent(body, Encoding.UTF8, "application/json")
    };

    private sealed class StubHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> response) : HttpMessageHandler
    {
        public StubHandler(Func<HttpRequestMessage, CancellationToken, HttpResponseMessage> response)
            : this((request, token) => Task.FromResult(response(request, token))) { }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => response(request, cancellationToken);
    }

    private sealed class TemporaryDirectory : IDisposable
    {
        public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"NTranslate-{Guid.NewGuid():N}");
        public TemporaryDirectory() => Directory.CreateDirectory(Path);
        public void Dispose() => Directory.Delete(Path, true);
    }
}
