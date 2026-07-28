using System.Diagnostics;
using System.Reflection;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using NTranslate.App.History;
using NTranslate.App.Popup;
using NTranslate.App.Recovery;
using NTranslate.App.Settings;
using NTranslate.App.Updates;
using NTranslate.Core.Configuration;
using NTranslate.Core.History;
using NTranslate.Core.OpenAI;
using NTranslate.Core.Settings;
using NTranslate.Core.Speech;
using NTranslate.Core.Updates;
using NTranslate.Platform.Capture;
using NTranslate.Platform.Clipboard;
using NTranslate.Platform.Credentials;
using NTranslate.Platform.Diagnostics;
using NTranslate.Platform.Images;
using NTranslate.Platform.Input;
using NTranslate.Platform.Media;
using NTranslate.Platform.Shell;
using NTranslate.Platform.Storage;
using NTranslate.Platform.Updates;
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
    private readonly HistoryViewModel _historyViewModel;
    private readonly HistoryWindow _historyWindow;
    private readonly SettingsWindow _settingsWindow;
    private readonly SpeechCoordinator _speech;
    private readonly UpdateCoordinator _updates;
    private readonly RecoveryCoordinator _recovery;
    private readonly AppShutdown _shutdown;
    private readonly AppConfig _config;
    private readonly string _root;
    private readonly string _configPath;
    private readonly PopupRouter _router;
    private CancellationTokenSource? _captureRequest;
    private int _captureGeneration;

    public AppComposition(DispatcherQueue dispatcher)
    {
        _dispatcher = dispatcher;
        var startup = LoadConfig();
        _config = startup.Config;
        _root = string.IsNullOrWhiteSpace(_config.HistoryDirectory)
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NTranslate")
            : Path.GetFullPath(_config.HistoryDirectory);
        _configPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NTranslate", "config.json");

        _clipboard = new OleClipboardService();
        _capture = new SelectionCaptureService(new UiAutomationSelectionReader(), _clipboard, new SendInputCopyCommand());
        _hotkey = new GlobalHotkey();
        _tray = new TrayIcon();
        var credentials = new CredentialLockerApiKeyStore();
        var http = new HttpClient();
        var client = new OpenAiCompatibleClient(http);
        var historyStore = new JsonTranslationHistoryStore(_root);
        var historySink = new AcceptedTranslationSink(historyStore);
        _speech = new SpeechCoordinator(
            new OpenAiSpeechApi(client, _config, ResolveApiKeyAsync),
            new WindowsSpeechPlayer(),
            new SpeechHistoryAdapter(historyStore));
        _viewModel = new TranslationViewModel(
            _config,
            client,
            _clipboard,
            ResolveApiKeyAsync,
            new WindowsImageNormalizer(),
            new WindowsBrowserLauncher(),
            _speech,
            async (entry, token) =>
            {
                if (entry.Mode != NTranslate.Core.Translation.TranslationMode.Translate) return null;
                var accepted = new AcceptedTextTranslation(Guid.NewGuid(), DateTimeOffset.UtcNow, entry.SourceText, entry.ResultText, entry.SourceLanguage, entry.TargetLanguage, entry.IsGrammar);
                await historySink.AcceptAsync(new TranslationRecord(accepted.RecordId, accepted.Timestamp, accepted.SourceText, accepted.ResultText, accepted.SourceLanguage, accepted.TargetLanguage, null, null, false), token).ConfigureAwait(false);
                return accepted.RecordId;
            },
            DispatchAsync);
        _viewModel.SetStartupGuidance(startup.Guidance);
        _window = new TranslationWindow(_viewModel, _config.Ui.Width, _config.Ui.Height, CancelPopupWork);

        _historyViewModel = new HistoryViewModel(
            historyStore,
            new HistoryAudioPlayer(),
            (_, _) => Task.FromResult(true),
            (record, _) => { Show(record.SourceText); return Task.CompletedTask; },
            dispatchUi: DispatchAsync);
        _historyWindow = new HistoryWindow(_historyViewModel);

        var configStore = new JsonConfigStore(_configPath);
        var settingsSave = new SettingsSaveCoordinator(configStore, credentials, new HistoryDirectoryMigrator(), (_, _, _, _) => Task.CompletedTask);
        var settingsViewModel = new SettingsViewModel(
            _config,
            credentials.LoadAsync().GetAwaiter().GetResult() ?? string.Empty,
            async (request, token) => await settingsSave.SaveAsync(
                request.Config,
                request.ApiKey,
                request.SpeechRate,
                request.StartWithWindows,
                _root,
                string.IsNullOrWhiteSpace(request.Config.HistoryDirectory) ? _root : Path.GetFullPath(request.Config.HistoryDirectory),
                token).ConfigureAwait(false),
            CloseSettings);
        _settingsWindow = new SettingsWindow(settingsViewModel);

        var releases = new GitHubReleaseClient(http, "ninhnguyen375", "NTranslate");
        var currentVersion = SemanticVersion.TryParse(Assembly.GetExecutingAssembly().GetName().Version?.ToString(3), out var version) ? version : new(0, 0, 0);
        _updates = new UpdateCoordinator(
            currentVersion,
            async token =>
            {
                var selected = WindowsUpdatePolicy.Select(currentVersion, await releases.GetReleasesAsync(token).ConfigureAwait(false));
                return selected is null ? [] : [selected];
            },
            releases.DownloadAsync,
            new MsixPackageVerifier(),
            info => Process.Start(info));
        var crashLogs = new CrashLogService(_root, new AtomicFileWriter());
        _recovery = new RecoveryCoordinator(crashLogs, new RecoveryNotice(), new ShellLogDirectoryLauncher());

        _router = new PopupRouter(CancelCapture, () => Show(null));
        _shutdown = new AppShutdown(
            () => { _lifetime.Cancel(); _captureRequest?.Cancel(); _viewModel.Cancel(); _speech.InvalidateAll(true); },
            _hotkey.Dispose,
            _tray.Dispose,
            _window.RestoreWindowProcedure,
            () =>
            {
                _historyViewModel.DisposeAsync().AsTask().GetAwaiter().GetResult();
                _speech.DisposeAsync().AsTask().GetAwaiter().GetResult();
                _historyWindow.Close();
                _settingsWindow.Close();
                _window.CloseForShutdown();
            });

        _hotkey.Pressed += (_, _) => _ = CaptureAndShowAsync();
        _tray.OpenTranslatorRequested += (_, _) => ShowManual();
        _tray.HistoryRequested += (_, _) => Enqueue(ShowHistory);
        _tray.SettingsRequested += (_, _) => Enqueue(ShowSettings);
        _tray.CheckForUpdatesRequested += (_, _) => _ = _updates.CheckAsync(true, _lifetime.Token);
        _tray.StartWithWindowsRequested += (_, _) => Enqueue(ShowSettings);
        _tray.ExitRequested += (_, _) => Enqueue(_shutdown.Run);
    }

    internal XamlRoot? ContentRoot => (_window.Content as FrameworkElement)?.XamlRoot;
    public string? HotkeyRegistrationError { get; private set; }

    public void Start()
    {
        _tray.Show();
        var registration = _hotkey.Register(_config.Hotkey);
        HotkeyRegistrationError = registration.Error;
        _viewModel.SetStartupGuidance(GuidancePolicy.Combine(_viewModel.PersistentGuidance, registration.Error));
        _ = _recovery.ShowPendingAsync(_lifetime.Token);
    }

    public void ShowManual() => Enqueue(_router.ShowManual);
    public void Dispose() => _shutdown.Run();

    private Task<string> ResolveApiKeyAsync(CancellationToken token) => new CredentialLockerApiKeyStore().LoadAsync(token).ContinueWith(
        task => task.Result ?? throw new InvalidOperationException("API key missing. Store key in Windows Credential Locker before translating."),
        token,
        TaskContinuationOptions.ExecuteSynchronously,
        TaskScheduler.Default);

    private Task DispatchAsync(Action action)
    {
        var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        if (!_dispatcher.TryEnqueue(() =>
            {
                try { action(); completion.SetResult(); }
                catch (Exception error) { completion.SetException(error); }
            })) completion.SetException(new UiDispatchUnavailableException());
        return completion.Task;
    }

    private void ShowHistory()
    {
        _historyWindow.Activate();
        _ = _historyViewModel.ReloadAsync(_lifetime.Token);
    }

    private void ShowSettings() => _settingsWindow.Activate();
    private void CloseSettings() => _settingsWindow?.AppWindow.Hide();
    private void CancelPopupWork() { CancelCapture(); _viewModel.Cancel(); }
    private void CancelCapture() { Interlocked.Increment(ref _captureGeneration); Interlocked.Exchange(ref _captureRequest, null)?.Cancel(); }

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
            Enqueue(() => { if (generation == Volatile.Read(ref _captureGeneration)) Show(CaptureRouting.SourceText(capture)); });
    }

    private void Show(string? text)
    {
        if (text is null) _viewModel.SourceText = string.Empty;
        _window.ShowPopup(text);
    }

    private void Enqueue(Action action) => _dispatcher.TryEnqueue(() => { if (!_lifetime.IsCancellationRequested) action(); });

    private static ConfigStartupResult LoadConfig()
    {
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "NTranslate", "config.json");
        if (!File.Exists(path)) return new(AppConfig.Default, null);
        try { return ConfigStartupPolicy.Resolve(File.ReadAllText(path), path); }
        catch (IOException) { return ConfigStartupPolicy.Resolve(null, path); }
        catch (UnauthorizedAccessException) { return ConfigStartupPolicy.Resolve(null, path); }
    }
}
