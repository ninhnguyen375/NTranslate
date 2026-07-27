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

    private static ScreenPoint Place(ScreenPoint cursor, PopupSize popup, ScreenRect workArea) =>
        PopupPlacement.Place(cursor, popup, workArea);
}
