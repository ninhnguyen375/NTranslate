using NTranslate.Core.Configuration;
using NTranslate.Core.Settings;

namespace NTranslate.Core.Tests.Settings;

public sealed class SettingsDraftTests
{
    [Fact]
    public void DraftCopiesEveryExistingConfigFieldAndKeepsKeySeparate()
    {
        var config = AppConfig.Default;

        var draft = SettingsDraft.From(config, "secret");
        var rebuilt = draft.ToAppConfig(config);

        Assert.Equal(ConfigJson.Serialize(config), ConfigJson.Serialize(rebuilt));
        Assert.NotSame(config.Languages, rebuilt.Languages);
        Assert.NotSame(config.TargetLanguages, rebuilt.TargetLanguages);
        Assert.Equal("secret", draft.ApiKey);
        Assert.DoesNotContain("apiKey", System.Text.Json.JsonSerializer.Serialize(rebuilt), StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void RevertRestoresDeepCopiesOfListsAndNestedValues()
    {
        var config = AppConfig.Default with
        {
            Languages = ["Auto detect", "English", "French"],
            TargetLanguages = ["English", "French"]
        };
        var draft = SettingsDraft.From(config, "old-key");
        draft.Languages.Add("German");
        draft.TargetLanguages.Clear();
        draft.ApiKey = "new-key";
        draft.HotkeyKey = "Q";

        draft.Revert(config, "old-key");

        Assert.Equal(config.Languages, draft.Languages);
        Assert.Equal(config.TargetLanguages, draft.TargetLanguages);
        Assert.Equal("old-key", draft.ApiKey);
        Assert.Equal(config.Hotkey.Key, draft.HotkeyKey);
        Assert.NotSame(config.Languages, draft.Languages);
        Assert.NotSame(config.TargetLanguages, draft.TargetLanguages);
    }

    [Fact]
    public void ValidationCoversPromptsLanguagesUrlsHotkeyRateDimensionsAndCustomPath()
    {
        var draft = SettingsDraft.From(AppConfig.Default, string.Empty);
        draft.ApiBaseUrl = "http://example.test/v1/chat/completions";
        draft.ApiSpeechUrl = "not-a-url";
        draft.SystemPrompt = " ";
        draft.LearnPrompt = " ";
        draft.SentenceLearnPrompt = " ";
        draft.GrammarPrompt = " ";
        draft.SourceLang = "French";
        draft.TargetLang = "German";
        draft.NativeLang = "Spanish";
        draft.HotkeyKey = "1";
        draft.HotkeyOption = false;
        draft.HotkeyControl = false;
        draft.HotkeyShift = false;
        draft.SpeechRate = 2;
        draft.UiWidth = 0;
        draft.UiHeight = -1;
        draft.HistoryDirectory = "relative";

        var fields = draft.Validate().Select(issue => issue.Field).ToHashSet();

        Assert.Subset(fields, new HashSet<string>
        {
            "ApiBaseUrl", "ApiSpeechUrl", "SystemPrompt", "LearnPrompt", "SentenceLearnPrompt", "GrammarPrompt",
            "SourceLang", "TargetLang", "NativeLang", "Hotkey.Key", "Hotkey.Modifiers", "SpeechRate",
            "Ui.Width", "Ui.Height", "HistoryDirectory"
        });
    }
}
