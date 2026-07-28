using Microsoft.UI.Xaml;

namespace NTranslate.App.Settings;

public sealed partial class SettingsWindow : Window
{
    public SettingsWindow(SettingsViewModel viewModel)
    {
        InitializeComponent();
        if (Content is FrameworkElement content)
            content.DataContext = viewModel;
    }
}
