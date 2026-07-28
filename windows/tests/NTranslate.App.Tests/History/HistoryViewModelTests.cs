using NTranslate.App.History;
using NTranslate.Core.History;

namespace NTranslate.App.Tests.History;

public sealed class HistoryViewModelTests
{
    [Fact]
    public async Task AcceptedTranslationSinkAppendsExactRecord()
    {
        var record = Record("source", "result");
        var store = new FakeStore([]);
        IAcceptedTranslationSink sink = new AcceptedTranslationSink(store);

        await sink.AcceptAsync(record, CancellationToken.None);

        Assert.Equal([record], store.Records);
    }

    [Fact]
    public async Task ReloadAndFiltersUseNewestMatchingRecords()
    {
        var now = new DateTimeOffset(2026, 7, 28, 12, 0, 0, TimeSpan.Zero);
        var saved = Record("saved source", "one", now.AddHours(-1), true);
        var old = Record("other", "saved result", now.AddDays(-8), false);
        var store = new FakeStore([old, saved]);
        await using var vm = Create(store, now);
        await vm.ReloadAsync(CancellationToken.None);
        vm.Query = "saved";
        vm.SavedOnly = true;
        vm.TimeRange = HistoryTimeRange.Last24Hours;
        Assert.Equal([saved], vm.VisibleRecords);
    }

    [Fact]
    public async Task BookmarkPersistsBeforeChangingView()
    {
        var record = Record("source", "result");
        var store = new FakeStore([record]) { BlockSave = true };
        await using var vm = Create(store);
        await vm.ReloadAsync(CancellationToken.None);
        var save = vm.SetSavedAsync(record, true, CancellationToken.None);
        Assert.False(save.IsCompleted);
        Assert.False(vm.VisibleRecords.Single().IsSaved);
        store.ReleaseSave();
        await save;
        Assert.True(vm.VisibleRecords.Single().IsSaved);
    }

    [Fact]
    public async Task PlayReadsCachedAudioAndReportsMissingAudio()
    {
        var record = Record("source", "result") with { SourceAudioPath = "Audio/source.audio" };
        var store = new FakeStore([record]);
        store.Audio[(record.Id, TranslationAudioKind.Source)] = [1, 2, 3];
        var player = new FakeAudioPlayer();
        await using var vm = Create(store, player: player);
        await vm.ReloadAsync(CancellationToken.None);
        await vm.PlayAudioAsync(record, TranslationAudioKind.Source, CancellationToken.None);
        Assert.Equal(new byte[] { 1, 2, 3 }, player.LastAudio);
        await vm.PlayAudioAsync(record, TranslationAudioKind.Result, CancellationToken.None);
        Assert.Equal("Cached audio is unavailable.", vm.ErrorMessage);
    }

    [Fact]
    public async Task DeleteOneUsesConfirmedSnapshotAndCancelDoesNothing()
    {
        var first = Record("first", "one");
        var second = Record("second", "two");
        var store = new FakeStore([first, second]);
        IReadOnlyList<TranslationRecord>? confirmation = null;
        var allow = false;
        await using var vm = Create(store, confirm: (records, _) => { confirmation = records; return Task.FromResult(allow); });
        await vm.ReloadAsync(CancellationToken.None);
        await vm.DeleteAsync(first, CancellationToken.None);
        Assert.Equal([first], confirmation);
        Assert.Equal(2, store.Records.Count);
        allow = true;
        await vm.DeleteAsync(first, CancellationToken.None);
        Assert.Equal([second.Id], store.Records.Select(item => item.Id));
    }

    [Fact]
    public async Task DeleteVisibleUsesSnapshotTakenBeforeConfirmation()
    {
        var first = Record("match one", "one");
        var second = Record("match two", "two");
        var hidden = Record("hidden", "three");
        var store = new FakeStore([first, second, hidden]);
        var confirmation = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        await using var vm = Create(store, confirm: (_, token) => confirmation.Task.WaitAsync(token));
        await vm.ReloadAsync(CancellationToken.None);
        vm.Query = "match";
        var delete = vm.DeleteVisibleAsync(CancellationToken.None);
        vm.Query = "hidden";
        confirmation.SetResult(true);
        await delete;
        Assert.Equal([hidden.Id], store.Records.Select(item => item.Id));
    }

    [Fact]
    public async Task ReopenStopsAudioAndPassesRecordThroughNarrowCallback()
    {
        var record = Record("source", "result");
        var player = new FakeAudioPlayer();
        TranslationRecord? reopened = null;
        await using var vm = Create(new FakeStore([record]), player: player, reopen: (value, _) => { reopened = value; return Task.CompletedTask; });
        await vm.ReopenAsync(record, CancellationToken.None);
        Assert.Equal(1, player.StopCount);
        Assert.Equal(record, reopened);
    }

    [Fact]
    public async Task LoadErrorDisablesMutationAndIncludesStoreMessage()
    {
        var record = Record("source", "result");
        var store = new FakeStore([record]) { LoadError = @"Malformed history: C:\data\history.json" };
        await using var vm = Create(store);
        await vm.ReloadAsync(CancellationToken.None);
        await vm.SetSavedAsync(record, true, CancellationToken.None);
        await vm.DeleteAsync(record, CancellationToken.None);
        Assert.False(vm.CanMutate);
        Assert.Contains(@"C:\data\history.json", vm.ErrorMessage, StringComparison.Ordinal);
        Assert.Empty(store.Calls);
    }

    [Fact]
    public async Task StaleReloadCompletionCannotMutateUi()
    {
        var old = Record("old", "one");
        var current = Record("current", "two");
        var store = new FakeStore([old]);
        var dispatches = new Queue<(Action Action, TaskCompletionSource Completion)>();
        await using var vm = Create(store, dispatch: action => { var completion = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); dispatches.Enqueue((action, completion)); return completion.Task; });
        var first = vm.ReloadAsync(CancellationToken.None);
        store.SetRecords([current]);
        var second = vm.ReloadAsync(CancellationToken.None);
        var stale = dispatches.Dequeue();
        var latest = dispatches.Dequeue();
        latest.Action();
        latest.Completion.SetResult();
        await second;
        stale.Action();
        stale.Completion.SetResult();
        await first;
        Assert.Equal([current], vm.VisibleRecords);
    }

    [Fact]
    public async Task DisposeStopsAndDisposesPlayerAndRejectsLaterOperations()
    {
        var player = new FakeAudioPlayer();
        var vm = Create(new FakeStore([]), player: player);
        await vm.DisposeAsync();
        Assert.Equal(1, player.StopCount);
        Assert.True(player.Disposed);
        await Assert.ThrowsAsync<ObjectDisposedException>(() => vm.ReloadAsync(CancellationToken.None));
    }

    private static HistoryViewModel Create(FakeStore store, DateTimeOffset? now = null, FakeAudioPlayer? player = null,
        Func<IReadOnlyList<TranslationRecord>, CancellationToken, Task<bool>>? confirm = null,
        Func<TranslationRecord, CancellationToken, Task>? reopen = null, Func<Action, Task>? dispatch = null) =>
        new(store, player ?? new FakeAudioPlayer(), confirm ?? ((_, _) => Task.FromResult(true)), reopen ?? ((_, _) => Task.CompletedTask),
            () => now ?? new DateTimeOffset(2026, 7, 28, 12, 0, 0, TimeSpan.Zero), TimeZoneInfo.Utc, dispatch);

    private static TranslationRecord Record(string source, string result, DateTimeOffset? timestamp = null, bool saved = false) =>
        new(Guid.NewGuid(), timestamp ?? DateTimeOffset.UtcNow, source, result, "English", "Vietnamese", null, null, saved);

    private sealed class FakeStore(IEnumerable<TranslationRecord> records) : ITranslationHistoryStore
    {
        private List<TranslationRecord> _records = [.. records];
        private readonly TaskCompletionSource _saveRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public IReadOnlyList<TranslationRecord> Records => _records;
        public string? LoadError { get; set; }
        public bool BlockSave { get; set; }
        public List<string> Calls { get; } = [];
        public Dictionary<(Guid, TranslationAudioKind), byte[]> Audio { get; } = [];
        public void SetRecords(IEnumerable<TranslationRecord> value) => _records = [.. value];
        public void ReleaseSave() => _saveRelease.TrySetResult();
        public Task AppendAsync(TranslationRecord record, CancellationToken token = default) { _records.Add(record); return Task.CompletedTask; }
        public async Task SetSavedAsync(Guid id, bool saved, CancellationToken token = default) { Calls.Add("save"); if (BlockSave) await _saveRelease.Task.WaitAsync(token); _records = _records.Select(record => record.Id == id ? record with { IsSaved = saved } : record).ToList(); }
        public Task AttachAudioAsync(Guid id, TranslationAudioKind kind, ReadOnlyMemory<byte> data, CancellationToken token = default) => throw new NotSupportedException();
        public Task<byte[]?> ReadAudioAsync(Guid id, TranslationAudioKind kind, CancellationToken token = default) { Calls.Add("audio"); return Task.FromResult(Audio.TryGetValue((id, kind), out var data) ? data : null); }
        public Task RemoveAsync(IReadOnlySet<Guid> ids, CancellationToken token = default) { Calls.Add("remove"); _records = _records.Where(record => !ids.Contains(record.Id)).ToList(); return Task.CompletedTask; }
    }

    private sealed class FakeAudioPlayer : IHistoryAudioPlayer
    {
        public byte[]? LastAudio { get; private set; }
        public int StopCount { get; private set; }
        public bool Disposed { get; private set; }
        public Task PlayAsync(ReadOnlyMemory<byte> audio, CancellationToken token) { LastAudio = audio.ToArray(); return Task.CompletedTask; }
        public void Stop() => StopCount++;
        public ValueTask DisposeAsync() { Disposed = true; return ValueTask.CompletedTask; }
    }
}
