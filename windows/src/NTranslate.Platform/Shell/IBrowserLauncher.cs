namespace NTranslate.Platform.Shell;

public interface IBrowserLauncher
{
    Task OpenAsync(Uri uri, CancellationToken cancellationToken);
}
