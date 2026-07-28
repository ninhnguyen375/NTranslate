using System.Xml.Linq;

namespace NTranslate.App.Tests.Popup;

public sealed class TranslationWindowXamlTests
{
    private static readonly string XamlPath = Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml");

    [Fact]
    public void Popup_HasNamedBoundAccessibleControls()
    {
        var document = XDocument.Load(XamlPath);
        var names = document.Descendants().Attributes().Where(a => a.Name.LocalName == "Name").Select(a => a.Value).ToHashSet();
        Assert.Contains("SourceTextBox", names);
        Assert.Contains("ResultTextBox", names);
        Assert.Contains("SourceLanguageBox", names);
        Assert.Contains("TargetLanguageBox", names);
        Assert.Contains("SwapButton", names);
        Assert.Contains("TranslateButton", names);
        Assert.Contains("CopyButton", names);
        Assert.Contains("PinButton", names);
        Assert.Contains("CloseButton", names);
        Assert.DoesNotContain(document.Descendants(), element =>
            names.Contains(element.Attributes().FirstOrDefault(a => a.Name.LocalName == "Name")?.Value ?? "") &&
            element.Name.LocalName is "Button" or "ComboBox" or "TextBox" &&
            element.Attributes().All(a => a.Name.LocalName != "AutomationProperties.Name"));
    }

    [Fact]
    public void Result_IsPoliteLiveRegion()
    {
        var result = FindNamed("ResultTextBox");
        Assert.Equal("Polite", Attribute(result, "AutomationProperties.LiveSetting"));
    }

    [Fact]
    public void Popup_DefinesRequiredKeyboardAccelerators()
    {
        var document = XDocument.Load(XamlPath);
        var accelerators = document.Descendants().Where(e => e.Name.LocalName == "KeyboardAccelerator")
            .Select(e => (Key: Attribute(e, "Key"), Modifiers: Attribute(e, "Modifiers"))).ToHashSet();
        Assert.Contains(("Escape", "None"), accelerators);
        Assert.Contains(("Enter", "Control"), accelerators);
        Assert.Contains(("C", "Control,Shift"), accelerators);
    }

    private static XElement FindNamed(string name) => XDocument.Load(XamlPath).Descendants()
        .Single(e => e.Attributes().Any(a => a.Name.LocalName == "Name" && a.Value == name));

    private static string? Attribute(XElement element, string localName) =>
        element.Attributes().SingleOrDefault(a => a.Name.LocalName == localName)?.Value;
}
