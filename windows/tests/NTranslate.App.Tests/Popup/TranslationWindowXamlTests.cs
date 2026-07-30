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
        Assert.Equal("{x:Bind ViewModel.CanUseSourceSpeech, Mode=OneWay}", Attribute(FindNamed("SourceSpeechButton"), "IsEnabled"));
        Assert.Equal("{x:Bind ViewModel.CanUseResultSpeech, Mode=OneWay}", Attribute(FindNamed("ResultSpeechButton"), "IsEnabled"));
        Assert.Equal("SourceSpeechIcon", Attribute(FindNamed("SourceSpeechButton").Descendants().Single(element => element.Name.LocalName == "SymbolIcon"), "Name"));
        Assert.Equal("ResultSpeechIcon", Attribute(FindNamed("ResultSpeechButton").Descendants().Single(element => element.Name.LocalName == "SymbolIcon"), "Name"));
        Assert.Equal("Image preview", Attribute(FindNamed("ImagePreview"), "AutomationProperties.Name"));
        Assert.Equal("{x:Bind ViewModel.IsLoading, Mode=OneWay}", Attribute(FindNamed("ProgressRing"), "IsActive"));
        Assert.Null(Attribute(FindNamed("TitleDragRegion"), "PointerPressed"));
        Assert.Null(Attribute(FindNamed("TitleDragRegion"), "PointerMoved"));
        Assert.Null(Attribute(FindNamed("TitleDragRegion"), "PointerReleased"));
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
    public void Window_ExposesManualTextAndImageRequestsWithLifetimeCancellation()
    {
        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        Assert.Contains("internal void ShowManual()", codeBehind, StringComparison.Ordinal);
        Assert.Contains("internal Task ShowAndTranslateTextAsync(string text, CancellationToken cancellationToken)", codeBehind, StringComparison.Ordinal);
        Assert.Contains("internal async Task ShowAndTranslateImageAsync(byte[] imageBytes, CancellationToken cancellationToken)", codeBehind, StringComparison.Ordinal);
        Assert.Contains("internal CancellationToken OperationToken", codeBehind, StringComparison.Ordinal);
        Assert.Contains("ViewModel.TranslateAsync(OperationToken)", codeBehind, StringComparison.Ordinal);
        Assert.Contains("ViewModel.TranslateImageAsync(image, OperationToken)", codeBehind, StringComparison.Ordinal);
    }

    [Fact]
    public void Startup_DoesNotShowPopup()
    {
        var composition = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "AppComposition.cs"));
        var start = composition[composition.IndexOf("public void Start()", StringComparison.Ordinal)..composition.IndexOf("public void ShowManual()", StringComparison.Ordinal)];
        Assert.DoesNotContain("ShowManual();", start, StringComparison.Ordinal);
    }

    [Fact]
    public void Result_IsPoliteLiveRegion()
    {
        var result = FindNamed("ResultTextBox");
        Assert.Equal("Polite", Attribute(result, "AutomationProperties.LiveSetting"));
    }

    [Fact]
    public void Popup_UsesHeaderSplitPaneAndGroupedFooterHierarchy()
    {
        var header = FindNamed("HeaderGrid");
        var title = FindNamed("TitleDragRegion");
        Assert.Contains(header.Descendants(), element => Attribute(element, "Name") == "TitleDragRegion");
        Assert.All(new[] { "UpdateButton", "HistoryButton", "PinButton", "CloseButton" }, name =>
        {
            Assert.Contains(header.Descendants(), element => Attribute(element, "Name") == name);
            Assert.DoesNotContain(title.DescendantsAndSelf(), element => Attribute(element, "Name") == name);
        });

        var paneGrid = FindNamed("PaneGrid");
        var columns = paneGrid.Elements().Single(e => e.Name.LocalName == "Grid.ColumnDefinitions").Elements().ToArray();
        Assert.Equal(new[] { "*", "Auto", "*" }, columns.Select(column => Attribute(column, "Width")));
        Assert.Contains(paneGrid.Descendants(), element => Attribute(element, "Name") == "PaneDivider");

        var sourceHeader = FindNamed("SourcePaneHeader");
        Assert.All(new[] { "SourceLanguageCode", "SpeechRateBox", "SourceSpeechButton" }, name => Assert.Contains(sourceHeader.Descendants(), element => Attribute(element, "Name") == name));
        var resultHeader = FindNamed("ResultPaneHeader");
        Assert.All(new[] { "TargetLanguageCode", "ResultSpeechButton", "CopyButton", "BookmarkButton" }, name => Assert.Contains(resultHeader.Descendants(), element => Attribute(element, "Name") == name));

        var footer = FindNamed("FooterGrid");
        Assert.Contains(footer.Descendants(), element => Attribute(element, "Name") == "ActionPanel");
        Assert.Contains(footer.Descendants(), element => Attribute(element, "Name") == "LanguagePanel");
        Assert.DoesNotContain("ButtonPanel", XDocument.Load(XamlPath).Descendants().Attributes().Where(a => a.Name.LocalName == "Name").Select(a => a.Value));
    }

    [Fact]
    public void Popup_UsesAccessibleIconActionsAndAccentTranslateButton()
    {
        var iconButtons = new[] { "UpdateButton", "HistoryButton", "PinButton", "CloseButton", "SourceSpeechButton", "ResultSpeechButton", "CopyButton", "BookmarkButton", "SwapButton" };
        foreach (var name in iconButtons)
        {
            var button = FindNamed(name);
            Assert.NotNull(Attribute(button, "AutomationProperties.Name"));
            Assert.NotNull(Attribute(button, "ToolTipService.ToolTip"));
            Assert.Contains(button.Descendants(), element => element.Name.LocalName is "SymbolIcon" or "FontIcon");
        }

        var translate = FindNamed("TranslateButton");
        Assert.Equal("{StaticResource AccentButtonStyle}", Attribute(translate, "Style"));
        Assert.Contains(translate.Descendants(), element => element.Name.LocalName is "SymbolIcon" or "FontIcon");
        Assert.Contains(translate.Descendants(), element => element.Name.LocalName == "TextBlock" && Attribute(element, "Text") == "Translate");
    }

    [Fact]
    public void Popup_UsesNativeSymbolIconsWithoutFluentFontGlyphs()
    {
        var document = XDocument.Load(XamlPath);
        Assert.DoesNotContain(document.Descendants(), element => element.Name.LocalName == "FontIcon");
        Assert.DoesNotContain("Segoe Fluent Icons", File.ReadAllText(XamlPath), StringComparison.Ordinal);

        var iconControls = new[]
        {
            "UpdateButton", "HistoryButton", "PinButton", "CloseButton", "SourceSpeechButton",
            "ResultSpeechButton", "CopyButton", "BookmarkButton", "ImagesButton", "ImageTranslateButton",
            "LearnButton", "TranslateButton", "SwapButton"
        };
        Assert.All(iconControls, name => Assert.Contains(FindNamed(name).Descendants(), element => element.Name.LocalName == "SymbolIcon"));
    }

    [Fact]
    public void Popup_WiresHeaderPaneActionsAndCustomTitleBar()
    {
        Assert.Equal("HistoryButton_Click", Attribute(FindNamed("HistoryButton"), "Click"));
        Assert.Equal("UpdateButton_Click", Attribute(FindNamed("UpdateButton"), "Click"));
        Assert.Equal("BookmarkButton_Click", Attribute(FindNamed("BookmarkButton"), "Click"));
        Assert.Equal("{x:Bind ViewModel.CanToggleSaved, Mode=OneWay}", Attribute(FindNamed("BookmarkButton"), "IsEnabled"));
        Assert.Null(Attribute(FindNamed("BookmarkButton"), "IsChecked"));
        Assert.Equal("{x:Bind ViewModel.SelectedSpeechRate, Mode=TwoWay}", Attribute(FindNamed("SpeechRateBox"), "SelectedItem"));

        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        Assert.Contains("ExtendsContentIntoTitleBar = true", codeBehind, StringComparison.Ordinal);
        Assert.Contains("SetTitleBar(TitleDragRegion)", codeBehind, StringComparison.Ordinal);
        Assert.Contains("SetBorderAndTitleBar(true, false)", codeBehind, StringComparison.Ordinal);
        Assert.DoesNotContain("TitleDragRegion_Pointer", codeBehind, StringComparison.Ordinal);
        Assert.Contains("BookmarkButton.IsChecked = ViewModel.IsCurrentSaved", codeBehind, StringComparison.Ordinal);
        Assert.Contains("SourceSpeechIcon.Symbol = SpeechSymbol(ViewModel.SourceSpeechActionText)", codeBehind, StringComparison.Ordinal);
        Assert.Contains("ResultSpeechIcon.Symbol = SpeechSymbol(ViewModel.ResultSpeechActionText)", codeBehind, StringComparison.Ordinal);
        Assert.Contains("await EventBoundary.IgnoreCancellation(() => ViewModel.ToggleSavedAsync(_lifetimeCancellation.Token))", codeBehind, StringComparison.Ordinal);
        Assert.Contains("try { await ViewModel.ReportErrorAsync(error); }", codeBehind, StringComparison.Ordinal);
        Assert.Contains("catch (UiDispatchUnavailableException) { }", codeBehind, StringComparison.Ordinal);
    }

    [Fact]
    public void Status_HasDedicatedFullWidthWrappedPoliteLiveRow()
    {
        var status = FindNamed("StatusTextBlock");
        Assert.Equal("{x:Bind ViewModel.StatusMessage, Mode=OneWay}", Attribute(status, "Text"));
        Assert.Equal("Wrap", Attribute(status, "TextWrapping"));
        Assert.Equal("Polite", Attribute(status, "AutomationProperties.LiveSetting"));
        Assert.Equal("2", Attribute(status, "Grid.Row"));
        Assert.Null(Attribute(status, "Grid.Column"));

        var footer = FindNamed("FooterGrid");
        Assert.Equal("3", Attribute(footer, "Grid.Row"));
        Assert.DoesNotContain(status, footer.Descendants());
    }

    [Fact]
    public void SourceEditor_TranslatesForAltOrControlEnter()
    {
        Assert.Equal("SourceTextBox_KeyDown", Attribute(FindNamed("SourceTextBox"), "KeyDown"));

        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        Assert.Contains("args.Key != Windows.System.VirtualKey.Enter", codeBehind, StringComparison.Ordinal);
        Assert.Contains("args.KeyStatus.IsMenuKeyDown", codeBehind, StringComparison.Ordinal);
        Assert.Contains("Windows.System.VirtualKey.Control", codeBehind, StringComparison.Ordinal);
        Assert.Contains("CoreVirtualKeyStates.Down", codeBehind, StringComparison.Ordinal);
        Assert.Contains("args.Handled = true", codeBehind, StringComparison.Ordinal);
        Assert.Contains("EventBoundary.IgnoreCancellation(() => ViewModel.TranslateAsync(OperationToken))", codeBehind, StringComparison.Ordinal);
    }

    [Fact]
    public void SpeechIconsFollowSpeakerPausePlaySpeakerLifecycle()
    {
        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        Assert.Contains("actionText.StartsWith(\"Pause\"", codeBehind, StringComparison.Ordinal);
        Assert.Contains("actionText.StartsWith(\"Resume\"", codeBehind, StringComparison.Ordinal);
        Assert.Contains("Microsoft.UI.Xaml.Controls.Symbol.Play", codeBehind, StringComparison.Ordinal);
        Assert.Contains("Microsoft.UI.Xaml.Controls.Symbol.Volume", codeBehind, StringComparison.Ordinal);
    }

    [Fact]
    public void BookmarkHandlerReliesOnUiDispatchedPropertyChange()
    {
        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        var start = codeBehind.IndexOf("private async void BookmarkButton_Click", StringComparison.Ordinal);
        var end = codeBehind.IndexOf("private void SwapButton_Click", start, StringComparison.Ordinal);
        var handler = codeBehind[start..end];

        Assert.DoesNotContain("BookmarkButton.IsChecked", handler, StringComparison.Ordinal);
        Assert.Contains("EventBoundary.IgnoreCancellation(() => ViewModel.ToggleSavedAsync", handler, StringComparison.Ordinal);
    }

    [Fact]
    public void Popup_DefinesRequiredKeyboardAccelerators()
    {
        var document = XDocument.Load(XamlPath);
        var accelerators = document.Descendants().Where(e => e.Name.LocalName == "KeyboardAccelerator")
            .Select(e => (Key: Attribute(e, "Key"), Modifiers: Attribute(e, "Modifiers"))).ToHashSet();
        Assert.Contains(("Escape", "None"), accelerators);
        Assert.Contains(("Enter", "Control"), accelerators);
        Assert.Contains(("Enter", "Menu"), accelerators);
        Assert.Contains(("C", "Control,Shift"), accelerators);
        Assert.Contains(("L", "Control,Shift"), accelerators);
    }

    [Fact]
    public void Popup_ReopeningResetsContentHeightMeasurement()
    {
        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        Assert.Contains("private void ShowAtConfiguredSize(string? sourceText)", codeBehind, StringComparison.Ordinal);
        Assert.Contains("_lastDesiredHeight = double.NaN", codeBehind, StringComparison.Ordinal);
        Assert.Equal(4, codeBehind.Split("ShowAtConfiguredSize(", StringSplitOptions.None).Length - 1);
    }

    [Fact]
    public void Popup_TextPanesScrollAndReportContentSizeChanges()
    {
        Assert.Equal("Auto", Attribute(FindNamed("SourceTextBox"), "ScrollViewer.VerticalScrollBarVisibility"));
        Assert.Equal("Auto", Attribute(FindNamed("ResultTextBox"), "ScrollViewer.VerticalScrollBarVisibility"));
        Assert.Equal("PopupContent_LayoutUpdated", Attribute(FindNamed("RootGrid"), "LayoutUpdated"));

        var codeBehind = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "TranslationWindow.xaml.cs"));
        Assert.Contains("EventBoundary.IgnoreCancellation(() => ViewModel.TranslateAsync(OperationToken))", codeBehind, StringComparison.Ordinal);
        Assert.DoesNotContain("ViewModel.TranslateCommand.ExecuteAsync()", codeBehind, StringComparison.Ordinal);
        Assert.Contains("args.Handled = true", codeBehind, StringComparison.Ordinal);
        Assert.Contains("_coordinator.ResizeToContent", codeBehind, StringComparison.Ordinal);
    }

    private static XElement FindNamed(string name) => XDocument.Load(XamlPath).Descendants()
        .Single(e => e.Attributes().Any(a => a.Name.LocalName == "Name" && a.Value == name));

    private static string? Attribute(XElement element, string localName) =>
        element.Attributes().SingleOrDefault(a => a.Name.LocalName == localName)?.Value;
}
