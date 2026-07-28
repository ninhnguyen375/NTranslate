using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Xml;
using NTranslate.Core.Updates;

namespace NTranslate.Platform.Updates;

public sealed record VerifiedMsixPackage(string Path, string IdentityName, string Publisher, SemanticVersion Version, string Architecture);

public interface IMsixPackageVerifier
{
    Task<VerifiedMsixPackage> VerifyAsync(string packagePath, CancellationToken token);
}

public sealed class MsixVerificationException(string message, Exception? innerException = null) : Exception(message, innerException);

public sealed class MsixPackageVerifier(Func<string, bool>? verifySignature = null) : IMsixPackageVerifier
{
    public const string RequiredIdentityName = "NinhNguyen375.NTranslate";
    public const string RequiredPublisher = "CN=Ninh Nguyen";
    public const string RequiredArchitecture = "x64";
    private const long MaximumManifestBytes = 1024 * 1024;
    private readonly Func<string, bool> _verifySignature = verifySignature ?? WinTrustVerifier.Verify;

    public Task<VerifiedMsixPackage> VerifyAsync(string packagePath, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        ArgumentException.ThrowIfNullOrWhiteSpace(packagePath);
        var fullPath = Path.GetFullPath(packagePath);
        if (!File.Exists(fullPath))
            throw new MsixVerificationException("MSIX package does not exist.");
        if (!string.Equals(Path.GetExtension(fullPath), ".msix", StringComparison.OrdinalIgnoreCase))
            throw new MsixVerificationException("Update package must use the .msix extension.");
        if ((File.GetAttributes(fullPath) & FileAttributes.ReparsePoint) != 0)
            throw new MsixVerificationException("MSIX package cannot be a reparse point.");
        if (!_verifySignature(fullPath))
            throw new MsixVerificationException("MSIX package signature is invalid.");

        try
        {
            using var archive = ZipFile.OpenRead(fullPath);
            var manifests = archive.Entries.Where(entry => string.Equals(entry.FullName, "AppxManifest.xml", StringComparison.OrdinalIgnoreCase)).ToArray();
            if (manifests.Length != 1 || manifests[0].Length > MaximumManifestBytes)
                throw new MsixVerificationException("MSIX package must contain one bounded root AppxManifest.xml.");

            using var bounded = new BoundedReadStream(manifests[0].Open(), MaximumManifestBytes);
            using var reader = XmlReader.Create(bounded, new XmlReaderSettings
            {
                DtdProcessing = DtdProcessing.Prohibit,
                XmlResolver = null,
                MaxCharactersInDocument = MaximumManifestBytes,
                IgnoreComments = true
            });
            var document = new XmlDocument { XmlResolver = null };
            document.Load(reader);
            var identity = document.DocumentElement?.ChildNodes.OfType<XmlElement>().SingleOrDefault(element => element.LocalName == "Identity")
                ?? throw new MsixVerificationException("MSIX manifest has no unique Identity.");
            var name = identity.GetAttribute("Name");
            var publisher = identity.GetAttribute("Publisher");
            var architecture = identity.GetAttribute("ProcessorArchitecture");
            var rawVersion = identity.GetAttribute("Version");
            if (!string.Equals(name, RequiredIdentityName, StringComparison.Ordinal) ||
                !string.Equals(publisher, RequiredPublisher, StringComparison.Ordinal) ||
                !string.Equals(architecture, RequiredArchitecture, StringComparison.OrdinalIgnoreCase) ||
                !TryParsePackageVersion(rawVersion, out var version))
                throw new MsixVerificationException("MSIX manifest identity does not match NTranslate policy.");

            return Task.FromResult(new VerifiedMsixPackage(fullPath, name, publisher, version, RequiredArchitecture));
        }
        catch (MsixVerificationException) { throw; }
        catch (OperationCanceledException) { throw; }
        catch (Exception exception) when (exception is InvalidDataException or IOException or XmlException or InvalidOperationException)
        {
            throw new MsixVerificationException("MSIX package content is invalid.", exception);
        }
    }

    private static bool TryParsePackageVersion(string value, out SemanticVersion version)
    {
        version = default;
        var parts = value.Split('.');
        return parts.Length == 4 && parts[3] == "0" && SemanticVersion.TryParse(string.Join('.', parts[..3]), out version);
    }

    private sealed class BoundedReadStream(Stream inner, long maximum) : Stream
    {
        private long _read;
        public override int Read(byte[] buffer, int offset, int count)
        {
            var read = inner.Read(buffer, offset, (int)Math.Min(count, maximum - _read + 1));
            _read += read;
            if (_read > maximum) throw new InvalidDataException("Manifest exceeds limit.");
            return read;
        }
        public override int Read(Span<byte> buffer)
        {
            var read = inner.Read(buffer[..Math.Min(buffer.Length, (int)Math.Min(int.MaxValue, maximum - _read + 1))]);
            _read += read;
            if (_read > maximum) throw new InvalidDataException("Manifest exceeds limit.");
            return read;
        }
        protected override void Dispose(bool disposing) { if (disposing) inner.Dispose(); base.Dispose(disposing); }
        public override bool CanRead => inner.CanRead;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
        public override void Flush() => throw new NotSupportedException();
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    }

    private static class WinTrustVerifier
    {
        private static readonly Guid Action = new("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

        public static bool Verify(string path)
        {
            if (!OperatingSystem.IsWindows()) return false;
            var fileInfo = new WinTrustFileInfo(path);
            var data = new WinTrustData(fileInfo);
            try { return WinVerifyTrust(IntPtr.Zero, Action, data) == 0; }
            finally { data.Dispose(); fileInfo.Dispose(); }
        }

        [DllImport("wintrust.dll", ExactSpelling = true, PreserveSig = true)]
        private static extern int WinVerifyTrust(IntPtr hwnd, [MarshalAs(UnmanagedType.LPStruct)] Guid actionId, WinTrustData data);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private sealed class WinTrustFileInfo : IDisposable
        {
            private readonly uint size = (uint)Marshal.SizeOf<WinTrustFileInfo>();
            private readonly IntPtr filePath = Marshal.StringToCoTaskMemUni(string.Empty);
            private readonly IntPtr fileHandle = IntPtr.Zero;
            private readonly IntPtr knownSubject = IntPtr.Zero;
            public WinTrustFileInfo(string path) { Marshal.FreeCoTaskMem(filePath); filePath = Marshal.StringToCoTaskMemUni(path); }
            public void Dispose() => Marshal.FreeCoTaskMem(filePath);
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private sealed class WinTrustData : IDisposable
        {
            private readonly uint size = (uint)Marshal.SizeOf<WinTrustData>();
            private readonly IntPtr policyCallbackData = IntPtr.Zero;
            private readonly IntPtr sipClientData = IntPtr.Zero;
            private readonly uint uiChoice = 2;
            private readonly uint revocationChecks = 0;
            private readonly uint unionChoice = 1;
            private readonly IntPtr fileInfo;
            private readonly uint stateAction = 0;
            private readonly IntPtr stateData = IntPtr.Zero;
            private readonly IntPtr urlReference = IntPtr.Zero;
            private readonly uint providerFlags = 0x00000040;
            private readonly uint uiContext = 0;
            public WinTrustData(WinTrustFileInfo info) { fileInfo = Marshal.AllocCoTaskMem(Marshal.SizeOf(info)); Marshal.StructureToPtr(info, fileInfo, false); }
            public void Dispose() => Marshal.FreeCoTaskMem(fileInfo);
        }
    }
}
