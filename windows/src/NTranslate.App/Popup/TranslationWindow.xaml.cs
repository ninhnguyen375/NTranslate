using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;

namespace NTranslate.App.Popup;

public sealed partial class TranslationWindow : Window
{
    private readonly PopupCoordinator _coordinator;
    private Windows.Foundation.Point? _dragStart;

    internal TranslationWindow(TranslationViewModel viewModel, double width, double height)
    {
        ViewModel = viewModel;
        InitializeComponent();
        _coordinator = new PopupCoordinator(this, viewModel, width, height);
        Activated += (_, args) =>
        {
            if (args.WindowActivationState == WindowActivationState.Deactivated)
                _coordinator.Deactivate();
        };
        RootGrid.PointerPressed += (_, args) => _dragStart = args.GetCurrentPoint(RootGrid).Position;
        RootGrid.PointerMoved += (_, args) =>
        {
            if (_dragStart is not { } start || !args.GetCurrentPoint(RootGrid).Properties.IsLeftButtonPressed)
                return;
            var current = args.GetCurrentPoint(RootGrid).Position;
            if (Math.Abs(current.X - start.X) + Math.Abs(current.Y - start.Y) < 4)
                return;
            _coordinator.Drag();
            PinButton.IsChecked = true;
            _dragStart = null;
        };
        RootGrid.PointerReleased += (_, _) => _dragStart = null;
    }

    internal TranslationViewModel ViewModel { get; }

    internal void ShowPopup(string? sourceText) => _coordinator.Show(sourceText);

    internal void RestoreWindowProcedure() => _coordinator.RestoreWindowProcedure();

    private void CloseButton_Click(object sender, RoutedEventArgs e) => _coordinator.Close();
    private void PinButton_Click(object sender, RoutedEventArgs e) => _coordinator.IsPinned = PinButton.IsChecked == true;
    private void SwapButton_Click(object sender, RoutedEventArgs e) => ViewModel.SwapLanguages();
    private void CloseAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { _coordinator.Close(); args.Handled = true; }
    private void TranslateAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { if (ViewModel.TranslateCommand.CanExecute(null)) ViewModel.TranslateCommand.Execute(null); args.Handled = true; }
    private void CopyAccelerator_Invoked(KeyboardAccelerator sender, KeyboardAcceleratorInvokedEventArgs args) { if (ViewModel.CopyCommand.CanExecute(null)) ViewModel.CopyCommand.Execute(null); args.Handled = true; }
}
