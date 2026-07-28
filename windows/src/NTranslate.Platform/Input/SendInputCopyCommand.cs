using System.Runtime.InteropServices;

namespace NTranslate.Platform.Input;

public sealed class SendInputCopyCommand : ISimulatedCopyCommand
{
    private const uint InputKeyboard = 1;
    private const uint KeyEventFKeyUp = 2;

    public void SendCopy() => SendCopy(Send, Marshal.GetLastWin32Error);

    internal static void SendCopy(Func<CopyInput[], uint> send, Func<int> getLastError)
    {
        var inputs = CreateCopyInputs();
        var sent = send(inputs);
        if (sent == inputs.Length)
            return;

        var failure = CreateFailureMessage(sent, sent == 0 ? getLastError() : 0);
        var releases = KeysLeftDown(inputs, sent).Select(key => new CopyInput(key, true)).ToArray();
        if (releases.Length > 0)
        {
            try { _ = send(releases); }
            catch { }
        }
        throw new InvalidOperationException(failure);
    }

    private static ushort[] KeysLeftDown(CopyInput[] inputs, uint sent)
    {
        List<ushort> down = [];
        foreach (var input in inputs.Take((int)Math.Min(sent, (uint)inputs.Length)))
        {
            if (input.KeyUp)
                down.Remove(input.VirtualKey);
            else if (!down.Contains(input.VirtualKey))
                down.Add(input.VirtualKey);
        }
        down.Reverse();
        return [.. down];
    }

    private static uint Send(CopyInput[] inputs)
    {
        var nativeInputs = inputs.Select(input => (NativeInput)input).ToArray();
        return SendInput((uint)nativeInputs.Length, nativeInputs, Marshal.SizeOf<NativeInput>());
    }

    internal static string CreateFailureMessage(uint sent, int win32Error) => sent == 0
        ? $"SendInput sent 0 of 4 copy events (Win32 error {win32Error})."
        : $"SendInput sent {sent} of 4 copy events.";

    internal static CopyInput[] CreateCopyInputs() =>
    [
        new(0x11, false),
        new(0x43, false),
        new(0x43, true),
        new(0x11, true)
    ];

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint inputCount, [In] NativeInput[] inputs, int size);

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeInput
    {
        public uint Type;
        public NativeInputUnion Data;

        public static implicit operator NativeInput(CopyInput input) => new()
        {
            Type = InputKeyboard,
            Data = new NativeInputUnion
            {
                Keyboard = new KeyboardInput { VirtualKey = input.VirtualKey, Flags = input.KeyUp ? KeyEventFKeyUp : 0 }
            }
        };
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct NativeInputUnion
    {
        [FieldOffset(0)] public KeyboardInput Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort VirtualKey;
        public ushort ScanCode;
        public uint Flags;
        public uint Time;
        public nint ExtraInfo;
    }
}

internal readonly record struct CopyInput(ushort VirtualKey, bool KeyUp);
