namespace NTranslate.Core.Speech;

public enum SpeechChannel { Source, Result }
public enum SpeechPhase { Idle, Loading, Playing, Paused, Failed }
public enum SpeechButtonAction { Play, Loading, Pause, Resume, Retry }
public readonly record struct SpeechCacheKey(SpeechChannel Channel, string Text, string Model);
public sealed record SpeechIdentity(SpeechCacheKey CacheKey, Guid? HistoryRecordId);
