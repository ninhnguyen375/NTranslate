namespace NTranslate.Core.Speech;

public static class SpeechRatePolicy
{
    public static double Normalize(double rate)
    {
        var tenths = rate * 10;
        return double.IsFinite(rate) && rate is >= 0.5 and <= 1.5 &&
               Math.Abs(tenths - Math.Round(tenths)) < 1e-9
            ? Math.Round(tenths) / 10
            : 1.0;
    }
}
