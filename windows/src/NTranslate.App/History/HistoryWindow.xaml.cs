using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using NTranslate.Core.History;

namespace NTranslate.App.History;

public sealed partial class HistoryWindow : Window
{
    private readonly HistoryViewModel _viewModel;
    private readonly Microsoft.UI.Windowing.AppWindow _appWindow;
    private CancellationTokenSource _lifetime = new();
    private bool _shuttingDown;

    public HistoryWindow(HistoryViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();
        if (Content is FrameworkElement content) content.DataContext = viewModel;
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd));
        _appWindow.Closing += AppWindow_Closing;
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

    private async void History_DoubleTapped(object sender, DoubleTappedRoutedEventArgs args) => await ReopenSelectedAsync();
    private async void HistoryEnter_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; await ReopenSelectedAsync(); }
    private async Task ReopenSelectedAsync() { if (HistoryList.SelectedItem is TranslationRecord record) await _viewModel.ReopenAsync(record, _lifetime.Token); }
    private async void DeleteVisible_Click(object sender, RoutedEventArgs args) => await _viewModel.DeleteVisibleAsync(_lifetime.Token);
    private async void PlaySource_Click(object sender, RoutedEventArgs args)
    {
        if (Record(sender) is { } record)
        {
            try { await _viewModel.PlayAudioAsync(record, TranslationAudioKind.Source, _lifetime.Token); }
            catch (Exception ex) when (ex is not OperationCanceledException) { }
        }
    }
    private async void PlayResult_Click(object sender, RoutedEventArgs args)
    {
        if (Record(sender) is { } record)
        {
            try { await _viewModel.PlayAudioAsync(record, TranslationAudioKind.Result, _lifetime.Token); }
            catch (Exception ex) when (ex is not OperationCanceledException) { }
        }
    }
    private async void ToggleSaved_Click(object sender, RoutedEventArgs args) { if (Record(sender) is { } record) await _viewModel.SetSavedAsync(record, !record.IsSaved, _lifetime.Token); }
    private async void Delete_Click(object sender, RoutedEventArgs args) { if (Record(sender) is { } record) await _viewModel.DeleteAsync(record, _lifetime.Token); }
    private void AllHistory_Click(object sender, RoutedEventArgs args) => _viewModel.SavedOnly = false;
    private void Saved_Click(object sender, RoutedEventArgs args) => _viewModel.SavedOnly = true;
    private void TimeRange_SelectionChanged(object sender, SelectionChangedEventArgs args) { if (sender is ComboBox { SelectedIndex: >= 0 } box) _viewModel.TimeRange = (HistoryTimeRange)box.SelectedIndex; }
    private static TranslationRecord? Record(object sender) => (sender as FrameworkElement)?.Tag as TranslationRecord;
}
