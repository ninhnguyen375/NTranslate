using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace NTranslate.Core.Updates;

public sealed class UpdateClientException(string message, Exception? innerException = null) : Exception(message, innerException);

public sealed class GitHubReleaseClient
{
    private static readonly HashSet<string> AllowedDownloadHosts = new(StringComparer.OrdinalIgnoreCase)
    {
        "github.com",
        "objects.githubusercontent.com"
    };

    private readonly HttpClient _httpClient;
    private readonly Uri _releasesUri;

    public GitHubReleaseClient(HttpClient httpClient, string owner, string repository)
    {
        ArgumentNullException.ThrowIfNull(httpClient);
        if (!IsSafeSegment(owner) || !IsSafeSegment(repository))
            throw new ArgumentException("GitHub owner and repository must contain only letters, digits, hyphens, underscores, or periods.");
        _httpClient = httpClient;
        _releasesUri = new($"https://api.github.com/repos/{owner}/{repository}/releases");
    }

    public async Task<IReadOnlyList<GitHubRelease>> GetReleasesAsync(CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, _releasesUri);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        request.Headers.UserAgent.ParseAdd("NTranslate-Windows-Updater");
        request.Headers.Add("X-GitHub-Api-Version", "2022-11-28");
        using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
        EnsureSuccess(response);

        try
        {
            if (response.Content.Headers.ContentLength == 0)
                throw new UpdateClientException("GitHub returned an empty response.");
            await using var stream = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
            var payload = await JsonSerializer.DeserializeAsync<List<ReleaseDto>>(stream, cancellationToken: token).ConfigureAwait(false);
            if (payload is null)
                throw new UpdateClientException("GitHub returned an empty response.");

            return payload.Select(MapRelease).ToArray();
        }
        catch (UpdateClientException) { throw; }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception) when (exception is JsonException or InvalidOperationException)
        {
            throw new UpdateClientException("GitHub returned an invalid release response.", exception);
        }
    }

    public async Task DownloadAsync(Uri downloadUrl, string destinationPath, CancellationToken token)
    {
        ValidateDownloadUrl(downloadUrl);
        ArgumentException.ThrowIfNullOrWhiteSpace(destinationPath);
        var fullDestination = Path.GetFullPath(destinationPath);
        var directory = Path.GetDirectoryName(fullDestination) ?? throw new ArgumentException("Destination must include a directory.", nameof(destinationPath));
        Directory.CreateDirectory(directory);
        var partialPath = fullDestination + ".partial";

        try
        {
            File.Delete(partialPath);
            using var request = new HttpRequestMessage(HttpMethod.Get, downloadUrl);
            request.Headers.UserAgent.ParseAdd("NTranslate-Windows-Updater");
            using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
            EnsureSuccess(response);
            await using (var source = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false))
            await using (var destination = new FileStream(partialPath, FileMode.CreateNew, FileAccess.Write, FileShare.None, 81920, FileOptions.Asynchronous | FileOptions.WriteThrough))
            {
                await source.CopyToAsync(destination, token).ConfigureAwait(false);
                await destination.FlushAsync(token).ConfigureAwait(false);
            }
            File.Move(partialPath, fullDestination, true);
        }
        catch
        {
            File.Delete(partialPath);
            throw;
        }
    }

    private static GitHubRelease MapRelease(ReleaseDto release)
    {
        if (release.Tag is null || release.Notes is null || release.Assets is null)
            throw new UpdateClientException("GitHub returned an invalid release response.");

        var assets = release.Assets.Select(asset =>
        {
            if (asset.Name is null || !Uri.TryCreate(asset.DownloadUrl, UriKind.Absolute, out var uri))
                throw new UpdateClientException("GitHub returned an invalid release response.");
            ValidateDownloadUrl(uri);
            return new GitHubAsset(asset.Name, uri);
        }).ToArray();
        return new(release.Tag, release.Notes, release.Draft, release.Prerelease, assets);
    }

    private static void ValidateDownloadUrl(Uri uri)
    {
        if (!uri.IsAbsoluteUri || !string.Equals(uri.Scheme, Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) ||
            !AllowedDownloadHosts.Contains(uri.IdnHost) || !string.IsNullOrEmpty(uri.UserInfo) || !uri.IsDefaultPort)
            throw new UpdateClientException("GitHub returned an unsafe download URL.");
    }

    private static void EnsureSuccess(HttpResponseMessage response)
    {
        if (!response.IsSuccessStatusCode)
            throw new UpdateClientException($"GitHub request failed with HTTP {(int)response.StatusCode}.");
    }

    private static bool IsSafeSegment(string value) =>
        !string.IsNullOrWhiteSpace(value) && value.All(character => char.IsAsciiLetterOrDigit(character) || character is '-' or '_' or '.');

    private sealed record ReleaseDto(
        [property: JsonPropertyName("tag_name")] string? Tag,
        [property: JsonPropertyName("body")] string? Notes,
        [property: JsonPropertyName("draft")] bool Draft,
        [property: JsonPropertyName("prerelease")] bool Prerelease,
        [property: JsonPropertyName("assets")] List<AssetDto>? Assets);

    private sealed record AssetDto(
        [property: JsonPropertyName("name")] string? Name,
        [property: JsonPropertyName("browser_download_url")] string? DownloadUrl);
}
