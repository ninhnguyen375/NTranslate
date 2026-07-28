using System.Net;
using System.Text;
using NTranslate.App.Popup;
using NTranslate.Core.Configuration;
using NTranslate.Core.OpenAI;
using NTranslate.Core.Speech;
using NTranslate.Core.Translation;
using NTranslate.Platform.Clipboard;
using NTranslate.Platform.Images;
using NTranslate.Platform.Shell;

namespace NTranslate.App.Tests.Popup;

public sealed class TranslationViewModelTests
{
    private static AppConfig Config => AppConfig.Default with { MaxTranslateLength = 10 };

    [Fact]
    public async Task CopyFailure_PreservesResultAndAllowsRetry()
    {
        var clipboard = new ThrowingClipboardService();
        var vm = CreateViewModel(ScriptedHandler.Sync(_ => JsonResponse("translated")), clipboard);
        vm.SourceText = "hello";
        await vm.TranslateCommand.ExecuteAsync();

        await vm.CopyCommand.ExecuteAsync();

        Assert.Equal("hello", vm.SourceText);
        Assert.Equal("translated", vm.ResultText);
        Assert.True(vm.CanCopy);
        Assert.Equal(PopupState.Result, vm.State);
        Assert.Contains("Clipboard", vm.StatusMessage, StringComparison.Ordinal);
    }

    [Fact]
    public async Task AutoCopyFailure_PreservesResultAndAllowsManualRetry()
    {
        var clipboard = new FailOnceClipboardService();
        var vm = CreateViewModel(
            ScriptedHandler.Sync(_ => JsonResponse("translated")),
            clipboard,
            autoCopy: true);
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal("translated", vm.ResultText);
        Assert.Equal(PopupState.Result, vm.State);
        Assert.True(vm.CanCopy);
        Assert.Contains("Clipboard", vm.StatusMessage, StringComparison.Ordinal);

        await vm.CopyCommand.ExecuteAsync();

        Assert.Equal("translated", clipboard.LastWritten);
        Assert.Null(vm.StatusMessage);
    }

    [Fact]
    public void StartupGuidance_PersistsWhenCapturedSourceArrives()
    {
        var vm = CreateViewModel(ScriptedHandler.Sync(_ => JsonResponse("unused")), new FakeClipboardService());
        vm.SetStartupGuidance("Configuration is malformed. Using defaults.");

        vm.SourceText = "captured";

        Assert.Equal("Configuration is malformed. Using defaults.", vm.PersistentGuidance);
        Assert.Equal("Configuration is malformed. Using defaults.", vm.StatusMessage);
    }

    [Fact]
    public void SwapLanguages_DoesNotSetTargetToAutoDetect()
    {
        var vm = CreateViewModel(ScriptedHandler.Sync(_ => JsonResponse("unused")), new FakeClipboardService());
        vm.SourceLang = "Auto detect";
        vm.TargetLang = "Vietnamese";

        vm.SwapLanguages();

        Assert.Equal("Auto detect", vm.SourceLang);
        Assert.Equal("Vietnamese", vm.TargetLang);
    }

    [Fact]
    public async Task BlankSourceTextProducesNoRequestAndShowsGuidance()
    {
        var handler = ScriptedHandler.Sync(_ => throw new InvalidOperationException("Network must not be called."));
        var clipboard = new FakeClipboardService();
        var vm = CreateViewModel(handler, clipboard);
        vm.SourceText = "   ";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal(0, handler.CallCount);
        Assert.Equal(PopupState.Guidance, vm.State);
        Assert.False(vm.CanCopy);
    }

    [Fact]
    public async Task OverLimitSourceTextProducesNoRequestAndShowsGuidance()
    {
        var handler = ScriptedHandler.Sync(_ => throw new InvalidOperationException("Network must not be called."));
        var vm = CreateViewModel(handler, new FakeClipboardService());
        vm.SourceText = new string('a', Config.MaxTranslateLength + 1);

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal(0, handler.CallCount);
        Assert.Equal(PopupState.Guidance, vm.State);
    }

    [Fact]
    public async Task TranslateSendsTrimmedTextAndConfiguredLanguages()
    {
        var handler = ScriptedHandler.Sync(_ => JsonResponse("done"));
        var vm = CreateViewModel(handler, new FakeClipboardService());
        vm.SourceLang = "English";
        vm.TargetLang = "Vietnamese";
        vm.SourceText = "  hi  ";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal(1, handler.CallCount);
        Assert.Contains("hi", handler.LastBody, StringComparison.Ordinal);
        Assert.DoesNotContain("  hi  ", handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("English", handler.LastBody, StringComparison.Ordinal);
        Assert.Contains("Vietnamese", handler.LastBody, StringComparison.Ordinal);
        Assert.Equal(PopupState.Result, vm.State);
        Assert.Equal("done", vm.ResultText);
    }

    [Fact]
    public async Task BackgroundCompletionDispatchesUiStateBeforeApplyingResult()
    {
        var handler = new ScriptedHandler(async _ =>
        {
            await Task.Run(() => { });
            return JsonResponse("translated");
        });
        var dispatches = 0;
        var client = new OpenAiCompatibleClient(new HttpClient(handler));
        var vm = new TranslationViewModel(
            Config,
            client,
            new FakeClipboardService(),
            _ => Task.FromResult("test-api-key"),
            action =>
            {
                dispatches++;
                action();
                return Task.CompletedTask;
            });
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.True(dispatches > 0);
        Assert.Equal("translated", vm.ResultText);
        Assert.Equal(PopupState.Result, vm.State);
    }

    [Fact]
    public async Task TranslationWaitsForQueuedUiCompletion()
    {
        var queued = new TaskCompletionSource<Action>(TaskCreationOptions.RunContinuationsAsynchronously);
        var completed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var client = new OpenAiCompatibleClient(new HttpClient(ScriptedHandler.Sync(_ => JsonResponse("translated"))));
        var vm = new TranslationViewModel(
            Config,
            client,
            new FakeClipboardService(),
            _ => Task.FromResult("test-api-key"),
            action =>
            {
                queued.SetResult(action);
                return completed.Task;
            });
        vm.SourceText = "hello";

        var translation = vm.TranslateCommand.ExecuteAsync();
        var action = await queued.Task.WaitAsync(TimeSpan.FromSeconds(1));

        Assert.False(translation.IsCompleted);
        Assert.Equal(PopupState.Loading, vm.State);

        action();
        completed.SetResult();
        await translation;

        Assert.Equal("translated", vm.ResultText);
        Assert.Equal(PopupState.Result, vm.State);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public async Task RejectedUiDispatchCompletesWithoutRetryingOrMutatingOffThread(bool apiFails)
    {
        var dispatches = 0;
        var response = apiFails
            ? new HttpResponseMessage(HttpStatusCode.InternalServerError) { Content = new StringContent("boom") }
            : JsonResponse("translated");
        var client = new OpenAiCompatibleClient(new HttpClient(ScriptedHandler.Sync(_ => response)));
        var vm = new TranslationViewModel(
            Config,
            client,
            new FakeClipboardService(),
            _ => Task.FromResult("test-api-key"),
            _ =>
            {
                dispatches++;
                throw new UiDispatchUnavailableException();
            });
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal(1, dispatches);
        Assert.Equal(PopupState.Loading, vm.State);
        Assert.Equal(string.Empty, vm.ResultText);
        Assert.Null(vm.StatusMessage);
    }

    [Fact]
    public async Task ChangingSourceTextMidFlightCancelsAndInvalidatesLateCompletion()
    {
        var gate = new TaskCompletionSource();
        CancellationToken requestToken = default;
        var handler = new ScriptedHandler(async ct =>
        {
            requestToken = ct;
            await gate.Task; // Simulate transport that completes despite cancellation.
            return JsonResponse("stale-result");
        });
        var vm = CreateViewModel(handler, new FakeClipboardService());
        vm.SourceText = "hello";
        var inFlight = vm.TranslateCommand.ExecuteAsync();

        vm.SourceText = "changed";
        Assert.True(requestToken.IsCancellationRequested);
        gate.SetResult();
        await inFlight;

        Assert.NotEqual(PopupState.Result, vm.State);
        Assert.Equal(string.Empty, vm.ResultText);
    }

    [Fact]
    public async Task ChangingLanguageMidFlightCancelsAndInvalidatesLateCompletion()
    {
        var gate = new TaskCompletionSource();
        CancellationToken requestToken = default;
        var handler = new ScriptedHandler(async ct =>
        {
            requestToken = ct;
            await gate.Task; // Simulate transport that completes despite cancellation.
            return JsonResponse("stale-result");
        });
        var vm = CreateViewModel(handler, new FakeClipboardService());
        vm.SourceText = "hello";
        var inFlight = vm.TranslateCommand.ExecuteAsync();

        vm.TargetLang = "Chinese";
        Assert.True(requestToken.IsCancellationRequested);
        gate.SetResult();
        await inFlight;

        Assert.NotEqual(PopupState.Result, vm.State);
    }

    [Fact]
    public async Task OlderCompletionArrivingAfterNewerRequestStartedLosesToNewer()
    {
        var firstGate = new TaskCompletionSource();
        var callIndex = 0;
        var handler = new ScriptedHandler(async ct =>
        {
            callIndex++;
            if (callIndex == 1)
            {
                await firstGate.Task; // Simulate late completion after cancellation.
                return JsonResponse("first-result");
            }
            return JsonResponse("second-result");
        });
        var vm = CreateViewModel(handler, new FakeClipboardService());
        vm.SourceText = "hello";
        var first = vm.TranslateForTestAsync();

        // Start a second, independent request without invalidating via property change
        // (simulates a fresh Translate click while the first is still pending).
        // Uses the internal test seam so the command's own re-entrancy guard
        // doesn't serialize the two calls; generation gating alone must win.
        var second = vm.TranslateForTestAsync();
        await second;
        firstGate.SetResult();
        var completed = await Task.WhenAny(first, Task.Delay(1000));
        Assert.Same(first, completed);
        await first;

        Assert.Equal("second-result", vm.ResultText);
    }

    [Theory]
    [InlineData("source")]
    [InlineData("language")]
    public async Task EditingAcceptedInputInvalidatesResultAndDisablesCopy(string edit)
    {
        var clipboard = new FakeClipboardService();
        var vm = CreateViewModel(ScriptedHandler.Sync(_ => JsonResponse("old-result")), clipboard);
        vm.SourceText = "hello";
        await vm.TranslateCommand.ExecuteAsync();
        Assert.True(vm.CanCopy);

        if (edit == "source")
            vm.SourceText = "new source";
        else
            vm.TargetLang = "Chinese";

        Assert.Equal(edit == "source" ? "new source" : "hello", vm.SourceText);
        Assert.Equal(string.Empty, vm.ResultText);
        Assert.Equal(PopupState.Guidance, vm.State);
        Assert.False(vm.CanCopy);
        Assert.False(vm.CopyCommand.CanExecute(null));
        await vm.CopyCommand.ExecuteAsync();
        Assert.Null(clipboard.LastWritten);
    }

    [Fact]
    public async Task StaleSuccessfulCompletionDoesNotAutoCopy()
    {
        var gate = new TaskCompletionSource();
        var handler = new ScriptedHandler(async _ =>
        {
            await gate.Task; // Simulate transport completing despite cancellation.
            return JsonResponse("stale-result");
        });
        var clipboard = new FakeClipboardService();
        var vm = CreateViewModel(handler, clipboard, autoCopy: true);
        vm.SourceText = "hello";
        var stale = vm.TranslateCommand.ExecuteAsync();

        vm.SourceText = "changed";
        gate.SetResult();
        await stale;

        Assert.Null(clipboard.LastWritten);
        Assert.Equal(string.Empty, vm.ResultText);
        Assert.Equal(PopupState.Guidance, vm.State);
    }

    [Fact]
    public async Task ApiKeyResolverCancellationWithoutRequestCancellationSurfacesError()
    {
        var vm = new TranslationViewModel(
            Config,
            new OpenAiCompatibleClient(new HttpClient(ScriptedHandler.Sync(_ => throw new InvalidOperationException("Network must not be called.")))),
            new FakeClipboardService(),
            _ => throw new OperationCanceledException("resolver stopped"));
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal(PopupState.Error, vm.State);
        Assert.Equal("resolver stopped", vm.StatusMessage);
    }

    [Fact]
    public async Task TranslatorCancellationWithoutRequestCancellationSurfacesError()
    {
        var vm = CreateViewModel(ScriptedHandler.Sync(_ => throw new OperationCanceledException("translator stopped")), new FakeClipboardService());
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal(PopupState.Error, vm.State);
        Assert.Equal("translator stopped", vm.StatusMessage);
    }

    [Fact]
    public async Task CancelledRequestDoesNotSurfaceVisibleError()
    {
        var handler = new ScriptedHandler(async ct =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, ct);
            return JsonResponse("unused");
        });
        var vm = CreateViewModel(handler, new FakeClipboardService());
        vm.SourceText = "hello";
        var inFlight = vm.TranslateCommand.ExecuteAsync();

        vm.SourceText = "changed"; // cancels the in-flight request
        await inFlight;

        Assert.NotEqual(PopupState.Error, vm.State);
    }

    [Fact]
    public async Task ApiErrorPreservesExistingSourceText()
    {
        var handler = ScriptedHandler.Sync(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError)
        {
            Content = new StringContent("boom")
        });
        var vm = CreateViewModel(handler, new FakeClipboardService());
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal("hello", vm.SourceText);
        Assert.Equal(PopupState.Error, vm.State);
        Assert.False(string.IsNullOrEmpty(vm.StatusMessage));
        Assert.False(vm.CanCopy);
    }

    [Fact]
    public async Task MissingApiKeyShowsSafeGuidanceWithoutSendingRequest()
    {
        var handler = ScriptedHandler.Sync(_ => throw new InvalidOperationException("Network must not be called."));
        var client = new OpenAiCompatibleClient(new HttpClient(handler));
        var vm = new TranslationViewModel(
            Config,
            client,
            new FakeClipboardService(),
            _ => throw new InvalidOperationException("API key missing. Store key in Windows Credential Locker before translating."));
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal(PopupState.Error, vm.State);
        Assert.Equal("API key missing. Store key in Windows Credential Locker before translating.", vm.StatusMessage);
        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task AutoCopyWritesClipboardOnlyOnAcceptedSuccessfulTranslation()
    {
        var handler = ScriptedHandler.Sync(_ => JsonResponse("copied-result"));
        var clipboard = new FakeClipboardService();
        var vm = CreateViewModel(handler, clipboard, autoCopy: true);
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Equal("copied-result", clipboard.LastWritten);
    }

    [Fact]
    public async Task AutoCopyDoesNotWriteClipboardOnError()
    {
        var handler = ScriptedHandler.Sync(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError)
        {
            Content = new StringContent("boom")
        });
        var clipboard = new FakeClipboardService();
        var vm = CreateViewModel(handler, clipboard, autoCopy: true);
        vm.SourceText = "hello";

        await vm.TranslateCommand.ExecuteAsync();

        Assert.Null(clipboard.LastWritten);
    }

    [Theory]
    [MemberData(nameof(NonResultStates))]
    public async Task CopyIsNotActionableOutsideAcceptedResultState(string scenario)
    {
        var clipboard = new FakeClipboardService();
        TranslationViewModel vm;
        switch (scenario)
        {
            case "guidance":
                vm = CreateViewModel(ScriptedHandler.Sync(_ => throw new InvalidOperationException()), clipboard);
                vm.SourceText = "";
                await vm.TranslateCommand.ExecuteAsync();
                break;
            case "loading":
                var gate = new TaskCompletionSource();
                vm = CreateViewModel(new ScriptedHandler(async ct => { await gate.Task.WaitAsync(ct); return JsonResponse("x"); }), clipboard);
                vm.SourceText = "hello";
                _ = vm.TranslateCommand.ExecuteAsync();
                break;
            case "error":
                vm = CreateViewModel(ScriptedHandler.Sync(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError) { Content = new StringContent("boom") }), clipboard);
                vm.SourceText = "hello";
                await vm.TranslateCommand.ExecuteAsync();
                break;
            default:
                throw new ArgumentOutOfRangeException(nameof(scenario));
        }

        Assert.False(vm.CanCopy);
        Assert.False(vm.CopyCommand.CanExecute(null));
        await vm.CopyCommand.ExecuteAsync();
        Assert.Null(clipboard.LastWritten);
    }

    [Fact]
    public async Task OpenHistoryRecordRestoresAcceptedStateWithoutApi()
    {
        var handler = ScriptedHandler.Sync(_ => throw new InvalidOperationException("Network must not be called."));
        var speech = new RecordingSpeech();
        var vm = CreateAdvancedViewModel(handler, speech: speech);
        var id = Guid.NewGuid();
        var record = new NTranslate.Core.History.TranslationRecord(
            id, DateTimeOffset.UtcNow, "offline source", "offline result", "English", "Vietnamese", null, null, true);

        vm.OpenHistoryRecord(record);
        await vm.SpeakResultAsync(CancellationToken.None);

        Assert.Equal(0, handler.CallCount);
        Assert.Equal("offline source", vm.SourceText);
        Assert.Equal("offline result", vm.ResultText);
        Assert.Equal("English", vm.SourceLang);
        Assert.Equal("Vietnamese", vm.TargetLang);
        Assert.Equal(PopupState.Result, vm.State);
        Assert.True(vm.CanCopy);
        Assert.Equal(id, Assert.Single(speech.Playbacks).Identity.HistoryRecordId);
    }

    [Fact]
    public async Task SameLanguageTranslateUsesGrammarPromptAndRecordsHistory()
    {
        var history = new RecordingHistory();
        var handler = ScriptedHandler.Sync(_ => JsonResponse("fixed"));
        var vm = CreateAdvancedViewModel(handler, history: history);
        vm.SourceLang = "English";
        vm.TargetLang = "English";
        vm.SourceText = "bad";

        await vm.TranslateAsync(CancellationToken.None);

        Assert.Contains(Config.GrammarPrompt.Split(' ')[0], handler.LastBody, StringComparison.Ordinal);
        Assert.Single(history.Records);
        Assert.Equal(TranslationMode.Translate, history.Records[0].Mode);
        Assert.True(history.Records[0].IsGrammar);
    }

    [Theory]
    [InlineData("token", "LearnWord")]
    [InlineData("two tokens", "LearnSentence")]
    public async Task LearnSelectsPromptAndNeverRecordsHistory(string text, string expectedPrompt)
    {
        var history = new RecordingHistory();
        var handler = ScriptedHandler.Sync(_ => JsonResponse("lesson"));
        var vm = CreateAdvancedViewModel(handler, history: history);
        vm.SourceText = text;

        await vm.LearnAsync(CancellationToken.None);

        Assert.Contains(expectedPrompt, handler.LastBody, StringComparison.Ordinal);
        Assert.Empty(history.Records);
    }

    [Fact]
    public async Task ImageModeClearsSourceAssociationAndKeepsTargetAndResultSpeech()
    {
        var speech = new RecordingSpeech();
        var vm = CreateAdvancedViewModel(ScriptedHandler.Sync(_ => JsonResponse("image-result")), speech: speech);
        vm.SourceText = "old source";

        await vm.TranslateImageAsync(new MemoryStream([1, 2, 3]), CancellationToken.None);

        Assert.True(vm.IsImageMode);
        Assert.Equal(string.Empty, vm.SourceText);
        Assert.False(vm.CanSelectSourceLanguage);
        Assert.False(vm.CanLearn);
        Assert.False(vm.CanSpeakSource);
        Assert.False(vm.CreatesHistory);
        Assert.True(vm.CanSpeakResult);
        Assert.Equal("image-result", vm.ResultText);
    }

    [Fact]
    public async Task ImageSearchFallsBackToSourceOnApiFailure()
    {
        var browser = new RecordingBrowser();
        var handler = ScriptedHandler.Sync(_ => new HttpResponseMessage(HttpStatusCode.InternalServerError));
        var vm = CreateAdvancedViewModel(handler, browser: browser);
        vm.SourceText = "red panda";

        await vm.SearchImagesAsync(CancellationToken.None);

        Assert.Equal("red panda", browser.OpenedUri?.Query.Split("q=")[1].Replace("%20", " "));
    }

    [Fact]
    public async Task CancelledImageSearchNeverOpensBrowser()
    {
        var browser = new RecordingBrowser();
        var gate = new TaskCompletionSource();
        var handler = new ScriptedHandler(async _ => { await gate.Task; return JsonResponse("query"); });
        var vm = CreateAdvancedViewModel(handler, browser: browser);
        vm.SourceText = "source";
        using var cancellation = new CancellationTokenSource();

        var search = vm.SearchImagesAsync(cancellation.Token);
        cancellation.Cancel();
        gate.SetResult();
        await search;

        Assert.Null(browser.OpenedUri);
    }

    [Theory]
    [InlineData("source")]
    [InlineData("language")]
    [InlineData("image")]
    [InlineData("window")]
    public async Task ContextChangesCancelTranslationAndBothSpeechChannels(string change)
    {
        var speech = new RecordingSpeech();
        var gate = new TaskCompletionSource();
        CancellationToken requestToken = default;
        var handler = new ScriptedHandler(async token => { requestToken = token; await gate.Task; return JsonResponse("late"); });
        var vm = CreateAdvancedViewModel(handler, speech: speech);
        vm.SourceText = "source";
        var translation = vm.TranslateForTestAsync();
        speech.InvalidatedChannels.Clear();

        switch (change)
        {
            case "source": vm.SourceText = "changed"; break;
            case "language": vm.TargetLang = "Chinese"; break;
            case "image": vm.EnterImageMode(); break;
            case "window": vm.WindowChanged(); break;
        }

        Assert.True(requestToken.IsCancellationRequested);
        Assert.Equal(2, speech.InvalidatedChannels.Count);
        gate.SetResult();
        await translation;
        Assert.NotEqual("late", vm.ResultText);
    }

    [Fact]
    public async Task SpeakSourceUsesResolvedSourceModelAndIndependentChannel()
    {
        var speech = new RecordingSpeech();
        var vm = CreateAdvancedViewModel(ScriptedHandler.Sync(_ => JsonResponse("unused")), speech: speech);
        vm.SourceLang = "Vietnamese";
        vm.SourceText = "xin chào";

        await vm.SpeakSourceAsync(CancellationToken.None);

        var playback = Assert.Single(speech.Playbacks);
        Assert.Equal(SpeechChannel.Source, playback.Identity.CacheKey.Channel);
        Assert.Equal("xin chào", playback.Identity.CacheKey.Text);
        Assert.Equal(Config.SpeechSourceModelVietnamese, playback.Identity.CacheKey.Model);
        Assert.Equal(1d, playback.Rate);
    }

    [Fact]
    public async Task SpeakResultUsesAcceptedResultIdentityAndIndependentChannel()
    {
        var speech = new RecordingSpeech();
        var history = new RecordingHistory();
        var vm = CreateAdvancedViewModel(ScriptedHandler.Sync(_ => JsonResponse("translated")), history: history, speech: speech);
        vm.SourceText = "hello";
        await vm.TranslateAsync(CancellationToken.None);

        await vm.SpeakResultAsync(CancellationToken.None);

        var playback = Assert.Single(speech.Playbacks);
        Assert.Equal(SpeechChannel.Result, playback.Identity.CacheKey.Channel);
        Assert.Equal("translated", playback.Identity.CacheKey.Text);
        Assert.Equal(Config.SpeechTargetModel, playback.Identity.CacheKey.Model);
        Assert.Equal(history.LastId, playback.Identity.HistoryRecordId);
        Assert.Equal(1d, playback.Rate);
    }

    [Fact]
    public async Task SpeechPrefetchOccursOnlyAfterAcceptedSuccessfulTextTranslation()
    {
        var speech = new RecordingSpeech();
        var vm = CreateAdvancedViewModel(ScriptedHandler.Sync(_ => JsonResponse("translated")), speech: speech, autoPrefetch: true);
        vm.SourceText = "hello";

        await vm.TranslateAsync(CancellationToken.None);

        Assert.Equal([SpeechChannel.Source, SpeechChannel.Result], speech.Prefetched.Select(x => x.CacheKey.Channel));
    }

    [Fact]
    public async Task SecondAdvancedRequestWinsWhenFirstCompletesLastWithoutSideEffects()
    {
        var history = new RecordingHistory();
        var speech = new RecordingSpeech();
        var firstGate = new TaskCompletionSource();
        var calls = 0;
        var handler = new ScriptedHandler(async _ => ++calls == 1
            ? await CompleteAfter(firstGate.Task, "first")
            : JsonResponse("second"));
        var vm = CreateAdvancedViewModel(handler, history: history, speech: speech, autoPrefetch: true);
        vm.SourceText = "hello";

        var first = vm.TranslateForTestAsync();
        var second = vm.TranslateForTestAsync();
        await second;
        firstGate.SetResult();
        await first;

        Assert.Equal("second", vm.ResultText);
        Assert.Single(history.Records);
        Assert.Equal(2, speech.Prefetched.Count);
    }

    public static TheoryData<string> NonResultStates => ["guidance", "loading", "error"];

    private static async Task<HttpResponseMessage> CompleteAfter(Task gate, string result)
    {
        await gate;
        return JsonResponse(result);
    }

    private static TranslationViewModel CreateAdvancedViewModel(
        ScriptedHandler handler,
        RecordingHistory? history = null,
        RecordingSpeech? speech = null,
        RecordingBrowser? browser = null,
        bool autoPrefetch = false)
    {
        var config = Config with
        {
            AutoPrefetchSpeech = autoPrefetch,
            LearnPrompt = "LearnWord {{config.sourceLang}} {{config.targetLang}}",
            SentenceLearnPrompt = "LearnSentence {{config.sourceLang}} {{config.targetLang}}"
        };
        return new TranslationViewModel(
            config,
            new OpenAiCompatibleClient(new HttpClient(handler)),
            new FakeClipboardService(),
            _ => Task.FromResult("test-api-key"),
            imageNormalizer: new PassThroughNormalizer(),
            browserLauncher: browser ?? new RecordingBrowser(),
            speech: speech ?? new RecordingSpeech(),
            recordHistory: (history ?? new RecordingHistory()).RecordAsync);
    }

    private static TranslationViewModel CreateViewModel(ScriptedHandler handler, IClipboardService clipboard, bool autoCopy = false)
    {
        var config = Config with { Ui = Config.Ui with { AutoCopy = autoCopy } };
        var client = new OpenAiCompatibleClient(new HttpClient(handler));
        return new TranslationViewModel(config, client, clipboard, _ => Task.FromResult("test-api-key"));
    }

    private static HttpResponseMessage JsonResponse(string content) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(
            "{\"choices\":[{\"message\":{\"content\":\"" + content + "\"}}]}",
            Encoding.UTF8,
            "application/json")
    };

    private sealed class ScriptedHandler(Func<CancellationToken, Task<HttpResponseMessage>> respond) : HttpMessageHandler
    {
        public static ScriptedHandler Sync(Func<CancellationToken, HttpResponseMessage> respond) =>
            new(ct => Task.FromResult(respond(ct)));

        public int CallCount { get; private set; }
        public string? LastBody { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CallCount++;
            LastBody = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return await respond(cancellationToken);
        }
    }

    private sealed class ThrowingClipboardService : IClipboardService
    {
        public uint GetSequenceNumber() => 0;
        public IClipboardSnapshot CaptureSnapshot() => throw new NotSupportedException();
        public string? ReadUnicodeText() => null;
        public void WriteUnicodeText(string text) => throw new InvalidOperationException("clipboard busy");
        public bool RestoreIfUnchanged(IClipboardSnapshot snapshot, uint copiedSequenceNumber) => false;
    }

    private sealed class FailOnceClipboardService : IClipboardService
    {
        private bool _failed;
        public string? LastWritten { get; private set; }

        public uint GetSequenceNumber() => 0;
        public IClipboardSnapshot CaptureSnapshot() => throw new NotSupportedException();
        public string? ReadUnicodeText() => null;
        public void WriteUnicodeText(string text)
        {
            if (!_failed)
            {
                _failed = true;
                throw new InvalidOperationException("clipboard busy");
            }

            LastWritten = text;
        }
        public bool RestoreIfUnchanged(IClipboardSnapshot snapshot, uint copiedSequenceNumber) => false;
    }

    private sealed class RecordingHistory
    {
        public List<TranslationHistoryEntry> Records { get; } = [];
        public Guid? LastId { get; private set; }
        public Task<Guid?> RecordAsync(TranslationHistoryEntry entry, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Records.Add(entry);
            LastId = Guid.NewGuid();
            return Task.FromResult(LastId);
        }
    }

    private sealed class RecordingSpeech : ITranslationSpeech
    {
        public List<SpeechIdentity> Prefetched { get; } = [];
        public List<(SpeechIdentity Identity, double Rate)> Playbacks { get; } = [];
        public List<SpeechChannel> InvalidatedChannels { get; } = [];
        public Task PrefetchAsync(SpeechIdentity identity, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Prefetched.Add(identity);
            return Task.CompletedTask;
        }
        public Task TogglePlaybackAsync(SpeechIdentity identity, double rate, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Playbacks.Add((identity, rate));
            return Task.CompletedTask;
        }
        public void Invalidate(SpeechChannel channel, bool stopPlayback) => InvalidatedChannels.Add(channel);
    }

    private sealed class RecordingBrowser : IBrowserLauncher
    {
        public Uri? OpenedUri { get; private set; }
        public Task OpenAsync(Uri uri, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            OpenedUri = uri;
            return Task.CompletedTask;
        }
    }

    private sealed class PassThroughNormalizer : IImageNormalizer
    {
        public async Task<NormalizedImage> NormalizePngAsync(Stream source, CancellationToken cancellationToken)
        {
            using var output = new MemoryStream();
            await source.CopyToAsync(output, cancellationToken);
            return new(output.ToArray(), 1, 1);
        }
    }

    private sealed class FakeClipboardService : IClipboardService
    {
        public string? LastWritten { get; private set; }

        public uint GetSequenceNumber() => 0;
        public IClipboardSnapshot CaptureSnapshot() => new NoopSnapshot();
        public string? ReadUnicodeText() => null;
        public void WriteUnicodeText(string text) => LastWritten = text;
        public bool RestoreIfUnchanged(IClipboardSnapshot snapshot, uint copiedSequenceNumber) => false;

        private sealed class NoopSnapshot : IClipboardSnapshot
        {
            public uint SequenceNumber => 0;
            public void Dispose() { }
        }
    }
}
