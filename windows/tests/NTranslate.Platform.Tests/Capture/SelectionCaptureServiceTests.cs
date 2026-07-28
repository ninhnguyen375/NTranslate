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
    public async Task Simulated_copy_sequence_change_returns_copied_text_without_unsafe_restore()
    {
        var clipboard = new FakeClipboard("original", 10);
        var copy = new FakeCopyCommand(() => clipboard.SetExternalText("  copied text  "));
        var service = CreateService(new FakeUiaReader(null), clipboard, copy);

        var capture = await service.CaptureAsync(simulateCopy: true, CancellationToken.None);

        Assert.Equal(new SelectionCapture("copied text", SelectionSource.SimulatedCopy, null), capture);
        Assert.Equal("  copied text  ", clipboard.Text);
        Assert.Equal(0, clipboard.RestoreCount);
    }

    [Fact]
    public async Task External_write_after_simulated_copy_is_never_restored_over()
    {
        var clipboard = new FakeClipboard("original", 10);
        var copy = new FakeCopyCommand(() => clipboard.SetExternalText("copied"));
        var service = CreateService(
            new FakeUiaReader(null),
            clipboard,
            copy,
            delay: (_, _) =>
            {
                clipboard.SetExternalText("external");
                return Task.CompletedTask;
            });

        await service.CaptureAsync(simulateCopy: true, CancellationToken.None);

        Assert.Equal("external", clipboard.Text);
        Assert.Equal(0, clipboard.RestoreCount);
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
    public async Task Cancellation_after_copy_preserves_unproven_clipboard_before_propagating()
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
        Assert.Equal("private selected text", clipboard.Text);
        Assert.Equal(0, clipboard.RestoreCount);
    }

    [Fact]
    public async Task Concurrent_simulated_captures_serialize_without_restore()
    {
        var clipboard = new FakeClipboard("original", 10);
        var firstDelayEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirstDelay = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var delayCount = 0;
        var copy = new FakeCopyCommand(() => clipboard.SetExternalText($"copy {clipboard.CaptureCount}"));
        var service = CreateService(
            new FakeUiaReader(null),
            clipboard,
            copy,
            delay: async (_, token) =>
            {
                if (Interlocked.Increment(ref delayCount) == 1)
                {
                    firstDelayEntered.SetResult();
                    await releaseFirstDelay.Task.WaitAsync(token);
                }
            });

        var first = service.CaptureAsync(simulateCopy: true, CancellationToken.None);
        await firstDelayEntered.Task;
        var second = service.CaptureAsync(simulateCopy: true, CancellationToken.None);
        await Task.Yield();

        Assert.Equal(1, clipboard.CaptureCount);
        Assert.Equal(1, copy.SendCount);
        releaseFirstDelay.SetResult();

        var captures = await Task.WhenAll(first, second);
        Assert.Equal(new[] { "copy 1", "copy 2" }, captures.Select(capture => capture!.Text));
        Assert.Equal("copy 2", clipboard.Text);
        Assert.Equal(0, clipboard.RestoreCount);
    }

    [Fact]
    public async Task Concurrent_timeouts_read_clipboard_before_serialized_transaction_ends()
    {
        var clipboard = new FakeClipboard(null, 10);
        var firstDelayEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirstDelay = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var delayCount = 0;
        var service = CreateService(
            new FakeUiaReader(null),
            clipboard,
            new FakeCopyCommand(),
            timeout: TimeSpan.FromMilliseconds(10),
            pollInterval: TimeSpan.FromMilliseconds(10),
            delay: async (_, token) =>
            {
                if (Interlocked.Increment(ref delayCount) == 1)
                {
                    firstDelayEntered.SetResult();
                    await releaseFirstDelay.Task.WaitAsync(token);
                }
            });

        var first = service.CaptureAsync(simulateCopy: true, CancellationToken.None);
        await firstDelayEntered.Task;
        var second = service.CaptureAsync(simulateCopy: true, CancellationToken.None);
        releaseFirstDelay.SetResult();

        var captures = await Task.WhenAll(first, second);
        Assert.All(captures, Assert.Null);
        Assert.Equal(0, clipboard.ReadsOutsideSnapshot);
    }

    [Fact]
    public async Task Concurrent_whitespace_copies_read_clipboard_before_transaction_ends()
    {
        var clipboard = new FakeClipboard(" \t ", 10);
        var firstDelayEntered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var releaseFirstDelay = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var delayCount = 0;
        var copy = new FakeCopyCommand(() => clipboard.SetExternalText(" \t "));
        var service = CreateService(
            new FakeUiaReader(null),
            clipboard,
            copy,
            delay: async (_, token) =>
            {
                if (Interlocked.Increment(ref delayCount) == 1)
                {
                    firstDelayEntered.SetResult();
                    await releaseFirstDelay.Task.WaitAsync(token);
                }
            });

        var first = service.CaptureAsync(simulateCopy: true, CancellationToken.None);
        await firstDelayEntered.Task;
        var second = service.CaptureAsync(simulateCopy: true, CancellationToken.None);
        releaseFirstDelay.SetResult();

        var captures = await Task.WhenAll(first, second);
        Assert.All(captures, Assert.Null);
        Assert.Equal(0, clipboard.ReadsOutsideSnapshot);
        Assert.Equal(0, clipboard.RestoreCount);
    }

    [Fact]
    public async Task Send_copy_throw_does_not_restore_external_clipboard_change()
    {
        var clipboard = new FakeClipboard("original", 10);
        var copy = new FakeCopyCommand(() =>
        {
            clipboard.SetExternalText("external clipboard change");
            throw new InvalidOperationException("send failed");
        });
        var service = CreateService(new FakeUiaReader(null), clipboard, copy);

        await Assert.ThrowsAsync<InvalidOperationException>(
            () => service.CaptureAsync(simulateCopy: true, CancellationToken.None));
        Assert.Equal("external clipboard change", clipboard.Text);
        Assert.Equal(0, clipboard.RestoreCount);
    }

    [Fact]
    public async Task Snapshot_sequence_is_coherent_without_second_baseline_read()
    {
        var clipboard = new FakeClipboard("original", 10);
        var copy = new FakeCopyCommand(() =>
        {
            Assert.Equal(0, clipboard.SequenceReadCount);
            clipboard.SetExternalText("copied");
        });
        var service = CreateService(new FakeUiaReader(null), clipboard, copy);

        var capture = await service.CaptureAsync(simulateCopy: true, CancellationToken.None);

        Assert.Equal("copied", capture!.Text);
        Assert.Equal("copied", clipboard.Text);
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
        public int CaptureCount { get; private set; }
        public int SequenceReadCount { get; private set; }
        public int ReadsOutsideSnapshot { get; private set; }
        private int _activeSnapshots;

        public uint GetSequenceNumber()
        {
            SequenceReadCount++;
            return sequenceNumber;
        }

        public IClipboardSnapshot CaptureSnapshot()
        {
            CaptureCount++;
            _activeSnapshots++;
            return new Snapshot(sequenceNumber, Text, () => _activeSnapshots--);
        }

        public string? ReadUnicodeText()
        {
            ReadCount++;
            if (_activeSnapshots == 0)
                ReadsOutsideSnapshot++;
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

        private sealed class Snapshot(uint sequenceNumber, string? text, Action onDispose) : IClipboardSnapshot
        {
            public uint SequenceNumber { get; } = sequenceNumber;
            public string? Text { get; } = text;
            public void Dispose() => onDispose();
        }
    }
}
