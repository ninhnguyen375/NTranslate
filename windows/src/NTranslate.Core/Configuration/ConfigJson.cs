using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace NTranslate.Core.Configuration;

public sealed record LegacyConfigParseResult(AppConfig Config, string? LegacyApiKey, bool RequiresRewrite);

public static class ConfigJson
{
    private const string DefaultResourceName = "NTranslate.Core.config.json.example";

    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true,
        AllowTrailingCommas = false
    };

    private static readonly Lazy<JsonObject> DefaultJson = new(ReadDefaultJson);

    public static string Serialize(AppConfig config) => JsonSerializer.Serialize(config, Options);

    public static LegacyConfigParseResult Parse(string json)
    {
        var input = JsonNode.Parse(json, documentOptions: new() { AllowTrailingCommas = false }) as JsonObject
            ?? throw new JsonException("Configuration root must be an object.");
        var hasLegacyKey = RemoveProperty(input, "apiKey", out var key);
        var legacyKey = key is JsonValue value && value.TryGetValue<string>(out var text) ? text.Trim() : null;
        var merged = (JsonObject)DefaultJson.Value.DeepClone();
        Merge(merged, input);
        var config = merged.Deserialize<AppConfig>(Options)?.WithDerivedSpeechUrl()
            ?? throw new JsonException("Configuration could not be parsed.");
        return new(config, string.IsNullOrWhiteSpace(legacyKey) ? null : legacyKey, hasLegacyKey);
    }

    internal static AppConfig LoadDefault() =>
        DefaultJson.Value.Deserialize<AppConfig>(Options)
        ?? throw new JsonException("Embedded default configuration could not be parsed.");

    private static JsonObject ReadDefaultJson()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(DefaultResourceName)
            ?? throw new InvalidOperationException($"Missing embedded resource {DefaultResourceName}.");
        return JsonNode.Parse(stream, documentOptions: new() { AllowTrailingCommas = false }) as JsonObject
            ?? throw new JsonException("Embedded default configuration root must be an object.");
    }

    private static void Merge(JsonObject target, JsonObject source)
    {
        foreach (var property in source.ToArray())
        {
            var targetName = FindPropertyName(target, property.Key) ?? property.Key;
            if (property.Value is JsonObject sourceObject && target[targetName] is JsonObject targetObject)
                Merge(targetObject, sourceObject);
            else
                target[targetName] = property.Value?.DeepClone();
        }
    }

    private static bool RemoveProperty(JsonObject json, string name, out JsonNode? value)
    {
        var propertyName = FindPropertyName(json, name);
        if (propertyName is null)
        {
            value = null;
            return false;
        }

        value = json[propertyName]?.DeepClone();
        return json.Remove(propertyName);
    }

    private static string? FindPropertyName(JsonObject json, string name) =>
        json.Select(property => property.Key)
            .FirstOrDefault(key => string.Equals(key, name, StringComparison.OrdinalIgnoreCase));
}
