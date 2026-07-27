using NTranslate.Platform.Windows;

namespace NTranslate.Platform.Tests.Windows;

public sealed class PopupPlacementTests
{
    [Fact]
    public void Place_prefers_below_cursor()
    {
        var point = Place(cursor: new(500, 400), popup: new(200, 100), workArea: new(0, 0, 1920, 1080));

        Assert.Equal(new ScreenPoint(500, 412), point);
    }

    [Fact]
    public void Place_prefers_above_when_below_overflows()
    {
        var point = Place(cursor: new(500, 1000), popup: new(200, 100), workArea: new(0, 0, 1920, 1080));

        Assert.Equal(new ScreenPoint(500, 888), point);
    }

    [Fact]
    public void Place_prefers_right_when_vertical_placements_overflow()
    {
        var point = Place(cursor: new(50, 50), popup: new(50, 50), workArea: new(0, 0, 300, 100));

        Assert.Equal(new ScreenPoint(62, 50), point);
    }

    [Fact]
    public void Place_prefers_left_when_other_placements_overflow()
    {
        var point = Place(cursor: new(100, 50), popup: new(50, 50), workArea: new(0, 0, 130, 100));

        Assert.Equal(new ScreenPoint(38, 50), point);
    }

    [Fact]
    public void Place_clamps_when_no_direction_fits()
    {
        var point = Place(cursor: new(250, 50), popup: new(100, 120), workArea: new(0, 0, 300, 100));

        Assert.Equal(new ScreenPoint(200, 0), point);
    }

    [Fact]
    public void Place_preserves_negative_monitor_coordinates()
    {
        var point = Place(cursor: new(-1000, 500), popup: new(300, 200), workArea: new(-1920, 0, 0, 1040));

        Assert.Equal(new ScreenPoint(-1000, 512), point);
    }

    [Fact]
    public void Place_uses_work_area_excluding_bottom_taskbar()
    {
        var point = Place(cursor: new(500, 1000), popup: new(200, 100), workArea: new(0, 0, 1920, 1040));

        Assert.Equal(new ScreenPoint(500, 888), point);
    }

    [Fact]
    public void Place_anchors_oversized_popup_at_work_area_origin()
    {
        var point = Place(cursor: new(500, 400), popup: new(2200, 1200), workArea: new(0, 0, 1920, 1080));

        Assert.Equal(new ScreenPoint(0, 0), point);
    }

    [Fact]
    public void Place_accepts_popup_ending_at_exclusive_right_and_bottom_edges()
    {
        var point = Place(cursor: new(900, 888), popup: new(100, 100), workArea: new(0, 0, 1000, 1000));

        Assert.Equal(new ScreenPoint(900, 900), point);
    }

    [Fact]
    public void Place_saturates_candidates_at_int_extremes()
    {
        var point = Place(
            cursor: new(int.MaxValue, 100),
            popup: new(1, 10),
            workArea: new(0, 0, int.MaxValue, int.MaxValue));

        Assert.Equal(new ScreenPoint(int.MaxValue - 13, 100), point);
    }

    [Fact]
    public void ToPhysicalPixels_rounds_half_pixels_away_from_zero()
    {
        var size = PopupPlacement.ToPhysicalPixels(1, 100, 144);

        Assert.Equal(new PopupSize(2, 150), size);
    }

    [Fact]
    public void ToPhysicalPixels_rejects_zero_dpi()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => PopupPlacement.ToPhysicalPixels(100, 100, 0));
    }

    [Fact]
    public void ToPhysicalPixels_rejects_negative_dimensions()
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => PopupPlacement.ToPhysicalPixels(-1, 100, 96));
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void ToPhysicalPixels_rejects_non_finite_width(double width)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => PopupPlacement.ToPhysicalPixels(width, 100, 96));
    }

    [Theory]
    [InlineData(double.NaN)]
    [InlineData(double.PositiveInfinity)]
    [InlineData(double.NegativeInfinity)]
    public void ToPhysicalPixels_rejects_non_finite_height(double height)
    {
        Assert.Throws<ArgumentOutOfRangeException>(() => PopupPlacement.ToPhysicalPixels(100, height, 96));
    }

    private static ScreenPoint Place(ScreenPoint cursor, PopupSize popup, ScreenRect workArea) =>
        PopupPlacement.Place(cursor, popup, workArea);
}
