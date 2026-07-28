namespace NTranslate.App.Popup;

internal sealed class TitleDragPolicy(double threshold)
{
    private (double X, double Y)? _start;

    public void Press(double x, double y) => _start = (x, y);
    public void Release() => _start = null;

    public bool Move(double x, double y)
    {
        if (_start is not { } start || Math.Abs(x - start.X) + Math.Abs(y - start.Y) < threshold)
            return false;
        _start = null;
        return true;
    }
}
