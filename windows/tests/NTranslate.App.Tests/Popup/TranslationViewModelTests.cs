using System.Net;
using System.Text;
using NTranslate.App.Popup;
using NTranslate.Core.Configuration;
using NTranslate.Core.OpenAI;
using NTranslate.Platform.Clipboard;

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

    public static TheoryData<string> NonResultStates => ["guidance", "loading", "error"];

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
