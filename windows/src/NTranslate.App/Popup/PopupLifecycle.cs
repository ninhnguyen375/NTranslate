namespace NTranslate.App.Popup;

internal sealed class PopupLifecycle(Action cancel, Action hide)
{
    public bool IsPinned { get; set; }

    public void Close()
    {
        cancel();
        hide();
    }

    public void Deactivate()
    {
        if (!IsPinned)
            Close();
    }

    public void Drag() => IsPinned = true;
}
