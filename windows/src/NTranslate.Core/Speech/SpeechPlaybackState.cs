namespace NTranslate.Core.Speech;

public sealed class SpeechPlaybackState
{
    private readonly ChannelState[] channels = [new(), new()];

    public long BeginLoading(SpeechIdentity identity)
    {
        var state = State(identity.CacheKey.Channel);
        state.Generation++;
        state.Phase = SpeechPhase.Loading;
        state.Identity = identity;
        return state.Generation;
    }

    public bool IsLoading(SpeechIdentity identity, long generation)
    {
        var state = State(identity.CacheKey.Channel);
        return state.Phase == SpeechPhase.Loading && state.Identity == identity && state.Generation == generation;
    }

    public bool MarkPlaying(SpeechIdentity identity, long generation) =>
        TransitionLoading(identity, generation, SpeechPhase.Playing);

    public bool MarkFailed(SpeechIdentity identity, long generation) =>
        TransitionLoading(identity, generation, SpeechPhase.Failed);

    public bool Pause(SpeechIdentity identity) =>
        Transition(identity, SpeechPhase.Playing, SpeechPhase.Paused);

    public bool Resume(SpeechIdentity identity) =>
        Transition(identity, SpeechPhase.Paused, SpeechPhase.Playing);

    public bool Finish(SpeechIdentity identity)
    {
        var state = State(identity.CacheKey.Channel);
        if (state.Identity != identity || state.Phase is not (SpeechPhase.Playing or SpeechPhase.Paused))
            return false;
        state.Generation++;
        state.Phase = SpeechPhase.Idle;
        state.Identity = null;
        return true;
    }

    public void Invalidate(SpeechChannel channel)
    {
        var state = State(channel);
        state.Generation++;
        state.Phase = SpeechPhase.Idle;
        state.Identity = null;
    }

    public SpeechPhase PhaseFor(SpeechChannel channel) => State(channel).Phase;

    public SpeechButtonAction ActionFor(SpeechIdentity identity)
    {
        var state = State(identity.CacheKey.Channel);
        if (state.Identity != identity)
            return SpeechButtonAction.Play;
        return state.Phase switch
        {
            SpeechPhase.Loading => SpeechButtonAction.Loading,
            SpeechPhase.Playing => SpeechButtonAction.Pause,
            SpeechPhase.Paused => SpeechButtonAction.Resume,
            SpeechPhase.Failed => SpeechButtonAction.Retry,
            _ => SpeechButtonAction.Play
        };
    }

    private bool TransitionLoading(SpeechIdentity identity, long generation, SpeechPhase phase)
    {
        var state = State(identity.CacheKey.Channel);
        if (state.Phase != SpeechPhase.Loading || state.Identity != identity || state.Generation != generation)
            return false;
        state.Phase = phase;
        return true;
    }

    private bool Transition(SpeechIdentity identity, SpeechPhase from, SpeechPhase to)
    {
        var state = State(identity.CacheKey.Channel);
        if (state.Phase != from || state.Identity != identity)
            return false;
        state.Phase = to;
        return true;
    }

    private ChannelState State(SpeechChannel channel) => channels[(int)channel];

    private sealed class ChannelState
    {
        public long Generation { get; set; }
        public SpeechPhase Phase { get; set; }
        public SpeechIdentity? Identity { get; set; }
    }
}
