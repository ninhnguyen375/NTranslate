using System.ComponentModel;
using System.Runtime.CompilerServices;
using NTranslate.Core.Configuration;
using NTranslate.Core.Languages;
using NTranslate.Core.OpenAI;
using NTranslate.Core.Prompts;
using NTranslate.Core.Requests;
using NTranslate.Platform.Clipboard;

namespace NTranslate.App.Popup;

public enum PopupState
{
    Guidance,
    Loading,
    Result,
    Error
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
    private readonly RequestCoordinator _coordinator = new();

    private CancellationTokenSource? _inFlight;
    private string _sourceText = string.Empty;
    private string _sourceLang;
    private string _targetLang;
    private string _resultText = string.Empty;
    private string? _statusMessage;
    private string? _persistentGuidance;
    private PopupState _state = PopupState.Guidance;

    public TranslationViewModel(
        AppConfig config,
        OpenAiCompatibleClient client,
        IClipboardService clipboard,
        Func<CancellationToken, Task<string>> resolveApiKey,
        Func<Action, Task>? dispatchUi = null)
    {
        _config = config;
        _client = client;
        _clipboard = clipboard;
        _resolveApiKey = resolveApiKey;
        _dispatchUi = dispatchUi ?? (action => { action(); return Task.CompletedTask; });
        _sourceLang = config.SourceLang;
        _targetLang = config.TargetLang;
        TranslateCommand = new AsyncRelayCommand(TranslateAsync);
        CopyCommand = new AsyncRelayCommand(CopyAsync, () => CanCopy);
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
                OnPropertyChanged(nameof(CanCopy));
                CopyCommand.RaiseCanExecuteChanged();
            }
        }
    }

    /// <summary>Copy is only ever actionable for an accepted, non-stale, successful translation.</summary>
    public bool CanCopy => State == PopupState.Result && ResultText.Length > 0;

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

    public void Cancel()
    {
        _coordinator.Invalidate();
        _inFlight?.Cancel();
    }

    /// <summary>
    /// Internal seam for tests: runs the translate flow without the command's
    /// own re-entrancy guard, so generation-gating (rather than command
    /// serialization) can be exercised directly for two overlapping requests.
    /// </summary>
    internal Task TranslateForTestAsync() => TranslateAsync();

    private async Task TranslateAsync()
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

        _inFlight?.Cancel();
        var cancellation = new CancellationTokenSource();
        _inFlight = cancellation;
        int generation = _coordinator.Begin();
        State = PopupState.Loading;

        try
        {
            string apiKey = await _resolveApiKey(cancellation.Token).ConfigureAwait(true);
            var pair = LanguagePolicy.ResolvePair(text, _config with { SourceLang = SourceLang, TargetLang = TargetLang }, []);
            var effectiveConfig = _config with { SourceLang = pair.SourceLang, TargetLang = pair.TargetLang };
            string systemPrompt = PromptRenderer.RenderTranslation(effectiveConfig);
            var request = new ChatCompletionRequest(_config.Model, systemPrompt, new TextChatInput(text));
            string result = await _client.CompleteChatAsync(new Uri(_config.ApiBaseUrl), apiKey, request, cancellation.Token).ConfigureAwait(false);

            await _dispatchUi(() =>
            {
                if (!_coordinator.IsCurrent(generation))
                    return; // superseded or invalidated: discard silently, no error.

                ResultText = result;
                StatusMessage = null;
                State = PopupState.Result;
                if (_config.Ui.AutoCopy)
                {
                    try
                    {
                        _clipboard.WriteUnicodeText(result);
                    }
                    catch
                    {
                        StatusMessage = "Clipboard unavailable. Try Copy again.";
                    }
                }
            }).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested)
        {
            // Cancelled by a newer request or an invalidating change: not a visible error.
        }
        catch (UiDispatchUnavailableException)
        {
            // Dispatcher shutdown is terminal. Do not retry it or mutate UI state off-thread.
            _coordinator.Invalidate();
        }
        catch (Exception ex)
        {
            try
            {
                await _dispatchUi(() =>
                {
                    if (!_coordinator.IsCurrent(generation))
                        return; // stale failure: discard, never surface, never touch SourceText.

                    StatusMessage = ex.Message;
                    State = PopupState.Error;
                }).ConfigureAwait(false);
            }
            catch (UiDispatchUnavailableException)
            {
                // Dispatcher shutdown is terminal. Do not mutate UI state off-thread.
                _coordinator.Invalidate();
            }
        }
        finally
        {
            if (ReferenceEquals(_inFlight, cancellation))
                _inFlight = null;
            cancellation.Dispose();
        }
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
        _coordinator.Invalidate();
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
        _coordinator.Invalidate();
        _inFlight?.Cancel();
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
}
