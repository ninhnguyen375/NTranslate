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
    private readonly PopupRouter _router;
    private CancellationTokenSource? _captureRequest;
    private int _captureGeneration;

    public AppComposition(DispatcherQueue dispatcher)
    {
        _dispatcher = dispatcher;
        var startup = LoadConfig();
        _config = startup.Config;
        _clipboard = new OleClipboardService();
        _capture = new SelectionCaptureService(new UiAutomationSelectionReader(), _clipboard, new SendInputCopyCommand());
        _hotkey = new GlobalHotkey();
        _tray = new TrayIcon();
        var credentials = new CredentialLockerApiKeyStore();
        _viewModel = new TranslationViewModel(_config, new OpenAiCompatibleClient(new HttpClient()), _clipboard,
            async token => await credentials.LoadAsync(token).ConfigureAwait(false) ?? throw new InvalidOperationException("API key missing. Store key in Windows Credential Locker before translating."),
            action =>
            {
                var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                if (!_dispatcher.TryEnqueue(() =>
                    {
                        try { action(); completion.SetResult(); }
                        catch (Exception error) { completion.SetException(error); }
                    }))
                    completion.SetException(new UiDispatchUnavailableException());
                return completion.Task;
            });
        _viewModel.SetStartupGuidance(startup.Guidance);
        _window = new TranslationWindow(_viewModel, _config.Ui.Width, _config.Ui.Height, CancelPopupWork);
        _router = new PopupRouter(CancelCapture, () => Show(null));
        _shutdown = new AppShutdown(
            () => { _lifetime.Cancel(); _captureRequest?.Cancel(); _viewModel.Cancel(); },
            _hotkey.Dispose,
            _tray.Dispose,
            _window.RestoreWindowProcedure,
            _window.CloseForShutdown);

        _hotkey.Pressed += (_, _) => _ = CaptureAndShowAsync();
        _tray.OpenTranslatorRequested += (_, _) => ShowManual();
        _tray.ExitRequested += (_, _) => Enqueue(_shutdown.Run);
    }

    public string? HotkeyRegistrationError { get; private set; }

    public void Start()
    {
        _tray.Show();
        var registration = _hotkey.Register(_config.Hotkey);
        HotkeyRegistrationError = registration.Error; // tray/manual entry remain usable on collision.
        _viewModel.SetStartupGuidance(GuidancePolicy.Combine(_viewModel.PersistentGuidance, registration.Error));
    }

    public void ShowManual() => Enqueue(_router.ShowManual);

    public void Dispose() => _shutdown.Run();

    private void CancelPopupWork()
    {
        CancelCapture();
        _viewModel.Cancel();
    }

    private void CancelCapture()
    {
        Interlocked.Increment(ref _captureGeneration);
        Interlocked.Exchange(ref _captureRequest, null)?.Cancel();
    }

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
            Enqueue(() =>
            {
                if (generation == Volatile.Read(ref _captureGeneration))
                    Show(CaptureRouting.SourceText(capture));
            });
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

    private static ConfigStartupResult LoadConfig()
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NTranslate", "config.json");
        if (!File.Exists(path))
            return new(AppConfig.Default, null);
        try { return ConfigStartupPolicy.Resolve(File.ReadAllText(path), path); }
        catch (IOException) { return ConfigStartupPolicy.Resolve(null, path); }
        catch (UnauthorizedAccessException) { return ConfigStartupPolicy.Resolve(null, path); }
    }
}
