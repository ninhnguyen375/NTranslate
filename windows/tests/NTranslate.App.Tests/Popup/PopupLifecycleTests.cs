using NTranslate.App.Popup;

namespace NTranslate.App.Tests.Popup;

public sealed class PopupLifecycleTests
{
    [Fact]
    public void Close_CancelsWorkBeforeHiding()
    {
        var calls = new List<string>();
        var lifecycle = new PopupLifecycle(() => calls.Add("cancel"), () => calls.Add("hide"));

        lifecycle.Close();

        Assert.Equal(["cancel", "hide"], calls);
    }

    [Fact]
    public void Deactivate_ClosesOnlyWhenUnpinned()
    {
        var hidden = 0;
        var lifecycle = new PopupLifecycle(() => { }, () => hidden++);

        lifecycle.IsPinned = true;
        lifecycle.Deactivate();
        lifecycle.IsPinned = false;
        lifecycle.Deactivate();

        Assert.Equal(1, hidden);
    }

    [Fact]
    public void Drag_PinsPopup()
    {
        var lifecycle = new PopupLifecycle(() => { }, () => { });

        lifecycle.Drag();

        Assert.True(lifecycle.IsPinned);
    }
}
