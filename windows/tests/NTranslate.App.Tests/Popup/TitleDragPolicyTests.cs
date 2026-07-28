using NTranslate.App.Popup;

namespace NTranslate.App.Tests.Popup;

public sealed class TitleDragPolicyTests
{
    [Fact]
    public void ClickWithoutMovement_DoesNotStartDrag()
    {
        var drag = new TitleDragPolicy(4);
        drag.Press(10, 10);
        drag.Release();
        Assert.False(drag.Move(10, 10));
    }

    [Fact]
    public void MovementPastThreshold_StartsDragOnce()
    {
        var drag = new TitleDragPolicy(4);
        drag.Press(10, 10);
        Assert.False(drag.Move(12, 11));
        Assert.True(drag.Move(15, 10));
        Assert.False(drag.Move(20, 10));
    }
}
