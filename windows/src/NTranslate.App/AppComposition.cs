using System.Text.Json;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using NTranslate.App.Popup;
using NTranslate.Core.Configuration;
using NTranslate.Core.OpenAI;
using NTranslate.Platform.Capture;
using NTranslate.Platform.Clipboard;
using NTranslate.Platform.Credentials;
using NTranslate.Platform.Input;
using NTranslate.Platform.Windows;

namespace NTranslate.App;

internal sealed class AppComposition : IDisposable
{
    private readonly DispatcherQueue _dispatcher;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly OleClipboardService _clipboard;
    private readonly SelectionCaptureService _capture;
    private readonly GlobalHotkey _hotkey;
    private readonly TrayIcon _tray;
    private readonly TranslationViewModel _viewModel;
    private readonly TranslationWindow _window;
    private readonly AppShutdown _shutdown;
    private readonly AppConfig _config;
    private CancellationTokenSource? _captureRequest;
    private int _captureGeneration;

    public AppComposition(DispatcherQueue dispatcher)
    {
        _dispatcher = dispatcher;
        _config = LoadConfig();
        _clipboard = new OleClipboardService();
        _capture = new SelectionCaptureService(new UiAutomationSelectionReader(), _clipboard, new SendInputCopyCommand());
        _hotkey = new GlobalHotkey();
        _tray = new TrayIcon();
        var credentials = new CredentialLockerApiKeyStore();
        _viewModel = new TranslationViewModel(_config, new OpenAiCompatibleClient(new HttpClient()), _clipboard,
            async token => await credentials.LoadAsync(token).ConfigureAwait(false) ?? throw new InvalidOperationException("API key missing. Store key in Windows Credential Locker before translating."));
        _window = new TranslationWindow(_viewModel, _config.Ui.Width, _config.Ui.Height);
        _shutdown = new AppShutdown(
            () => { _lifetime.Cancel(); _captureRequest?.Cancel(); _viewModel.Cancel(); },
            _hotkey.Dispose,
            _tray.Dispose,
            _window.RestoreWindowProcedure,
            _window.Close);

        _hotkey.Pressed += (_, _) => _ = CaptureAndShowAsync();
        _tray.OpenTranslatorRequested += (_, _) => Enqueue(() => Show(null));
        _tray.ExitRequested += (_, _) => Enqueue(_shutdown.Run);
    }

    public string? HotkeyRegistrationError { get; private set; }

    public void Start()
    {
        _tray.Show();
        var registration = _hotkey.Register(_config.Hotkey);
        HotkeyRegistrationError = registration.Error; // tray/manual entry remain usable on collision.
    }

    public void ShowManual() => Enqueue(() => Show(null));

    public void Dispose() => _shutdown.Run();

    private async Task CaptureAndShowAsync()
    {
        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        var previous = Interlocked.Exchange(ref _captureRequest, cancellation);
        previous?.Cancel();
        previous?.Dispose();
        var generation = Interlocked.Increment(ref _captureGeneration);
        SelectionCapture? capture = null;
        try { capture = await _capture.CaptureAsync(_config.Ui.SimulateCopy, cancellation.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { return; }
        catch { }
        if (generation == Volatile.Read(ref _captureGeneration))
            Enqueue(() => Show(capture?.Text));
    }

    private void Show(string? text)
    {
        if (text is null)
            _viewModel.SourceText = string.Empty;
        _window.ShowPopup(text);
    }

    private void Enqueue(Action action) => _dispatcher.TryEnqueue(() =>
    {
        if (!_lifetime.IsCancellationRequested)
            action();
    });

    private static AppConfig LoadConfig()
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NTranslate", "config.json");
        if (!File.Exists(path))
            return AppConfig.Default;
        try
        {
            var parsed = ConfigJson.Parse(File.ReadAllText(path));
            if (parsed.LegacyApiKey is not null)
                throw new InvalidOperationException("Remove apiKey from config.json and store it in Windows Credential Locker.");
            if (parsed.Config.Validate().Count > 0)
                throw new InvalidOperationException("config.json is invalid; fix reported fields or remove file to restore defaults.");
            return parsed.Config;
        }
        catch (JsonException exception)
        {
            throw new InvalidOperationException($"config.json is malformed: {path}", exception);
        }
    }
}
