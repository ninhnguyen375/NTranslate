using Microsoft.UI.Xaml;

namespace NTranslate.App.History;

public sealed partial class HistoryWindow : Window
{
    public HistoryWindow(HistoryViewModel viewModel)
    {
        InitializeComponent();
        if (Content is FrameworkElement content)
            content.DataContext = viewModel;
    }
}
