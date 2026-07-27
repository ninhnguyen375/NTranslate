using System.Runtime.InteropServices;

namespace NTranslate.Platform.Input;

public sealed class SendInputCopyCommand : ISimulatedCopyCommand
{
    private const uint InputKeyboard = 1;
    private const uint KeyEventFKeyUp = 2;

    public void SendCopy()
    {
        var inputs = CreateCopyInputs().Select(input => (NativeInput)input).ToArray();
        if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<NativeInput>()) != inputs.Length)
            throw new InvalidOperationException("SendInput did not send all copy events.");
    }

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
