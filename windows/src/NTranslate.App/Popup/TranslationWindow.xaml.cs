using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Windows.ApplicationModel.DataTransfer;
using NTranslate.Core.History;

namespace NTranslate.App.Popup;

public sealed partial class TranslationWindow : Window
{
    [DllImport("user32.dll")] internal static extern bool ShowWindow(nint hWnd, int nCmdShow);
    private readonly PopupCoordinator _coordinator;
    private readonly Microsoft.UI.Windowing.AppWindow _appWindow;
    private readonly Action _showHistory;
    private readonly Func<Task> _checkForUpdates;
    private CancellationTokenSource _lifetimeCancellation = new();
    private bool _shuttingDown;

    internal TranslationWindow(TranslationViewModel viewModel, double width, double height, Action cancelWork, Action showHistory, Func<Task> checkForUpdates)
    {
        ViewModel = viewModel;
        _showHistory = showHistory;
        _checkForUpdates = checkForUpdates;
        InitializeComponent();
        BookmarkButton.IsChecked = ViewModel.IsCurrentSaved;
        ViewModel.PropertyChanged += (_, args) =>
        {
            if (args.PropertyName == nameof(ViewModel.IsCurrentSaved))
                BookmarkButton.IsChecked = ViewModel.IsCurrentSaved;
        };
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(TitleDragRegion);
        _coordinator = new PopupCoordinator(this, viewModel, width, height, cancelWork);
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd));
        if (_appWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter presenter)
            presenter.SetBorderAndTitleBar(true, false);
        _appWindow.Closing += AppWindow_Closing;
        Activated += (_, args) =>
        {
            if (args.WindowActivationState == WindowActivationState.Deactivated)
                _coordinator.Deactivate();
        };
    }

    internal TranslationViewModel ViewModel { get; }
    internal CancellationToken OperationToken => _lifetimeCancellation.Token;

    internal void InitializeForTray() { Activate(); _appWindow.Hide(); }
    internal void ShowManual()
    {
        ViewModel.SourceText = string.Empty;
        ShowPopup(null);
    }
    internal void ShowHistoryRecord(TranslationRecord record)
    {
        if (_lifetimeCancellation.IsCancellationRequested)
        {
            _lifetimeCancellation.Dispose();
            _lifetimeCancellation = new();
        }
        ImagePreview.Source = null;
        ViewModel.OpenHistoryRecord(record);
        ShowAtConfiguredSize(null);
    }
    internal Task ShowAndTranslateTextAsync(string text, CancellationToken cancellationToken)
    {
        if (cancellationToken.IsCancellationRequested) return Task.CompletedTask;
        ShowPopup(text);
        return ViewModel.TranslateAsync(OperationToken);
    }

    internal async Task ShowAndTranslateImageAsync(byte[] imageBytes, CancellationToken cancellationToken)
    {
        if (cancellationToken.IsCancellationRequested) return;
        ShowImagePopup(imageBytes);
        using var image = new MemoryStream(imageBytes, writable: false);
        await ViewModel.TranslateImageAsync(image, OperationToken);
    }

    internal void ShowPopup(string? sourceText)
    {
        if (_lifetimeCancellation.IsCancellationRequested)
        {
            _lifetimeCancellation.Dispose();
            _lifetimeCancellation = new();
        }
        ViewModel.EnterTextMode();
        ShowAtConfiguredSize(sourceText);
    }

    internal void ShowImagePopup(byte[] imageBytes)
    {
        if (_lifetimeCancellation.IsCancellationRequested)
        {
            _lifetimeCancellation.Dispose();
            _lifetimeCancellation = new();
        }
        ViewModel.EnterImageMode();
        using var image = new MemoryStream(imageBytes, writable: false);
        var preview = new BitmapImage();
        preview.SetSource(image.AsRandomAccessStream());
        ImagePreview.Source = preview;
        ShowAtConfiguredSize(null);
    }

    private void ShowAtConfiguredSize(string? sourceText)
    {
        _lastDesiredHeight = double.NaN;
        _coordinator.Show(sourceText);
    }

    internal void RestoreWindowProcedure() => _coordinator.RestoreWindowProcedure();

    internal void CloseForShutdown()
    {
        _shuttingDown = true;
        CancelOperations();
        Close();
    }

    private void AppWindow_Closing(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        if (_shuttingDown) return;
        args.Cancel = true;
        CancelOperations();
        _coordinator.Close();
    }

    private void CancelOperations()
    {
        _lifetimeCancellation.Cancel();
        ViewModel.WindowChanged();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) { CancelOperations(); _coordinator.Close(); }
    private void PinButton_Click(object sender, RoutedEventArgs e)
    {
        try { _coordinator.IsPinned = PinButton.IsChecked == true; }
        catch (Exception error)
        {
            PinButton.IsChecked = _coordinator.IsPinned;
            _ = ReportPinErrorAsync(error);
        }
    }

    private async Task ReportPinErrorAsync(Exception error)
    {
        try { await ViewModel.ReportErrorAsync(error); }
        catch (UiDispatchUnavailableException) { }
    }
    private void HistoryButton_Click(object sender, RoutedEventArgs e) => _showHistory();
    private async void UpdateButton_Click(object sender, RoutedEventArgs e) => await _checkForUpdates();
    private async void BookmarkButton_Click(object sender, RoutedEventArgs e)
    {
        await EventBoundary.IgnoreCancellation(() => ViewModel.ToggleSavedAsync(_lifetimeCancellation.Token));
        BookmarkButton.IsChecked = ViewModel.IsCurrentSaved;
    }
    private void SwapButton_Click(object sender, RoutedEventArgs e) => ViewModel.SwapLanguages();
    private async void LearnButton_Click(object sender, RoutedEventArgs e) => await ViewModel.LearnAsync(_lifetimeCancellation.Token);
    private async void ImagesButton_Click(object sender, RoutedEventArgs e) => await ViewModel.SearchImagesAsync(_lifetimeCancellation.Token);
    private async void SourceSpeechButton_Click(object sender, RoutedEventArgs e)
    {
        try { await ViewModel.SpeakSourceAsync(_lifetimeCancellation.Token); }
        catch (Exception ex) when (ex is not OperationCanceledException) { }
    }
    private async void ResultSpeechButton_Click(object sender, RoutedEventArgs e)
    {
        try { await ViewModel.SpeakResultAsync(_lifetimeCancellation.Token); }
        catch (Exception ex) when (ex is not OperationCanceledException) { }
    }

    private async void ImageTranslateButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var content = Clipboard.GetContent();
            if (!content.Contains(StandardDataFormats.Bitmap)) return;
            var reference = await content.GetBitmapAsync();
            using var input = await reference.OpenReadAsync();
            using var image = new MemoryStream();
            await input.AsStreamForRead().CopyToAsync(image, _lifetimeCancellation.Token);
            image.Position = 0;
            var preview = new BitmapImage();
            await preview.SetSourceAsync(image.AsRandomAccessStream());
            ImagePreview.Source = preview;
            image.Position = 0;
            await ViewModel.TranslateImageAsync(image, _lifetimeCancellation.Token);
        }
        catch (OperationCanceledException) when (_lifetimeCancellation.IsCancellationRequested) { }
        catch (Exception error)
        {
            try { await ViewModel.ReportErrorAsync(error); }
            catch (UiDispatchUnavailableException) { }
        }
    }

    private double _lastDesiredHeight;

    internal static double CalculateDesiredContentHeight(
        double chromeHeight,
        double sourceContentHeight,
        double resultContentHeight) =>
        chromeHeight + sourceContentHeight + resultContentHeight;

    private void PopupContent_LayoutUpdated(object? sender, object args)
    {
        var sourceHeight = ContentHeight(SourceTextBox);
        var resultHeight = ContentHeight(ResultTextBox);
        var chromeHeight = Math.Max(0, RootGrid.ActualHeight - SourceTextBox.ActualHeight - ResultTextBox.ActualHeight);
        var desiredHeight = CalculateDesiredContentHeight(chromeHeight, sourceHeight, resultHeight);
        if (desiredHeight == _lastDesiredHeight)
            return;
        _lastDesiredHeight = desiredHeight;
        _coordinator.ResizeToContent(desiredHeight);
    }

    private static double ContentHeight(DependencyObject element)
    {
        if (element is Microsoft.UI.Xaml.Controls.ScrollViewer scrollViewer)
            return scrollViewer.ExtentHeight;
        for (var index = 0; index < Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChildrenCount(element); index++)
        {
            var height = ContentHeight(Microsoft.UI.Xaml.Media.VisualTreeHelper.GetChild(element, index));
            if (height > 0) return height;
        }
        return 0;
    }

    private void CloseAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { CancelOperations(); _coordinator.Close(); args.Handled = true; }
    private async void TranslateAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args)
    {
        args.Handled = true;
        await EventBoundary.IgnoreCancellation(() => ViewModel.TranslateAsync(OperationToken));
    }
    private async void LearnAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { args.Handled = true; await ViewModel.LearnAsync(_lifetimeCancellation.Token); }
    private void CopyAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { if (ViewModel.CopyCommand.CanExecute(null)) ViewModel.CopyCommand.Execute(null); args.Handled = true; }
}
