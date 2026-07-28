namespace NTranslate.Core.Translation;

public static class ImageSearchPolicy
{
    public static string ResolveQuery(string? generatedQuery, string fallbackText) =>
        string.IsNullOrWhiteSpace(generatedQuery) ? fallbackText.Trim() : generatedQuery.Trim();

    public static Uri CreateGoogleImagesUri(string query) =>
        new($"https://www.google.com/search?tbm=isch&q={Uri.EscapeDataString(query)}");
}
