using NTranslate.Core.Translation;

namespace NTranslate.Core.Tests.Translation;

public sealed class ImageSearchPolicyTests
{
    [Fact]
    public void ResolveQuery_prefers_nonblank_generated_query()
    {
        Assert.Equal("red panda", ImageSearchPolicy.ResolveQuery("  red panda  ", "fallback"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void ResolveQuery_falls_back_when_generated_query_is_missing(string? generatedQuery)
    {
        Assert.Equal("source text", ImageSearchPolicy.ResolveQuery(generatedQuery, "  source text  "));
    }

    [Fact]
    public void CreateGoogleImagesUri_escapes_unicode_query_and_selects_images()
    {
        var uri = ImageSearchPolicy.CreateGoogleImagesUri("mèo trắng");

        Assert.Equal("https", uri.Scheme);
        Assert.Equal("www.google.com", uri.Host);
        Assert.Equal("?tbm=isch&q=m%C3%A8o%20tr%E1%BA%AFng", uri.Query);
    }
}
