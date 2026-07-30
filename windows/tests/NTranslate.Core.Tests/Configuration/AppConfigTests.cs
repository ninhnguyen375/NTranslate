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
        Assert.Equal(["Auto detect", "English", "Vietnamese", "Chinese", "Japanese"], config.Languages);
        Assert.Equal("edge-tts/ja-JP-NanamiNeural", config.SpeechSourceModelJapanese);
        Assert.Equal(["English", "Vietnamese"], config.TargetLanguages);
        Assert.Equal(5000, config.MaxTranslateLength);
        Assert.Equal(1d, config.SpeechRate);
        Assert.False(config.StartWithWindows);
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
    public void ExplicitNullCollectionsAndNestedObjectsUseDefaults()
    {
        var config = ConfigJson.Parse("""
            {
              "languages": null,
              "targetLanguages": null,
              "hotkey": null,
              "ui": null
            }
            """).Config;

        Assert.Equal(AppConfig.Default.Languages, config.Languages);
        Assert.Equal(AppConfig.Default.TargetLanguages, config.TargetLanguages);
        Assert.Equal(AppConfig.Default.Hotkey, config.Hotkey);
        Assert.Equal(AppConfig.Default.Ui, config.Ui);
        Assert.Empty(config.Validate());
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

    [Theory]
    [InlineData(0.49)]
    [InlineData(1.51)]
    public void ValidationRejectsSpeechRateOutsideSupportedRange(double rate)
    {
        var config = AppConfig.Default with { SpeechRate = rate };

        Assert.Equal(["SpeechRate"], config.Validate().Select(issue => issue.Field));
    }

    [Theory]
    [InlineData("[\"English\",\"Vietnamese\"]", "English,Vietnamese,Japanese")]
    [InlineData("[\"English\",\"jApAnEsE\",\"Vietnamese\"]", "English,jApAnEsE,Vietnamese")]
    public void LegacyConfigMigratesJapaneseWithoutDuplicate(string languages, string expected)
    {
        var config = ConfigJson.Parse($$"""{"languages":{{languages}},"speechSourceModelJapanese":" "}""").Config;

        Assert.Equal(expected.Split(','), config.Languages);
        Assert.Equal("edge-tts/ja-JP-NanamiNeural", config.SpeechSourceModelJapanese);
        Assert.Equal(ConfigJson.Serialize(config), ConfigJson.Serialize(ConfigJson.Parse(ConfigJson.Serialize(config)).Config));
    }

    [Fact]
    public void OldConfigUsesIntegratedDefaults()
    {
        var config = ConfigJson.Parse("{}").Config;

        Assert.Equal(1d, config.SpeechRate);
        Assert.False(config.StartWithWindows);
        Assert.DoesNotContain("apiKey", ConfigJson.Serialize(config), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void ValidationRejectsNonLoopbackHttpEndpoints()
    {
        var config = AppConfig.Default with
        {
            ApiBaseUrl = "http://example.test/v1/chat/completions",
            ApiSpeechUrl = "http://192.0.2.1/v1/audio/speech"
        };

        Assert.Equal(["ApiBaseUrl", "ApiSpeechUrl"], config.Validate().Select(issue => issue.Field));
    }

    [Fact]
    public void ValidationRejectsWindowsOnlyHotkeyValues()
    {
        var config = AppConfig.Default with { Hotkey = new("Đ", false, true, false, false) };

        Assert.Equal(["Hotkey.Key", "Hotkey.Command"], config.Validate().Select(issue => issue.Field));
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
            if (File.Exists(path) && (Directory.Exists(Path.Combine(directory.FullName, ".git")) || File.Exists(Path.Combine(directory.FullName, ".git"))))
                return path;
            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException($"Repository root not found for {name}.");
    }
}
