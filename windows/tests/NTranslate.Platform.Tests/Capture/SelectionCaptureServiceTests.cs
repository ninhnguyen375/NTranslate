using NTranslate.Platform.Capture;
using NTranslate.Platform.Clipboard;
using NTranslate.Platform.Input;

namespace NTranslate.Platform.Tests.Capture;

public sealed class SelectionCaptureServiceTests
{
    [Fact]
    public async Task Ui_automation_wins_without_touching_clipboard()
    {
        var clipboard = new FakeClipboard("clipboard");
        var copy = new FakeCopyCommand();
        var service = CreateService(new FakeUiaReader("  selected\r\ntext  "), clipboard, copy);

        var capture = await service.CaptureAsync(simulateCopy: true, CancellationToken.None);

        Assert.Equal(new SelectionCapture("selected\r\ntext", SelectionSource.UiAutomation, null), capture);
        Assert.Equal(0, copy.SendCount);
        Assert.Equal(0, clipboard.ReadCount);
    }

    [Fact]
    public async Task Ui_automation_exception_falls_through_without_leaking_exception_text()
    {
        const string selectedText = "private selected text";
        var service = CreateService(
            new FakeUiaReader(exception: new InvalidOperationException(selectedText)),
            new FakeClipboard($"  {selectedText}  "),
            new FakeCopyCommand());

        var capture = await service.CaptureAsync(simulateCopy: false, CancellationToken.None);

        Assert.Equal(selectedText, capture!.Text);
        Assert.Equal(SelectionSource.Clipboard, capture.Source);
        Assert.DoesNotContain(selectedText, capture.Diagnostic ?? string.Empty);
    }

    [Fact]
    public async Task Simulated_copy_sequence_change_returns_copied_text_and_restores_snapshot()
    {
        var clipboard = new FakeClipboard("original", 10);
        var copy = new FakeCopyCommand(() => clipboard.SetExternalText("  copied text  "));
        var service = CreateService(new FakeUiaReader(null), clipboard, copy);

        var capture = await service.CaptureAsync(simulateCopy: true, CancellationToken.None);

        Assert.Equal(new SelectionCapture("copied text", SelectionSource.SimulatedCopy, null), capture);
        Assert.Equal("original", clipboard.Text);
        Assert.Equal(1, clipboard.RestoreCount);
    }

    [Fact]
    public async Task Simulated_copy_timeout_reads_existing_clipboard()
    {
        var clipboard = new FakeClipboard("  existing clipboard  ", 10);
        var delays = new List<TimeSpan>();
        var service = CreateService(
            new FakeUiaReader(null),
            clipboard,
            new FakeCopyCommand(),
            timeout: TimeSpan.FromMilliseconds(20),
            pollInterval: TimeSpan.FromMilliseconds(10),
            delay: (duration, _) => { delays.Add(duration); return Task.CompletedTask; });

        var capture = await service.CaptureAsync(simulateCopy: true, CancellationToken.None);

        Assert.Equal(new SelectionCapture("existing clipboard", SelectionSource.Clipboard, null), capture);
        Assert.Equal(new[] { TimeSpan.FromMilliseconds(10), TimeSpan.FromMilliseconds(10) }, delays);
        Assert.Equal(0, clipboard.RestoreCount);
    }

    [Fact]
    public async Task Whitespace_from_all_sources_returns_null()
    {
        var clipboard = new FakeClipboard(" \t\r\n ");
        var service = CreateService(new FakeUiaReader(" \r\n "), clipboard, new FakeCopyCommand());

        Assert.Null(await service.CaptureAsync(simulateCopy: false, CancellationToken.None));
    }

    [Fact]
    public async Task Cancellation_propagates()
    {
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        var service = CreateService(new FakeUiaReader(null), new FakeClipboard("text"), new FakeCopyCommand());

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => service.CaptureAsync(simulateCopy: true, cancellation.Token));
    }

    [Fact]
    public async Task Cancellation_after_copy_restores_clipboard_before_propagating()
    {
        using var cancellation = new CancellationTokenSource();
        var clipboard = new FakeClipboard("original", 10);
        var copy = new FakeCopyCommand(() => clipboard.SetExternalText("private selected text"));
        var service = CreateService(
            new FakeUiaReader(null),
            clipboard,
            copy,
            delay: (_, token) => { cancellation.Cancel(); return Task.FromCanceled(token); });

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => service.CaptureAsync(simulateCopy: true, cancellation.Token));
        Assert.Equal("original", clipboard.Text);
        Assert.Equal(1, clipboard.RestoreCount);
    }

    [Fact]
    public void Production_timing_is_250ms_timeout_with_10ms_polling()
    {
        Assert.Equal(TimeSpan.FromMilliseconds(250), SelectionCaptureService.CopyTimeout);
        Assert.Equal(TimeSpan.FromMilliseconds(10), SelectionCaptureService.CopyPollInterval);
    }

    private static SelectionCaptureService CreateService(
        IUiAutomationSelectionReader reader,
        IClipboardService clipboard,
        ISimulatedCopyCommand copy,
        TimeSpan? timeout = null,
        TimeSpan? pollInterval = null,
        Func<TimeSpan, CancellationToken, Task>? delay = null) =>
        new(reader, clipboard, copy, timeout, pollInterval, delay);

    private sealed class FakeUiaReader(string? text = null, Exception? exception = null) : IUiAutomationSelectionReader
    {
        public Task<string?> ReadSelectedTextAsync(CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            return exception is null ? Task.FromResult(text) : Task.FromException<string?>(exception);
        }
    }

    private sealed class FakeCopyCommand(Action? onSend = null) : ISimulatedCopyCommand
    {
        public int SendCount { get; private set; }

        public void SendCopy()
        {
            SendCount++;
            onSend?.Invoke();
        }
    }

    private sealed class FakeClipboard(string? text, uint sequenceNumber = 1) : IClipboardService
    {
        public string? Text { get; private set; } = text;
        public int ReadCount { get; private set; }
        public int RestoreCount { get; private set; }

        public uint GetSequenceNumber() => sequenceNumber;

        public IClipboardSnapshot CaptureSnapshot() => new Snapshot(sequenceNumber, Text);

        public string? ReadUnicodeText()
        {
            ReadCount++;
            return Text;
        }

        public void WriteUnicodeText(string value) => SetExternalText(value);

        public bool RestoreIfUnchanged(IClipboardSnapshot snapshot, uint copiedSequenceNumber)
        {
            if (sequenceNumber != copiedSequenceNumber)
                return false;

            var state = Assert.IsType<Snapshot>(snapshot);
            Text = state.Text;
            sequenceNumber++;
            RestoreCount++;
            return true;
        }

        public void SetExternalText(string value)
        {
            Text = value;
            sequenceNumber++;
        }

        private sealed class Snapshot(uint sequenceNumber, string? text) : IClipboardSnapshot
        {
            public uint SequenceNumber { get; } = sequenceNumber;
            public string? Text { get; } = text;
            public void Dispose() { }
        }
    }
}
