using System.Text.Json;
using NTranslate.Core.Configuration;

namespace NTranslate.App;

internal sealed class CaptureGeneration
{
    private int _generation;
    public int Begin() => Interlocked.Increment(ref _generation);
    public void Cancel() => Interlocked.Increment(ref _generation);
    public bool IsCurrent(int generation) => Volatile.Read(ref _generation) == generation;
}

internal static class GuidancePolicy
{
    public static string? Combine(string? config, string? hotkeyError)
    {
        var hotkey = hotkeyError is null ? null : "Global hotkey unavailable.";
        return string.Join(' ', new[] { config, hotkey }.Where(value => value is not null));
    }
}

internal static class CaptureRouting
{
    public static string? SourceText(NTranslate.Platform.Capture.SelectionCapture? capture) => capture?.Source switch
    {
        NTranslate.Platform.Capture.SelectionSource.UiAutomation or
        NTranslate.Platform.Capture.SelectionSource.SimulatedCopy => capture.Text,
        _ => null,
    };
}

internal sealed class PopupRouter(Action cancelCapture, Action showManual)
{
    public void ShowManual()
    {
        cancelCapture();
        showManual();
    }
}

internal sealed class ActivationGate(Action show)
{
    private readonly object _gate = new();
    private int _pending;
    private bool _ready;

    public void Activate()
    {
        lock (_gate)
        {
            if (!_ready) { _pending++; return; }
        }
        show();
    }

    public void Ready()
    {
        int pending;
        lock (_gate)
        {
            if (_ready) return;
            _ready = true;
            pending = _pending;
            _pending = 0;
        }
        for (var i = 0; i < pending; i++) show();
    }
}

internal sealed record ConfigStartupResult(AppConfig Config, string? Guidance);

internal static class ConfigStartupPolicy
{
    public static ConfigStartupResult Resolve(string? json, string path)
    {
        if (json is null)
            return new(AppConfig.Default, $"Configuration could not be read. Using defaults. File: {path}");
        try
        {
            var parsed = ConfigJson.Parse(json);
            if (parsed.LegacyApiKey is not null)
                return new(AppConfig.Default, "Configuration contains an API key. Remove it and store key in Windows Credential Locker. Using defaults.");
            return parsed.Config.Validate().Count == 0
                ? new(parsed.Config, null)
                : new(AppConfig.Default, $"Configuration is invalid. Using defaults. File: {path}");
        }
        catch (JsonException)
        {
            return new(AppConfig.Default, $"Configuration is malformed. Using defaults. File: {path}");
        }
    }
}
