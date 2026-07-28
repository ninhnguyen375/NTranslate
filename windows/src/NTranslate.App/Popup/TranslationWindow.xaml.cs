using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using System.Runtime.InteropServices;

namespace NTranslate.App.Popup;

public sealed partial class TranslationWindow : Window
{
    private readonly PopupCoordinator _coordinator;
    private readonly Microsoft.UI.Windowing.AppWindow _appWindow;
    private bool _shuttingDown;
    private readonly TitleDragPolicy _drag = new(4);

    internal TranslationWindow(TranslationViewModel viewModel, double width, double height, Action cancelWork)
    {
        ViewModel = viewModel;
        InitializeComponent();
        _coordinator = new PopupCoordinator(this, viewModel, width, height, cancelWork);
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        _appWindow = Microsoft.UI.Windowing.AppWindow.GetFromWindowId(Microsoft.UI.Win32Interop.GetWindowIdFromWindow(hwnd));
        _appWindow.Closing += AppWindow_Closing;
        Activated += (_, args) =>
        {
            if (args.WindowActivationState == WindowActivationState.Deactivated)
                _coordinator.Deactivate();
        };
    }

    internal TranslationViewModel ViewModel { get; }

    internal void ShowPopup(string? sourceText) => _coordinator.Show(sourceText);

    internal void RestoreWindowProcedure() => _coordinator.RestoreWindowProcedure();

    internal void CloseForShutdown()
    {
        _shuttingDown = true;
        Close();
    }

    private void AppWindow_Closing(Microsoft.UI.Windowing.AppWindow sender, Microsoft.UI.Windowing.AppWindowClosingEventArgs args)
    {
        if (_shuttingDown) return;
        args.Cancel = true;
        _coordinator.Close();
    }

    private void TitleDragRegion_PointerPressed(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs args)
    {
        var point = args.GetCurrentPoint(TitleDragRegion);
        if (point.Properties.IsLeftButtonPressed)
            _drag.Press(point.Position.X, point.Position.Y);
    }

    private void TitleDragRegion_PointerMoved(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs args)
    {
        var point = args.GetCurrentPoint(TitleDragRegion);
        if (!point.Properties.IsLeftButtonPressed || !_drag.Move(point.Position.X, point.Position.Y)) return;
        _coordinator.Drag();
        PinButton.IsChecked = true;
        ReleaseCapture();
        SendMessage(WinRT.Interop.WindowNative.GetWindowHandle(this), 0x00A1, 2, 0); // WM_NCLBUTTONDOWN, HTCAPTION
    }

    private void TitleDragRegion_PointerReleased(object sender, Microsoft.UI.Xaml.Input.PointerRoutedEventArgs args) => _drag.Release();

    [DllImport("user32.dll")] private static extern bool ReleaseCapture();
    [DllImport("user32.dll")] private static extern nint SendMessage(nint hwnd, uint message, nint wParam, nint lParam);

    private void CloseButton_Click(object sender, RoutedEventArgs e) => _coordinator.Close();
    private void PinButton_Click(object sender, RoutedEventArgs e) => _coordinator.IsPinned = PinButton.IsChecked == true;
    private void SwapButton_Click(object sender, RoutedEventArgs e) => ViewModel.SwapLanguages();
    private void CloseAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { _coordinator.Close(); args.Handled = true; }
    private void TranslateAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { if (ViewModel.TranslateCommand.CanExecute(null)) ViewModel.TranslateCommand.Execute(null); args.Handled = true; }
    private void CopyAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { if (ViewModel.CopyCommand.CanExecute(null)) ViewModel.CopyCommand.Execute(null); args.Handled = true; }
}
