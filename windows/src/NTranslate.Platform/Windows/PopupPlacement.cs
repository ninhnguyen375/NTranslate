namespace NTranslate.Platform.Windows;

public readonly record struct ScreenPoint(int X, int Y);

public readonly record struct ScreenRect(int Left, int Top, int Right, int Bottom);

public readonly record struct PopupSize(int Width, int Height);

public static class PopupPlacement
{
    public static ScreenPoint Place(ScreenPoint cursor, PopupSize popup, ScreenRect workArea, int gap = 12)
    {
        var candidates = new[]
        {
            new ScreenPoint(cursor.X, cursor.Y + gap),
            new ScreenPoint(cursor.X, cursor.Y - gap - popup.Height),
            new ScreenPoint(cursor.X + gap, cursor.Y),
            new ScreenPoint(cursor.X - gap - popup.Width, cursor.Y)
        };

        foreach (var candidate in candidates)
        {
            if (Fits(candidate, popup, workArea))
                return candidate;
        }

        return new ScreenPoint(
            Clamp(cursor.X, workArea.Left, workArea.Right - popup.Width),
            Clamp(cursor.Y + gap, workArea.Top, workArea.Bottom - popup.Height));
    }

    private static bool Fits(ScreenPoint point, PopupSize popup, ScreenRect workArea) =>
        point.X >= workArea.Left &&
        point.Y >= workArea.Top &&
        point.X + popup.Width <= workArea.Right &&
        point.Y + popup.Height <= workArea.Bottom;

    private static int Clamp(int candidateX, int minimum, int maximum) =>
        maximum < minimum ? minimum : Math.Clamp(candidateX, minimum, maximum);
}
