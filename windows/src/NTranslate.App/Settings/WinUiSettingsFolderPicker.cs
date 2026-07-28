using Microsoft.UI.Xaml;
using Windows.Storage.Pickers;

namespace NTranslate.App.Settings;

public sealed class WinUiSettingsFolderPicker(Window owner) : ISettingsFolderPicker
{
    public nint OwnerHwnd => WinRT.Interop.WindowNative.GetWindowHandle(owner);

    public async Task<string?> PickAsync(nint ownerHwnd, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var picker = new FolderPicker();
        WinRT.Interop.InitializeWithWindow.Initialize(picker, ownerHwnd);
        picker.FileTypeFilter.Add("*");
        var folder = await picker.PickSingleFolderAsync().AsTask(token);
        return folder?.Path;
    }
}
