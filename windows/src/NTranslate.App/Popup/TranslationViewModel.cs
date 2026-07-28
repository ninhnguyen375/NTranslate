using System.ComponentModel;
using System.Runtime.CompilerServices;
using NTranslate.Core.Configuration;
using NTranslate.Core.Languages;
using NTranslate.Core.OpenAI;
using NTranslate.Core.Prompts;
using NTranslate.Core.Requests;
using NTranslate.Core.Speech;
using NTranslate.Core.Translation;
using NTranslate.Platform.Clipboard;
using NTranslate.Platform.Images;
using NTranslate.Platform.Shell;

namespace NTranslate.App.Popup;

public enum PopupState
{
    Guidance,
    Loading,
    Result,
    Error
}

public sealed record AcceptedTextTranslation(
    Guid RecordId,
    DateTimeOffset Timestamp,
    string SourceText,
    string ResultText,
    string SourceLanguage,
    string TargetLanguage,
    bool IsGrammar);

public sealed record TranslationHistoryEntry(
    string SourceText,
    string ResultText,
    string SourceLanguage,
    string TargetLanguage,
    TranslationMode Mode,
    bool IsGrammar = false);

public interface ITranslationSpeech
{
    Task PrefetchAsync(SpeechIdentity identity, CancellationToken cancellationToken);
    Task TogglePlaybackAsync(SpeechIdentity identity, double rate, CancellationToken cancellationToken);
    void Invalidate(SpeechChannel channel, bool stopPlayback);
}

internal sealed class UiDispatchUnavailableException : InvalidOperationException
{
    public UiDispatchUnavailableException() : base("UI dispatcher is unavailable.") { }
}

/// <summary>
/// Text-translation popup state. Owns request cancellation/generation gating
/// so only the newest, non-stale completion can ever mutate <see cref="ResultText"/>,
/// <see cref="State"/>, or the clipboard. Never mutates <see cref="SourceText"/>
/// itself (per plan's "never auto-replace source-app text" constraint) — it
/// only reads it.
/// </summary>
public sealed class TranslationViewModel : INotifyPropertyChanged
{
    private readonly AppConfig _config;
    private readonly OpenAiCompatibleClient _client;
    private readonly IClipboardService _clipboard;
    private readonly Func<CancellationToken, Task<string>> _resolveApiKey;
    private readonly Func<Action, Task> _dispatchUi;
    private readonly IImageNormalizer? _imageNormalizer;
    private readonly IBrowserLauncher? _browserLauncher;
    private readonly ITranslationSpeech? _speech;
    private readonly Func<TranslationHistoryEntry, CancellationToken, Task<Guid?>>? _recordHistory;
    private readonly RequestCoordinator _coordinator = new();

    private CancellationTokenSource? _inFlight;
    private string _sourceText = string.Empty;
    private string _sourceLang;
    private string _targetLang;
    private string _resultText = string.Empty;
    private string? _statusMessage;
    private string? _persistentGuidance;
    private PopupState _state = PopupState.Guidance;
    private bool _isImageMode;
    private SpeechIdentity? _sourceSpeechIdentity;
    private SpeechIdentity? _resultSpeechIdentity;

    public TranslationViewModel(
        AppConfig config,
        OpenAiCompatibleClient client,
        IClipboardService clipboard,
        Func<CancellationToken, Task<string>> resolveApiKey,
        Func<Action, Task>? dispatchUi = null,
        IImageNormalizer? imageNormalizer = null,
        IBrowserLauncher? browserLauncher = null,
        ITranslationSpeech? speech = null,
        Func<TranslationHistoryEntry, CancellationToken, Task<Guid?>>? recordHistory = null)
    {
        _config = config;
        _client = client;
        _clipboard = clipboard;
        _resolveApiKey = resolveApiKey;
        _dispatchUi = dispatchUi ?? (action => { action(); return Task.CompletedTask; });
        _imageNormalizer = imageNormalizer;
        _browserLauncher = browserLauncher;
        _speech = speech;
        _recordHistory = recordHistory;
        _sourceLang = config.SourceLang;
        _targetLang = config.TargetLang;
        TranslateCommand = new AsyncRelayCommand(TranslateAsync);
        CopyCommand = new AsyncRelayCommand(CopyAsync, () => CanCopy);
    }

    public TranslationViewModel(
        AppConfig config,
        OpenAiCompatibleClient client,
        IClipboardService clipboard,
        Func<CancellationToken, Task<string>> resolveApiKey,
        IImageNormalizer imageNormalizer,
        IBrowserLauncher browserLauncher,
        SpeechCoordinator speechCoordinator,
        Func<TranslationHistoryEntry, CancellationToken, Task<Guid?>>? recordHistory = null,
        Func<Action, Task>? dispatchUi = null)
        : this(
            config,
            client,
            clipboard,
            resolveApiKey,
            dispatchUi,
            imageNormalizer,
            browserLauncher,
            new SpeechCoordinatorBoundary(speechCoordinator),
            recordHistory)
    {
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public string SourceText
    {
        get => _sourceText;
        set => SetInvalidating(ref _sourceText, value);
    }

    public string SourceLang
    {
        get => _sourceLang;
        set => SetInvalidating(ref _sourceLang, value);
    }

    public string TargetLang
    {
        get => _targetLang;
        set => SetInvalidating(ref _targetLang, value);
    }

    public string ResultText
    {
        get => _resultText;
        private set => Set(ref _resultText, value);
    }

    /// <summary>Guidance text (blank/too-long) or error message, depending on <see cref="State"/>.</summary>
    public string? StatusMessage
    {
        get => _statusMessage ?? PersistentGuidance;
        private set
        {
            if (Set(ref _statusMessage, value))
                OnPropertyChanged(nameof(StatusMessage));
        }
    }

    public string? PersistentGuidance
    {
        get => _persistentGuidance;
        private set
        {
            if (Set(ref _persistentGuidance, value))
                OnPropertyChanged(nameof(StatusMessage));
        }
    }

    public PopupState State
    {
        get => _state;
        private set
        {
            if (Set(ref _state, value))
            {
                OnPropertyChanged(nameof(IsLoading));
                OnPropertyChanged(nameof(CanCopy));
                CopyCommand.RaiseCanExecuteChanged();
            }
        }
    }

    /// <summary>Copy is only ever actionable for an accepted, non-stale, successful translation.</summary>
    public bool CanCopy => State == PopupState.Result && ResultText.Length > 0;
    public bool IsLoading => State == PopupState.Loading;
    public bool IsImageMode => _isImageMode;
    public bool CanSelectSourceLanguage => !IsImageMode;
    public bool CanLearn => !IsImageMode;
    public bool CanSpeakSource => !IsImageMode && SourceText.Length > 0;
    public bool CanSpeakResult => ResultText.Length > 0;
    public bool CreatesHistory => !IsImageMode;

    public IReadOnlyList<string> Languages => _config.Languages;

    public IReadOnlyList<string> TargetLanguages => _config.TargetLanguages;

    public IAsyncCommand TranslateCommand { get; }

    public AsyncRelayCommand CopyCommand { get; }

    public void SwapLanguages()
    {
        if (!_config.TargetLanguages.Contains(SourceLang, StringComparer.OrdinalIgnoreCase))
            return;
        (SourceLang, TargetLang) = (TargetLang, SourceLang);
    }

    internal void SetStartupGuidance(string? guidance) => PersistentGuidance = guidance;

    public void Cancel() => InvalidateAll();

    public Task TranslateAsync(CancellationToken cancellationToken) => TranslateTextAsync(TranslationMode.Translate, cancellationToken);

    public Task LearnAsync(CancellationToken cancellationToken) => TranslateTextAsync(TranslationMode.Learn, cancellationToken);

    public Task SpeakSourceAsync(CancellationToken cancellationToken)
    {
        if (_speech is null || !CanSpeakSource) return Task.CompletedTask;
        var identity = SpeechIdentityFor(SpeechChannel.Source, SourceText, SourceLang, _sourceSpeechIdentity?.HistoryRecordId);
        _sourceSpeechIdentity = identity;
        return _speech.TogglePlaybackAsync(identity, _config.SpeechRate, cancellationToken);
    }

    public Task SpeakResultAsync(CancellationToken cancellationToken)
    {
        if (_speech is null || !CanSpeakResult) return Task.CompletedTask;
        var identity = SpeechIdentityFor(SpeechChannel.Result, ResultText, TargetLang, _resultSpeechIdentity?.HistoryRecordId);
        _resultSpeechIdentity = identity;
        return _speech.TogglePlaybackAsync(identity, _config.SpeechRate, cancellationToken);
    }

    public async Task TranslateImageAsync(Stream image, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(image);
        if (_imageNormalizer is null) throw new InvalidOperationException("Image normalization is unavailable.");
        EnterImageMode();
        using var lease = BeginRequest(cancellationToken, out var requestCancellation);
        try
        {
            var normalized = await _imageNormalizer.NormalizePngAsync(image, requestCancellation.Token).ConfigureAwait(false);
            string apiKey = await _resolveApiKey(requestCancellation.Token).ConfigureAwait(false);
            var request = new ChatCompletionRequest(_config.Model, PromptRenderer.RenderTranslation(_config), new ImageChatInput(normalized.PngData.ToArray(), TargetLang));
            string result = await _client.CompleteChatAsync(new Uri(_config.ApiBaseUrl), apiKey, request, requestCancellation.Token).ConfigureAwait(false);
            await ApplyAcceptedResultAsync(lease.Generation, result, null, TranslationMode.ImageTranslate, false, requestCancellation.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (requestCancellation.IsCancellationRequested) { }
        catch (Exception ex) { await ApplyErrorAsync(lease.Generation, ex).ConfigureAwait(false); }
        finally { FinishRequest(requestCancellation); }
    }

    public async Task SearchImagesAsync(CancellationToken cancellationToken)
    {
        if (_browserLauncher is null) throw new InvalidOperationException("Browser launch is unavailable.");
        string fallback = SourceText.Trim();
        using var lease = BeginRequest(cancellationToken, out var requestCancellation);
        string? generated = null;
        try
        {
            string apiKey = await _resolveApiKey(requestCancellation.Token).ConfigureAwait(false);
            var request = new ChatCompletionRequest(_config.Model, "Return only a concise image search query.", new TextChatInput(fallback));
            generated = await _client.CompleteChatAsync(new Uri(_config.ApiBaseUrl), apiKey, request, requestCancellation.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (requestCancellation.IsCancellationRequested) { return; }
        catch { }
        finally
        {
            if (ReferenceEquals(_inFlight, requestCancellation)) _inFlight = null;
        }
        if (!_coordinator.Accepts(lease.Generation) || requestCancellation.IsCancellationRequested)
        {
            requestCancellation.Dispose();
            return;
        }
        try
        {
            string query = ImageSearchPolicy.ResolveQuery(generated, fallback);
            await _browserLauncher.OpenAsync(ImageSearchPolicy.CreateGoogleImagesUri(query), requestCancellation.Token).ConfigureAwait(false);
        }
        finally { requestCancellation.Dispose(); }
    }

    public void EnterImageMode()
    {
        InvalidateAll();
        _isImageMode = true;
        _sourceText = string.Empty;
        OnPropertyChanged(nameof(SourceText));
        OnImageModeChanged();
        ResultText = string.Empty;
        State = PopupState.Guidance;
    }

    public void WindowChanged() => InvalidateAll();

    /// <summary>
    /// Internal seam for tests: runs the translate flow without the command's
    /// own re-entrancy guard, so generation-gating (rather than command
    /// serialization) can be exercised directly for two overlapping requests.
    /// </summary>
    internal Task TranslateForTestAsync() => TranslateAsync();

    private Task TranslateAsync() => TranslateTextAsync(TranslationMode.Translate, CancellationToken.None);

    private async Task TranslateTextAsync(TranslationMode mode, CancellationToken outerCancellationToken)
    {
        string text = SourceText.Trim();
        if (text.Length == 0)
        {
            RejectWithGuidance("Enter text to translate.");
            return;
        }
        if (text.Length > _config.MaxTranslateLength)
        {
            RejectWithGuidance($"Text exceeds {_config.MaxTranslateLength} characters.");
            return;
        }

        _isImageMode = false;
        OnImageModeChanged();
        using var lease = BeginRequest(outerCancellationToken, out var cancellation);

        try
        {
            string apiKey = await _resolveApiKey(cancellation.Token).ConfigureAwait(true);
            var pair = LanguagePolicy.ResolvePair(text, _config with { SourceLang = SourceLang, TargetLang = TargetLang }, []);
            var effectiveConfig = _config with { SourceLang = pair.SourceLang, TargetLang = pair.TargetLang };
            bool isGrammar = mode == TranslationMode.Translate
                && PromptRenderer.SelectMode(text, pair.SourceLang, pair.TargetLang, false) == PromptMode.Grammar;
            string systemPrompt = mode == TranslationMode.Learn
                ? PromptRenderer.RenderLearn(text, effectiveConfig)
                : isGrammar
                    ? PromptRenderer.RenderGrammar(pair.TargetLang, effectiveConfig)
                    : PromptRenderer.RenderTranslation(effectiveConfig);
            var request = new ChatCompletionRequest(_config.Model, systemPrompt, new TextChatInput(text));
            string result = await _client.CompleteChatAsync(new Uri(_config.ApiBaseUrl), apiKey, request, cancellation.Token).ConfigureAwait(false);

            await ApplyAcceptedResultAsync(
                lease.Generation,
                result,
                mode == TranslationMode.Translate ? text : null,
                mode,
                isGrammar,
                cancellation.Token).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            // Cancelled by a newer request or an invalidating change: not a visible error.
        }
        catch (UiDispatchUnavailableException)
        {
            // Dispatcher shutdown is terminal. Do not retry it or mutate UI state off-thread.
            _coordinator.CancelCurrent();
        }
        catch (Exception ex)
        {
            try
            {
                await _dispatchUi(() =>
                {
                    if (!_coordinator.Accepts(lease.Generation))
                        return; // stale failure: discard, never surface, never touch SourceText.

                    StatusMessage = ex.Message;
                    State = PopupState.Error;
                }).ConfigureAwait(false);
            }
            catch (UiDispatchUnavailableException)
            {
                // Dispatcher shutdown is terminal. Do not mutate UI state off-thread.
                _coordinator.CancelCurrent();
            }
        }
        finally { FinishRequest(cancellation); }
    }

    private RequestLease BeginRequest(CancellationToken outerCancellationToken, out CancellationTokenSource cancellation)
    {
        _inFlight?.Cancel();
        cancellation = CancellationTokenSource.CreateLinkedTokenSource(outerCancellationToken);
        _inFlight = cancellation;
        var lease = _coordinator.Begin(cancellation.Token);
        State = PopupState.Loading;
        return lease;
    }

    private void FinishRequest(CancellationTokenSource cancellation)
    {
        if (ReferenceEquals(_inFlight, cancellation)) _inFlight = null;
        cancellation.Dispose();
    }

    private async Task ApplyAcceptedResultAsync(
        RequestGeneration generation,
        string result,
        string? historySource,
        TranslationMode mode,
        bool isGrammar,
        CancellationToken cancellationToken)
    {
        Guid? historyId = null;
        await _dispatchUi(() =>
        {
            if (!_coordinator.Accepts(generation)) return;
            ResultText = result;
            StatusMessage = null;
            State = PopupState.Result;
            if (_config.Ui.AutoCopy)
            {
                try { _clipboard.WriteUnicodeText(result); }
                catch { StatusMessage = "Clipboard unavailable. Try Copy again."; }
            }
        }).ConfigureAwait(false);
        if (!_coordinator.Accepts(generation)) return;
        if (historySource is not null && _recordHistory is not null)
        {
            historyId = await _recordHistory(new(historySource, result, SourceLang, TargetLang, mode, isGrammar), cancellationToken).ConfigureAwait(false);
            if (!_coordinator.Accepts(generation)) return;
        }
        if (mode == TranslationMode.Translate)
        {
            _sourceSpeechIdentity = SpeechIdentityFor(SpeechChannel.Source, historySource!, SourceLang, historyId);
            _resultSpeechIdentity = SpeechIdentityFor(SpeechChannel.Result, result, TargetLang, historyId);
        }
        else
        {
            _sourceSpeechIdentity = null;
            _resultSpeechIdentity = SpeechIdentityFor(SpeechChannel.Result, result, TargetLang, null);
        }
        if (_config.AutoPrefetchSpeech && _speech is not null && mode == TranslationMode.Translate)
        {
            await _speech.PrefetchAsync(_sourceSpeechIdentity!, cancellationToken).ConfigureAwait(false);
            if (!_coordinator.Accepts(generation)) return;
            await _speech.PrefetchAsync(_resultSpeechIdentity!, cancellationToken).ConfigureAwait(false);
        }
    }

    private async Task ApplyErrorAsync(RequestGeneration generation, Exception exception)
    {
        await _dispatchUi(() =>
        {
            if (!_coordinator.Accepts(generation)) return;
            StatusMessage = exception.Message;
            State = PopupState.Error;
        }).ConfigureAwait(false);
    }

    private SpeechIdentity SpeechIdentityFor(SpeechChannel channel, string text, string language, Guid? historyId) =>
        new(new(channel, text, channel == SpeechChannel.Result ? _config.SpeechTargetModel : SpeechModelResolver.Resolve(language, _config)), historyId);

    private void InvalidateAll()
    {
        _coordinator.CancelCurrent();
        _inFlight?.Cancel();
        _sourceSpeechIdentity = null;
        _resultSpeechIdentity = null;
        _speech?.Invalidate(SpeechChannel.Source, true);
        _speech?.Invalidate(SpeechChannel.Result, true);
    }

    private void OnImageModeChanged()
    {
        OnPropertyChanged(nameof(IsImageMode));
        OnPropertyChanged(nameof(CanSelectSourceLanguage));
        OnPropertyChanged(nameof(CanLearn));
        OnPropertyChanged(nameof(CanSpeakSource));
        OnPropertyChanged(nameof(CreatesHistory));
    }

    private Task CopyAsync()
    {
        if (!CanCopy)
            return Task.CompletedTask;
        try
        {
            _clipboard.WriteUnicodeText(ResultText);
            StatusMessage = null;
        }
        catch
        {
            StatusMessage = "Clipboard unavailable. Try Copy again.";
        }
        return Task.CompletedTask;
    }

    private void RejectWithGuidance(string message)
    {
        _coordinator.CancelCurrent();
        _inFlight?.Cancel();
        ResultText = string.Empty;
        StatusMessage = message;
        State = PopupState.Guidance;
    }

    private void SetInvalidating(ref string field, string value)
    {
        if (!Set(ref field, value))
            return;

        // Source text/language changed mid-flight: cancel and invalidate so a
        // late completion for the old request can never apply.
        InvalidateAll();
        ResultText = string.Empty;
        StatusMessage = null;
        State = PopupState.Guidance;
    }

    private bool Set<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
            return false;

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged(string? propertyName) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));

    private sealed class SpeechCoordinatorBoundary(SpeechCoordinator coordinator) : ITranslationSpeech
    {
        public Task PrefetchAsync(SpeechIdentity identity, CancellationToken cancellationToken) =>
            coordinator.PrefetchAsync(identity, cancellationToken);

        public Task TogglePlaybackAsync(SpeechIdentity identity, double rate, CancellationToken cancellationToken) =>
            coordinator.TogglePlaybackAsync(identity, rate, cancellationToken);

        public void Invalidate(SpeechChannel channel, bool stopPlayback) =>
            coordinator.Invalidate(channel, stopPlayback);
    }
}
