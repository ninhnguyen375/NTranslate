using System.Runtime.InteropServices.WindowsRuntime;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace NTranslate.Platform.Images;

public sealed class WindowsImageNormalizer : IImageNormalizer
{
    private const ulong MaximumDecodedBytes = 100UL * 1024 * 1024;
    private const long MaximumEncodedBytes = 10L * 1024 * 1024;

    public async Task<NormalizedImage> NormalizePngAsync(Stream source, CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(source);
        cancellationToken.ThrowIfCancellationRequested();

        try
        {
            using var input = source.AsRandomAccessStream();
            var decoder = await BitmapDecoder.CreateAsync(input).AsTask(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            ValidateDecodedSize(decoder.PixelWidth, decoder.PixelHeight);
            var pixels = await decoder.GetPixelDataAsync(
                    BitmapPixelFormat.Bgra8,
                    BitmapAlphaMode.Premultiplied,
                    new BitmapTransform(),
                    ExifOrientationMode.RespectExifOrientation,
                    ColorManagementMode.ColorManageToSRgb)
                .AsTask(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            using var output = new InMemoryRandomAccessStream();
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, output).AsTask(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            encoder.SetPixelData(
                BitmapPixelFormat.Bgra8,
                BitmapAlphaMode.Premultiplied,
                decoder.PixelWidth,
                decoder.PixelHeight,
                decoder.DpiX,
                decoder.DpiY,
                pixels.DetachPixelData());
            await encoder.FlushAsync().AsTask(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();

            ValidateEncodedSize((long)output.Size);
            output.Seek(0);
            var png = new byte[(int)output.Size];
            using var reader = new DataReader(output);
            await reader.LoadAsync((uint)output.Size).AsTask(cancellationToken);
            cancellationToken.ThrowIfCancellationRequested();
            reader.ReadBytes(png);
            return new NormalizedImage(png, decoder.PixelWidth, decoder.PixelHeight);
        }
        catch (OperationCanceledException)
        {
            throw;
        }
        catch (InvalidDataException)
        {
            throw;
        }
        catch (Exception exception)
        {
            throw new InvalidDataException("Image data is not a supported raster image.", exception);
        }
    }

    internal static void ValidateDecodedSize(uint width, uint height)
    {
        if ((ulong)width * height > MaximumDecodedBytes / 4)
            throw new InvalidDataException("Decoded image exceeds 100 MiB.");
    }

    internal static void ValidateEncodedSize(long length)
    {
        if (length > MaximumEncodedBytes)
            throw new InvalidDataException("Normalized PNG exceeds 10 MiB.");
    }
}
