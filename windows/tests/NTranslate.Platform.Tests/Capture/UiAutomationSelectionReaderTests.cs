using NTranslate.Platform.Capture;

namespace NTranslate.Platform.Tests.Capture;

public sealed class UiAutomationSelectionReaderTests
{
    [Fact]
    public void JoinSelectionRanges_PreservesOrderAndSkipsEmptyRanges()
    {
        var result = UiAutomationSelectionReader.JoinSelectionRanges(["first", "", "second", "   ", "third"]);

        Assert.Equal("firstsecond   third", result);
    }

    [Fact]
    public void JoinSelectionRanges_ReturnsNullWhenNoRangeHasText()
    {
        Assert.Null(UiAutomationSelectionReader.JoinSelectionRanges(["", ""]));
    }
}
