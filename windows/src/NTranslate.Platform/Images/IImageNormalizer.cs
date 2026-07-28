namespace NTranslate.Platform.Images;

public sealed record NormalizedImage(ReadOnlyMemory<byte> PngData, uint PixelWidth, uint PixelHeight);

public interface IImageNormalizer
{
    Task<NormalizedImage> NormalizePngAsync(Stream source, CancellationToken cancellationToken);
}
