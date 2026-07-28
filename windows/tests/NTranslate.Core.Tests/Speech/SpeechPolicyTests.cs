using NTranslate.Core.Configuration;
using NTranslate.Core.Speech;

namespace NTranslate.Core.Tests.Speech;

public sealed class SpeechPolicyTests
{
    [Theory]
    [InlineData("Vietnamese", "vi-model")]
    [InlineData("vietnamese", "vi-model")]
    [InlineData("Chinese", "zh-model")]
    [InlineData("English", "default-model")]
    public void ModelResolverMapsLanguage(string language, string expected)
    {
        var config = AppConfig.Default with
        {
            SpeechSourceModel = "default-model",
            SpeechSourceModelVietnamese = "vi-model",
            SpeechSourceModelChinese = "zh-model"
        };

        Assert.Equal(expected, SpeechModelResolver.Resolve(language, config));
    }

    [Theory]
    [InlineData(0.5)]
    [InlineData(0.6)]
    [InlineData(0.7)]
    [InlineData(0.8)]
    [InlineData(0.9)]
    [InlineData(1.0)]
    [InlineData(1.1)]
    [InlineData(1.2)]
    [InlineData(1.3)]
    [InlineData(1.4)]
    [InlineData(1.5)]
    public void RatePolicyAcceptsBoundedTenths(double rate) =>
        Assert.Equal(rate, SpeechRatePolicy.Normalize(rate), 10);

    [Theory]
    [InlineData(0.49)]
    [InlineData(0.54)]
    [InlineData(1.45)]
    [InlineData(1.51)]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    public void RatePolicyFallsBackForInvalidRate(double rate) =>
        Assert.Equal(1.0, SpeechRatePolicy.Normalize(rate), 10);
}
