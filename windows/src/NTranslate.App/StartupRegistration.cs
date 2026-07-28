using Microsoft.Win32;

namespace NTranslate.App;

internal interface IStartupRegistration
{
    Task SetEnabledAsync(bool enabled, CancellationToken token);
}

internal sealed class StartupRegistration : IStartupRegistration
{
    private const string KeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "NTranslate";

    public Task SetEnabledAsync(bool enabled, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath, writable: true) ?? throw new InvalidOperationException("Cannot open Windows startup registry key.");
        if (enabled)
            key.SetValue(ValueName, $"\"{Environment.ProcessPath ?? throw new InvalidOperationException("Application path is unavailable.")}\"");
        else
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        return Task.CompletedTask;
    }
}
