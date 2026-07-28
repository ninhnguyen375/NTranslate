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
        Assert.Contains("LearnButton", names);
        Assert.Contains("ImagesButton", names);
        Assert.Contains("SourceSpeechButton", names);
        Assert.Contains("ResultSpeechButton", names);
        Assert.Contains("ImageTranslateButton", names);
        Assert.Contains("ImagePreview", names);
        Assert.Contains("ProgressRing", names);
        Assert.Contains("PinButton", names);
        Assert.Contains("CloseButton", names);
        Assert.DoesNotContain(document.Descendants(), element =>
            names.Contains(element.Attributes().FirstOrDefault(a => a.Name.LocalName == "Name")?.Value ?? "") &&
            element.Name.LocalName is "Button" or "ComboBox" or "TextBox" &&
            element.Attributes().All(a => a.Name.LocalName != "AutomationProperties.Name"));
    }

    [Fact]
    public void Popup_HasExactBindingsAndDedicatedTitleDragSurface()
    {
        Assert.Equal("{x:Bind ViewModel.SourceText, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}", Attribute(FindNamed("SourceTextBox"), "Text"));
        Assert.Equal("{x:Bind ViewModel.ResultText, Mode=OneWay}", Attribute(FindNamed("ResultTextBox"), "Text"));
        Assert.Equal("True", Attribute(FindNamed("ResultTextBox"), "IsReadOnly"));
        Assert.Equal("{x:Bind ViewModel.TranslateCommand}", Attribute(FindNamed("TranslateButton"), "Command"));
        Assert.Equal("{x:Bind ViewModel.CopyCommand}", Attribute(FindNamed("CopyButton"), "Command"));
        Assert.Equal("LearnButton_Click", Attribute(FindNamed("LearnButton"), "Click"));
        Assert.Equal("ImagesButton_Click", Attribute(FindNamed("ImagesButton"), "Click"));
        Assert.Equal("SourceSpeechButton_Click", Attribute(FindNamed("SourceSpeechButton"), "Click"));
        Assert.Equal("ResultSpeechButton_Click", Attribute(FindNamed("ResultSpeechButton"), "Click"));
        Assert.Equal("ImageTranslateButton_Click", Attribute(FindNamed("ImageTranslateButton"), "Click"));
        Assert.Equal("{x:Bind ViewModel.CanSpeakSource, Mode=OneWay}", Attribute(FindNamed("SourceSpeechButton"), "IsEnabled"));
        Assert.Equal("{x:Bind ViewModel.CanSpeakResult, Mode=OneWay}", Attribute(FindNamed("ResultSpeechButton"), "IsEnabled"));
        Assert.Equal("Image preview", Attribute(FindNamed("ImagePreview"), "AutomationProperties.Name"));
        Assert.Equal("{x:Bind ViewModel.IsLoading, Mode=OneWay}", Attribute(FindNamed("ProgressRing"), "IsActive"));
        Assert.Equal("TitleDragRegion_PointerPressed", Attribute(FindNamed("TitleDragRegion"), "PointerPressed"));
        Assert.Equal("TitleDragRegion_PointerMoved", Attribute(FindNamed("TitleDragRegion"), "PointerMoved"));
        Assert.Equal("TitleDragRegion_PointerReleased", Attribute(FindNamed("TitleDragRegion"), "PointerReleased"));
        Assert.Null(Attribute(FindNamed("RootGrid"), "PointerMoved"));
    }

    [Fact]
    public void SourceEditorAndImagePreviewBindVisibilityToImageMode()
    {
        Assert.Equal("{x:Bind ViewModel.SourceEditorVisibility, Mode=OneWay}", Attribute(FindNamed("SourceTextBox"), "Visibility"));
        Assert.Equal("{x:Bind ViewModel.ImagePreviewVisibility, Mode=OneWay}", Attribute(FindNamed("ImagePreview"), "Visibility"));

        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        Assert.DoesNotContain("SourceTextBox.Visibility = Visibility.Collapsed", codeBehind, StringComparison.Ordinal);
        Assert.DoesNotContain("ImagePreview.Visibility = Visibility.Visible", codeBehind, StringComparison.Ordinal);
    }

    [Fact]
    public void Window_WiresClosingCancellation()
    {
        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        Assert.Contains("_appWindow.Closing += AppWindow_Closing", codeBehind, StringComparison.Ordinal);
        Assert.Contains("args.Cancel = true", codeBehind, StringComparison.Ordinal);
        Assert.Contains("_lifetimeCancellation.Cancel()", codeBehind, StringComparison.Ordinal);
        Assert.Contains("ViewModel.WindowChanged()", codeBehind, StringComparison.Ordinal);
    }

    [Fact]
    public void Result_IsPoliteLiveRegion()
    {
        var result = FindNamed("ResultTextBox");
        Assert.Equal("Polite", Attribute(result, "AutomationProperties.LiveSetting"));
    }

    [Fact]
    public void Status_HasDedicatedFullWidthWrappedPoliteLiveRow()
    {
        var status = FindNamed("StatusTextBlock");
        Assert.Equal("{x:Bind ViewModel.StatusMessage, Mode=OneWay}", Attribute(status, "Text"));
        Assert.Equal("Wrap", Attribute(status, "TextWrapping"));
        Assert.Equal("Polite", Attribute(status, "AutomationProperties.LiveSetting"));
        Assert.Equal("4", Attribute(status, "Grid.Row"));
        Assert.Null(Attribute(status, "Grid.Column"));

        var buttonPanel = FindNamed("ButtonPanel");
        Assert.Equal("5", Attribute(buttonPanel, "Grid.Row"));
        Assert.DoesNotContain(status, buttonPanel.Descendants());
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
        Assert.Contains(("L", "Control,Shift"), accelerators);
    }

    private static XElement FindNamed(string name) => XDocument.Load(XamlPath).Descendants()
        .Single(e => e.Attributes().Any(a => a.Name.LocalName == "Name" && a.Value == name));

    private static string? Attribute(XElement element, string localName) =>
        element.Attributes().SingleOrDefault(a => a.Name.LocalName == localName)?.Value;
}
