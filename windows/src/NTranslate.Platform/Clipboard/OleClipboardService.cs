using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Threading;
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

    private static void SetClipboard(object dataObject) => IgnoreClipboardCloseFailure(() => OleSetClipboard(dataObject));

    private static void FlushClipboard() => IgnoreClipboardCloseFailure(OleFlushClipboard);

    private static void IgnoreClipboardCloseFailure(Func<int> operation)
    {
        var hResult = operation();
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
    private static readonly Dispatcher Dispatcher = Start();

    public static T Invoke<T>(Func<T> operation) => Dispatcher.Invoke(operation);

    public static void Invoke(Action operation) => Dispatcher.Invoke(operation);

    private static Dispatcher Start()
    {
        var ready = new TaskCompletionSource<Dispatcher>(TaskCreationOptions.RunContinuationsAsynchronously);
        var thread = new Thread(() =>
        {
            var dispatcher = Dispatcher.CurrentDispatcher;
            ready.SetResult(dispatcher);
            Dispatcher.Run();
        }) { IsBackground = true, Name = "NTranslate clipboard STA" };
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        return ready.Task.GetAwaiter().GetResult();
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
