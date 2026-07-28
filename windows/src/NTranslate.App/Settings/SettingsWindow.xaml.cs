using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;

namespace NTranslate.App.Settings;

public sealed partial class SettingsWindow : Window
{
    private readonly SettingsViewModel _viewModel;
    private readonly CancellationTokenSource _lifetime = new();

    public SettingsWindow(SettingsViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();
        if (Content is FrameworkElement content) content.DataContext = viewModel;
    }

    private async void Save_Click(object sender, RoutedEventArgs args) => await _viewModel.SaveAsync(_lifetime.Token);
    private void Cancel_Click(object sender, RoutedEventArgs args) => _viewModel.Cancel();
    private void Revert_Click(object sender, RoutedEventArgs args) => _viewModel.Revert();
    private async void Browse_Click(object sender, RoutedEventArgs args) => await _viewModel.BrowseHistoryDirectoryAsync(_lifetime.Token);
    private async void SaveAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; await _viewModel.SaveAsync(_lifetime.Token); }
}
