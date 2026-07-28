using NTranslate.Core.Translation;

namespace NTranslate.Core.Tests.Translation;

public sealed class TranslationContractsTests
{
    [Fact]
    public void ContractsPreserveOperationInputs()
    {
        var text = new TextTranslationRequest("hello", "English", "Vietnamese", TranslationMode.Learn);
        var png = new byte[] { 1, 2, 3 };
        var image = new ImageTranslationRequest(png, "English");
        var result = new TranslationResult("xin chào");

        Assert.Equal(TranslationMode.Learn, text.Mode);
        Assert.Equal("hello", text.Text);
        Assert.Equal(png, image.PngData.ToArray());
        Assert.Equal("xin chào", result.Text);
    }
}
