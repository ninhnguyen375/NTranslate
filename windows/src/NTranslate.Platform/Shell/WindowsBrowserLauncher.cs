using System.Diagnostics;

namespace NTranslate.Platform.Shell;

public sealed class WindowsBrowserLauncher : IBrowserLauncher
{
    private readonly Func<ProcessStartInfo, Process?> start;

    public WindowsBrowserLauncher() : this(Process.Start) { }

    internal WindowsBrowserLauncher(Func<ProcessStartInfo, Process?> start) =>
        this.start = start ?? throw new ArgumentNullException(nameof(start));

    public Task OpenAsync(Uri uri, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(uri);
        cancellationToken.ThrowIfCancellationRequested();
        if (!uri.IsAbsoluteUri || uri.Scheme != Uri.UriSchemeHttps ||
            !string.Equals(uri.Host, "www.google.com", StringComparison.OrdinalIgnoreCase))
            throw new ArgumentException("Browser URI must use HTTPS on www.google.com.", nameof(uri));

        start(new ProcessStartInfo(uri.AbsoluteUri) { UseShellExecute = true });
        return Task.CompletedTask;
    }
}
