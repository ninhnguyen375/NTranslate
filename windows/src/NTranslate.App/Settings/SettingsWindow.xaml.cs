using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;

namespace NTranslate.App.Settings;

public sealed partial class SettingsWindow : Window
{
    private readonly SettingsViewModel _viewModel;
    private readonly Microsoft.UI.Windowing.AppWindow _appWindow;
    private CancellationTokenSource _lifetime = new();
    private bool _shuttingDown;

    public SettingsWindow(SettingsViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();
        if (Content is FrameworkElement content) content.DataContext = viewModel;
        SyncApiKeyBox();
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd));
        _appWindow.Closing += AppWindow_Closing;
        _viewModel.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName == "Draft")
                SyncApiKeyBox();
        };
    }

    private void SyncApiKeyBox() => ApiKeyBox.Password = _viewModel.Draft.ApiKey;

    private void ApiKeyBox_PasswordChanged(object sender, RoutedEventArgs e)
    {
        _viewModel.Draft.ApiKey = ApiKeyBox.Password;
    }

    internal void PrepareToShow()
    {
        if (!_lifetime.IsCancellationRequested) return;
        _lifetime.Dispose();
        _lifetime = new();
    }

    internal void CloseForShutdown()
    {
        _shuttingDown = true;
        _lifetime.Cancel();
        Close();
    }

    private void AppWindow_Closing(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        if (_shuttingDown) return;
        args.Cancel = true;
        _lifetime.Cancel();
        _appWindow.Hide();
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
    private async void Save_Click(object sender, RoutedEventArgs args) => await RunUiActionAsync(() => _viewModel.SaveAsync(_lifetime.Token));
    private void Cancel_Click(object sender, RoutedEventArgs args) => _viewModel.Cancel();
    private void Revert_Click(object sender, RoutedEventArgs args) => _viewModel.Revert();
    private async void Browse_Click(object sender, RoutedEventArgs args) => await RunUiActionAsync(() => _viewModel.BrowseHistoryDirectoryAsync(_lifetime.Token));
    private async void SaveAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; await RunUiActionAsync(() => _viewModel.SaveAsync(_lifetime.Token)); }

    private async Task RunUiActionAsync(Func<Task> action)
    {
        try { await action(); }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested) { }
        catch (Exception exception) { _viewModel.ReportError(exception); }
    }
}
