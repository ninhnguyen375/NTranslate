using NTranslate.Platform.Images;

namespace NTranslate.Platform.Tests.Images;

public sealed class WindowsImageNormalizerTests
{
    [Fact]
    public async Task Normalizes_raster_to_png_with_original_dimensions()
    {
        await using var source = OpenFixture("one-pixel.bmp");

        var image = await new WindowsImageNormalizer().NormalizePngAsync(source, CancellationToken.None);

        Assert.Equal(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, image.PngData.Span[..8].ToArray());
        Assert.Equal(1U, image.PixelWidth);
        Assert.Equal(1U, image.PixelHeight);
    }

    [Fact]
    public async Task Rejects_invalid_raster()
    {
        await using var source = OpenFixture("invalid-raster.bin");

        await Assert.ThrowsAsync<InvalidDataException>(
            () => new WindowsImageNormalizer().NormalizePngAsync(source, CancellationToken.None));
    }

    [Fact]
    public void Rejects_decoded_dimensions_over_100_mib_without_overflow()
    {
        Assert.Throws<InvalidDataException>(() => WindowsImageNormalizer.ValidateDecodedSize(uint.MaxValue, uint.MaxValue));
        Assert.Throws<InvalidDataException>(() => WindowsImageNormalizer.ValidateDecodedSize(5_121, 5_121));
        WindowsImageNormalizer.ValidateDecodedSize(5_120, 5_120);
    }

    [Fact]
    public void Rejects_encoded_png_over_10_mib()
    {
        Assert.Throws<InvalidDataException>(() => WindowsImageNormalizer.ValidateEncodedSize((10L * 1024 * 1024) + 1));
        WindowsImageNormalizer.ValidateEncodedSize(10L * 1024 * 1024);
    }

    [Fact]
    public async Task Honors_pre_cancellation()
    {
        await using var source = OpenFixture("one-pixel.bmp");
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => new WindowsImageNormalizer().NormalizePngAsync(source, cancellation.Token));
    }

    private static FileStream OpenFixture(string name)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var path = Path.Combine(directory.FullName, "shared", "contracts", "fixtures", "images", name);
            if (File.Exists(path))
                return File.OpenRead(path);
            directory = directory.Parent;
        }

        throw new FileNotFoundException($"Image fixture not found: {name}.");
    }
}
