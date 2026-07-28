using Microsoft.UI.Dispatching;

namespace NTranslate.App;

internal sealed class UiActivationGate(DispatcherQueue dispatcher, Action show)
{
    private readonly ActivationGate _gate = new(() => dispatcher.TryEnqueue(() => show()));
    public void Activate() => _gate.Activate();
    public void Ready() => _gate.Ready();
}
