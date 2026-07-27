using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Windows;
using WpfClipboard = System.Windows.Clipboard;

namespace NTranslate.Platform.Clipboard;

public sealed class OleClipboardService : IClipboardService
{
    public uint GetSequenceNumber() => StaClipboardThread.Invoke(GetClipboardSequenceNumber);

    public IClipboardSnapshot CaptureSnapshot() => StaClipboardThread.Invoke(() =>
    {
        OleGetClipboard(out var dataObject).ThrowOnFailure();
        return new OleClipboardSnapshot(GetClipboardSequenceNumber(), dataObject);
    });

    public string? ReadUnicodeText() => StaClipboardThread.Invoke(() => WpfClipboard.ContainsText(TextDataFormat.UnicodeText)
        ? WpfClipboard.GetText(TextDataFormat.UnicodeText)
        : null);

    public void WriteUnicodeText(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        StaClipboardThread.Invoke(() => WpfClipboard.SetText(text, TextDataFormat.UnicodeText));
    }

    public bool RestoreIfUnchanged(IClipboardSnapshot snapshot, uint copiedSequenceNumber) => StaClipboardThread.Invoke(() =>
    {
        if (!ClipboardRestorePolicy.ShouldRestore(GetClipboardSequenceNumber(), copiedSequenceNumber))
            return false;

        var oleSnapshot = snapshot as OleClipboardSnapshot
            ?? throw new ArgumentException("Snapshot must come from OleClipboardService.", nameof(snapshot));
        SetClipboard(oleSnapshot.DataObject);
        FlushClipboard();
        return true;
    });

    [DllImport("ole32.dll")]
    private static extern int OleGetClipboard([MarshalAs(UnmanagedType.Interface)] out object dataObject);

    [DllImport("ole32.dll")]
    private static extern int OleSetClipboard([MarshalAs(UnmanagedType.Interface)] object dataObject);

    [DllImport("ole32.dll")]
    private static extern int OleFlushClipboard();

    private static void SetClipboard(object dataObject)
    {
        var hResult = OleSetClipboard(dataObject);
        if (hResult < 0 && hResult != unchecked((int)0x800401D4))
            Marshal.ThrowExceptionForHR(hResult);
    }

    private static void FlushClipboard()
    {
        var hResult = OleFlushClipboard();
        if (hResult < 0 && hResult != unchecked((int)0x800401D4))
            Marshal.ThrowExceptionForHR(hResult);
    }

    [DllImport("user32.dll")]
    private static extern uint GetClipboardSequenceNumber();

    private sealed class OleClipboardSnapshot(uint sequenceNumber, object dataObject) : IClipboardSnapshot
    {
        public uint SequenceNumber { get; } = sequenceNumber;
        public object DataObject { get; } = dataObject;
        public void Dispose() => StaClipboardThread.Invoke(() => Marshal.ReleaseComObject(DataObject));
    }
}

internal static class StaClipboardThread
{
    private static readonly BlockingCollection<Action> Queue = [];
    private static readonly Thread Thread = Start();

    public static T Invoke<T>(Func<T> operation)
    {
        var completion = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);
        Queue.Add(() =>
        {
            try { completion.SetResult(operation()); }
            catch (Exception exception) { completion.SetException(exception); }
        });
        return completion.Task.GetAwaiter().GetResult();
    }

    public static void Invoke(Action operation) => Invoke(() => { operation(); return true; });

    private static Thread Start()
    {
        var thread = new Thread(() =>
        {
            foreach (var operation in Queue.GetConsumingEnumerable())
                operation();
        }) { IsBackground = true, Name = "NTranslate clipboard STA" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return thread;
    }
}

internal static class HResultExtensions
{
    public static void ThrowOnFailure(this int hResult)
    {
        if (hResult < 0)
            Marshal.ThrowExceptionForHR(hResult);
    }
}
