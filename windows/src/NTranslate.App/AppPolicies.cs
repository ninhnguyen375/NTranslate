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

internal static class EventBoundary
{
    public static async Task IgnoreCancellation(Func<Task> operation)
    {
        try { await operation().ConfigureAwait(true); }
        catch (OperationCanceledException) { }
    }
}

internal static class GuidancePolicy
{
    public static string? Combine(string? config, string? hotkeyError)
    {
        var hotkey = hotkeyError is null ? null : "Global hotkey unavailable.";
        return string.Join(' ', new[] { config, hotkey }.Where(value => value is not null));
    }
}

internal enum PopupCaptureKind
{
    Empty,
    Text,
    Image
}

internal sealed record PopupCapture(PopupCaptureKind Kind, string? Text, byte[]? ImagePng, string? Diagnostic);

internal enum PopupRequestAction
{
    ShowManual,
    ShowAndTranslateText,
    ShowAndTranslateImage
}

internal static class PopupRequestPolicy
{
    public static PopupRequestAction Resolve(PopupCapture capture) => capture.Kind switch
    {
        PopupCaptureKind.Text => PopupRequestAction.ShowAndTranslateText,
        PopupCaptureKind.Image => PopupRequestAction.ShowAndTranslateImage,
        _ => PopupRequestAction.ShowManual
    };
}

internal static class CaptureRouting
{
    public static PopupCapture Resolve(NTranslate.Platform.Capture.SelectionCapture? capture)
    {
        if (!string.IsNullOrWhiteSpace(capture?.Text))
            return new(PopupCaptureKind.Text, capture.Text, null, capture.Diagnostic);
        return capture?.ImagePng is not null
            ? new(PopupCaptureKind.Image, null, capture.ImagePng, capture.Diagnostic)
            : new(PopupCaptureKind.Empty, null, null, capture?.Diagnostic);
    }

    public static string? SourceText(NTranslate.Platform.Capture.SelectionCapture? capture) =>
        string.IsNullOrWhiteSpace(capture?.Text) ? null : capture.Text;
}

internal sealed class PopupRequestDispatcher(
    Action invalidate,
    Action<Action> enqueue,
    Action showManual,
    Func<string, CancellationToken, Task> showAndTranslateText,
    Func<byte[], CancellationToken, Task> showAndTranslateImage)
{
    public void Invalidate() => invalidate();

    public void Enqueue(PopupCapture capture, Func<bool> isCurrent, CancellationToken cancellationToken) => enqueue(() =>
    {
        if (!isCurrent()) return;
        _ = PopupRequestPolicy.Resolve(capture) switch
        {
            PopupRequestAction.ShowAndTranslateText => showAndTranslateText(capture.Text!, cancellationToken),
            PopupRequestAction.ShowAndTranslateImage => showAndTranslateImage(capture.ImagePng!, cancellationToken),
            _ => ShowManual()
        };
    });

    private Task ShowManual()
    {
        showManual();
        return Task.CompletedTask;
    }
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
