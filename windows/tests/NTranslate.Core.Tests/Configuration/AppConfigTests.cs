using System.Text.Json;
using NTranslate.Core.Configuration;

namespace NTranslate.Core.Tests.Configuration;

public sealed class AppConfigTests
{
    [Fact]
    public void DefaultsMatchSecretFreeExample()
    {
        var config = AppConfig.Default;

        Assert.Equal("http://localhost:20128/v1/chat/completions", config.ApiBaseUrl);
        Assert.Equal("http://localhost:20128/v1/audio/speech", config.ApiSpeechUrl);
        Assert.Equal("9r-gemini-low", config.Model);
        Assert.Equal(["Auto detect", "English", "Vietnamese", "Chinese"], config.Languages);
        Assert.Equal(["English", "Vietnamese"], config.TargetLanguages);
        Assert.Equal(5000, config.MaxTranslateLength);
        Assert.Equal(new("D", true, false, false, false), config.Hotkey);
        Assert.Equal(new(720, 320, false, false), config.Ui);
        Assert.DoesNotContain("apiKey", ConfigJson.Serialize(config), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void DefaultsMatchEveryNonSecretExampleValue()
    {
        var example = File.ReadAllText(FindRepositoryFile("config.json.example"));

        Assert.Equal(ConfigJson.Serialize(ConfigJson.Parse(example).Config), ConfigJson.Serialize(AppConfig.Default));
        Assert.DoesNotContain("apiKey", ConfigJson.Serialize(AppConfig.Default), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void MissingNestedFieldsUseDefaults()
    {
        var config = ConfigJson.Parse("""
            {
              "hotkey": { "key": "Q" },
              "ui": { "width": 900 }
            }
            """).Config;

        Assert.Equal(AppConfig.Default.Hotkey with { Key = "Q" }, config.Hotkey);
        Assert.Equal(AppConfig.Default.Ui with { Width = 900 }, config.Ui);
    }

    [Fact]
    public void LegacyKeyIsExtractedButNeverSerialized()
    {
        var json = """{"apiBaseURL":"http://localhost/v1/chat/completions","apiKey":"legacy-secret"}""";
        var parsed = ConfigJson.Parse(json);

        Assert.Equal("legacy-secret", parsed.LegacyApiKey);
        Assert.True(parsed.RequiresRewrite);
        Assert.DoesNotContain("apiKey", ConfigJson.Serialize(parsed.Config), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ValidationRejectsUnsafeOrEmptyValues()
    {
        var config = AppConfig.Default with
        {
            ApiBaseUrl = "file:///tmp/key",
            Model = " ",
            MaxTranslateLength = 0,
            Hotkey = new("1", false, false, false, false),
            Ui = new(0, -1, false, false)
        };

        Assert.Equal(
            ["ApiBaseUrl", "Model", "MaxTranslateLength", "Hotkey.Key", "Hotkey.Modifiers", "Ui.Width", "Ui.Height"],
            config.Validate().Select(issue => issue.Field));
    }

    [Fact]
    public void ValidationRejectsDuplicateAndUnknownLanguages()
    {
        var config = AppConfig.Default with
        {
            Languages = ["English", "english"],
            TargetLanguages = ["Vietnamese", "Vietnamese"],
            SourceLang = "French",
            TargetLang = "German",
            NativeLang = "Spanish"
        };

        Assert.Equal(
            ["Languages", "TargetLanguages", "SourceLang", "TargetLang", "NativeLang"],
            config.Validate().Select(issue => issue.Field));
    }

    [Fact]
    public void MissingSpeechUrlIsDerivedAndUnknownFieldsAreIgnored()
    {
        var parsed = ConfigJson.Parse("""
            {
              "apiBaseURL": "https://example.test/custom/chat/completions",
              "apiSpeechURL": null,
              "MODEL": "custom-model",
              "futureField": true
            }
            """);

        Assert.Equal("https://example.test/custom/audio/speech", parsed.Config.ApiSpeechUrl);
        Assert.Equal("custom-model", parsed.Config.Model);
        Assert.False(parsed.RequiresRewrite);
    }

    [Fact]
    public void SerializationIsDeterministicCamelCaseAndSecretFree()
    {
        var first = ConfigJson.Serialize(AppConfig.Default);
        var second = ConfigJson.Serialize(AppConfig.Default);

        Assert.Equal(first, second);
        Assert.Contains("\"apiBaseUrl\"", first, StringComparison.Ordinal);
        Assert.DoesNotContain("ApiBaseUrl", first, StringComparison.Ordinal);
        Assert.DoesNotContain("apiKey", first, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("legacyApiKey", first, StringComparison.OrdinalIgnoreCase);
        using var document = JsonDocument.Parse(first);
        Assert.Equal(JsonValueKind.Object, document.RootElement.ValueKind);
    }

    [Fact]
    public void TrailingCommasAreRejected() =>
        Assert.ThrowsAny<JsonException>(() => ConfigJson.Parse("""{"model":"x",}"""));

    private static string FindRepositoryFile(string name)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var path = Path.Combine(directory.FullName, name);
            if (Directory.Exists(Path.Combine(directory.FullName, ".git")) && File.Exists(path))
                return path;
            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException($"Repository root not found for {name}.");
    }
}
