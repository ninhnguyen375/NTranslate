using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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

    private void Navigation_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var selected = (args.SelectedItemContainer?.Tag as string) ?? "General";
        GeneralSection.Visibility = selected == "General" ? Visibility.Visible : Visibility.Collapsed;
        PromptsSection.Visibility = selected == "Prompts" ? Visibility.Visible : Visibility.Collapsed;
        LanguagesSection.Visibility = selected == "Languages" ? Visibility.Visible : Visibility.Collapsed;
        AdvancedSection.Visibility = selected == "Advanced" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void AddLanguage_Click(object sender, RoutedEventArgs args) => _viewModel.AddLanguage();
    private void RemoveLanguage_Click(object sender, RoutedEventArgs args) { if (LanguagesList.SelectedItem is string value) _viewModel.RemoveLanguage(value); }
    private void AddTargetLanguage_Click(object sender, RoutedEventArgs args) => _viewModel.AddTargetLanguage();
    private void RemoveTargetLanguage_Click(object sender, RoutedEventArgs args) { if (TargetLanguagesList.SelectedItem is string value) _viewModel.RemoveTargetLanguage(value); }
    private async void Save_Click(object sender, RoutedEventArgs args) => await _viewModel.SaveAsync(_lifetime.Token);
    private void Cancel_Click(object sender, RoutedEventArgs args) => _viewModel.Cancel();
    private void Revert_Click(object sender, RoutedEventArgs args) => _viewModel.Revert();
    private async void Browse_Click(object sender, RoutedEventArgs args) => await _viewModel.BrowseHistoryDirectoryAsync(_lifetime.Token);
    private async void SaveAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; await _viewModel.SaveAsync(_lifetime.Token); }
}
