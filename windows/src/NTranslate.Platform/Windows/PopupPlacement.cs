namespace NTranslate.Platform.Windows;

public readonly record struct ScreenPoint(int X, int Y);

/// <summary>Physical-pixel rectangle with exclusive <see cref="Right"/> and <see cref="Bottom"/> edges.</summary>
public readonly record struct ScreenRect(int Left, int Top, int Right, int Bottom);

public readonly record struct PopupSize(int Width, int Height);

public static class PopupPlacement
{
    public static ScreenPoint Place(ScreenPoint cursor, PopupSize popup, ScreenRect workArea, int gap = 12)
    {
        var candidates = new[]
        {
            new ScreenPoint(cursor.X, Saturate((long)cursor.Y + gap)),
            new ScreenPoint(cursor.X, Saturate((long)cursor.Y - gap - popup.Height)),
            new ScreenPoint(Saturate((long)cursor.X + gap), cursor.Y),
            new ScreenPoint(Saturate((long)cursor.X - gap - popup.Width), cursor.Y)
        };

        foreach (var candidate in candidates)
        {
            if (Fits(candidate, popup, workArea))
                return candidate;
        }

        return ClampToWorkArea(new(cursor.X, Saturate((long)cursor.Y + gap)), popup, workArea);
    }

    public static ScreenPoint ClampToWorkArea(ScreenPoint point, PopupSize popup, ScreenRect workArea) =>
        new(
            Clamp(point.X, workArea.Left, (long)workArea.Right - popup.Width),
            Clamp(point.Y, workArea.Top, (long)workArea.Bottom - popup.Height));

    public static PopupSize ToPhysicalPixels(double width, double height, uint dpi)
    {
        ArgumentOutOfRangeException.ThrowIfZero(dpi);
        return new PopupSize(ToPhysicalPixels(width, dpi), ToPhysicalPixels(height, dpi));
    }

    private static bool Fits(ScreenPoint point, PopupSize popup, ScreenRect workArea) =>
        point.X >= workArea.Left &&
        point.Y >= workArea.Top &&
        (long)point.X + popup.Width <= workArea.Right &&
        (long)point.Y + popup.Height <= workArea.Bottom;

    private static int Clamp(long value, int minimum, long maximum) =>
        maximum < minimum ? minimum : Saturate(Math.Clamp(value, minimum, maximum));

    private static int ToPhysicalPixels(double value, uint dpi)
    {
        if (!double.IsFinite(value) || value < 0)
            throw new ArgumentOutOfRangeException(nameof(value));

        return Saturate(Math.Round(value * dpi / 96, MidpointRounding.AwayFromZero));
    }

    private static int Saturate(long value) =>
        value > int.MaxValue ? int.MaxValue : value < int.MinValue ? int.MinValue : (int)value;

    private static int Saturate(double value) =>
        value > int.MaxValue ? int.MaxValue : value < int.MinValue ? int.MinValue : (int)value;
}
