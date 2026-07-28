using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using NTranslate.Core.History;

namespace NTranslate.App.History;

public sealed partial class HistoryWindow : Window
{
    private readonly HistoryViewModel _viewModel;
    private readonly CancellationTokenSource _lifetime = new();

    public HistoryWindow(HistoryViewModel viewModel)
    {
        _viewModel = viewModel;
        InitializeComponent();
        if (Content is FrameworkElement content) content.DataContext = viewModel;
    }

    private async void History_ItemClick(object sender, ItemClickEventArgs args) { if (args.ClickedItem is TranslationRecord record) await _viewModel.ReopenAsync(record, _lifetime.Token); }
    private async void DeleteVisible_Click(object sender, RoutedEventArgs args) => await _viewModel.DeleteVisibleAsync(_lifetime.Token);
    private async void PlaySource_Click(object sender, RoutedEventArgs args) { if (Record(sender) is { } record) await _viewModel.PlayAudioAsync(record, TranslationAudioKind.Source, _lifetime.Token); }
    private async void PlayResult_Click(object sender, RoutedEventArgs args) { if (Record(sender) is { } record) await _viewModel.PlayAudioAsync(record, TranslationAudioKind.Result, _lifetime.Token); }
    private async void ToggleSaved_Click(object sender, RoutedEventArgs args) { if (Record(sender) is { } record) await _viewModel.SetSavedAsync(record, !record.IsSaved, _lifetime.Token); }
    private async void Delete_Click(object sender, RoutedEventArgs args) { if (Record(sender) is { } record) await _viewModel.DeleteAsync(record, _lifetime.Token); }
    private void AllHistory_Click(object sender, RoutedEventArgs args) => _viewModel.SavedOnly = false;
    private void Saved_Click(object sender, RoutedEventArgs args) => _viewModel.SavedOnly = true;
    private void TimeRange_SelectionChanged(object sender, SelectionChangedEventArgs args) { if (sender is ComboBox { SelectedIndex: >= 0 } box) _viewModel.TimeRange = (HistoryTimeRange)box.SelectedIndex; }
    private static TranslationRecord? Record(object sender) => (sender as FrameworkElement)?.Tag as TranslationRecord;
}
