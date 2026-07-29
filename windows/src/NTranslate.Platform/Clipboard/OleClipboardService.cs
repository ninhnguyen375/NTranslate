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
        object dataObject = null!;
        ClipboardHResultRetry.Run(() => OleGetClipboard(out dataObject));
        return new OleClipboardSnapshot(GetClipboardSequenceNumber(), dataObject);
    });

    public string? ReadUnicodeText() => StaClipboardThread.Invoke(() => WpfClipboard.ContainsText(TextDataFormat.UnicodeText)
        ? WpfClipboard.GetText(TextDataFormat.UnicodeText)
        : null);

    public byte[]? ReadImagePng() => StaClipboardThread.Invoke(() =>
    {
        if (!WpfClipboard.ContainsImage())
            return null;

        var image = WpfClipboard.GetImage();
        if (image is null)
            return null;

        var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
        encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(image));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    });

    public void WriteUnicodeText(string text) => WriteUnicodeTextAndGetSequence(text);

    internal uint WriteUnicodeTextAndGetSequence(string text)
    {
        ArgumentNullException.ThrowIfNull(text);
        return StaClipboardThread.Invoke(() =>
        {
            WpfClipboard.SetText(text, TextDataFormat.UnicodeText);
            return GetClipboardSequenceNumber();
        });
    }

    public bool RestoreIfUnchanged(IClipboardSnapshot snapshot, uint copiedSequenceNumber) =>
        RestoreIfUnchangedAndGetSequence(snapshot, copiedSequenceNumber).HasValue;

    internal uint? RestoreIfUnchangedAndGetSequence(IClipboardSnapshot snapshot, uint? ownedSequence) =>
        StaClipboardThread.Invoke<uint?>(() =>
        {
            if (!ClipboardRestorePolicy.ShouldRestore(GetClipboardSequenceNumber(), ownedSequence))
                return null;

            var oleSnapshot = snapshot as OleClipboardSnapshot
                ?? throw new ArgumentException("Snapshot must come from OleClipboardService.", nameof(snapshot));
            SetClipboard(oleSnapshot.DataObject);
            FlushClipboard();
            return GetClipboardSequenceNumber();
        });

    [DllImport("ole32.dll")]
    private static extern int OleGetClipboard([MarshalAs(UnmanagedType.Interface)] out object dataObject);

    [DllImport("ole32.dll")]
    private static extern int OleSetClipboard([MarshalAs(UnmanagedType.Interface)] object dataObject);

    [DllImport("ole32.dll")]
    private static extern int OleFlushClipboard();

    private static void SetClipboard(object dataObject) => ClipboardHResultRetry.Run(
        () => IgnoreClipboardCloseFailure(OleSetClipboard(dataObject)));

    private static void FlushClipboard() => ClipboardHResultRetry.Run(
        () => IgnoreClipboardCloseFailure(OleFlushClipboard()));

    private static int IgnoreClipboardCloseFailure(int hResult) =>
        hResult == unchecked((int)0x800401D4) ? 0 : hResult;

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

internal static class ClipboardHResultRetry
{
    private const int ClipboardCannotOpen = unchecked((int)0x800401D0);
    private const int MaxAttempts = 3;
    private static readonly TimeSpan RetryDelay = TimeSpan.FromMilliseconds(10);

    public static void Run(Func<int> operation) => Run(operation, () => Thread.Sleep(RetryDelay));

    internal static void Run(Func<int> operation, Action delay)
    {
        for (var attempt = 1; ; attempt++)
        {
            var hResult = operation();
            if (hResult >= 0)
                return;
            if (hResult != ClipboardCannotOpen || attempt == MaxAttempts)
                Marshal.ThrowExceptionForHR(hResult);
            delay();
        }
    }
}
