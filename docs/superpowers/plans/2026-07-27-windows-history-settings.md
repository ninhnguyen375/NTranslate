# Windows History, Settings, and Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add durable history/bookmarks/audio, complete Settings with transactional credential/config changes, custom storage migration, and crash recovery.

**Architecture:** Core owns records, filters, validation, and transactions. Platform owns atomic files, filesystem containment, Credential Locker, media, and crash logs. App owns Fluent windows and ViewModels.

**Tech Stack:** .NET 10, C# 14, WinUI 3, `System.Text.Json`, PasswordVault, MediaPlayer, xUnit

## Global Constraints

- Default root `%LOCALAPPDATA%\NTranslate`; files `config.json`, `history.json`, `Audio\`, `Logs\`.
- History/config writes use same-directory temporary file then atomic replace.
- Malformed history is read-only and never overwritten.
- Audio paths reject rooted/traversal/reparse-point escape.
- API key only in Credential Locker.
- Settings runtime changes only after validation, credential, config, and migration succeed; failures roll back.
- Custom migration retains source directory in v1.
- No DB, ORM, logging package, audio converter, or MVVM package.

---

### Task 1: Add history records and filters

```csharp
public sealed record TranslationRecord(Guid Id, DateTimeOffset Timestamp, string SourceText, string ResultText, string SourceLanguage, string TargetLanguage, string? SourceAudioPath, string? ResultAudioPath, bool IsSaved);
public enum HistoryTimeRange { All, Today, Last24Hours, Week, Month }
public sealed record HistoryFilterOptions(string Query, bool SavedOnly, HistoryTimeRange TimeRange);
```

- [ ] Write tests for source/result case-insensitive search, Saved-only, local-midnight Today, rolling 24h/week/month boundaries, AND composition, newest-first, and input immutability.
- [ ] Run focused Core tests; expect compile FAIL.
- [ ] Implement `HistoryFilter.Apply(records, options, now, timeZone)`.
- [ ] Re-run; expect PASS.
- [ ] Commit `feat(windows): add history filtering policy`.

### Task 2: Add atomic history/audio store

```csharp
public interface ITranslationHistoryStore
{
    IReadOnlyList<TranslationRecord> Records { get; }
    string? LoadError { get; }
    Task AppendAsync(TranslationRecord record, CancellationToken token = default);
    Task SetSavedAsync(Guid id, bool saved, CancellationToken token = default);
    Task AttachAudioAsync(Guid id, TranslationAudioKind kind, ReadOnlyMemory<byte> data, CancellationToken token = default);
    Task<byte[]?> ReadAudioAsync(Guid id, TranslationAudioKind kind, CancellationToken token = default);
    Task RemoveAsync(IReadOnlySet<Guid> ids, CancellationToken token = default);
}
```

- [ ] Write tests for round trip/order/bookmark, empty fields, malformed/duplicate lockout preserving bytes, owned relative audio, metadata rollback, missing audio, rooted/traversal/reparse rejection, persist-before-delete, unknown record, multi-delete, and atomic-writer cleanup/failure preservation.
- [ ] Run Platform tests; expect compile FAIL.
- [ ] Implement `AtomicFileWriter`: same-dir hidden temp, write-through, flush-to-disk, `File.Replace` existing or `File.Move` new, cleanup on failure. Implement JSON store; update memory only after persistence. Audio filename `Audio\<record>-<kind>-<guid>.audio`; validate every existing ancestor and leaf reparse attributes.
- [ ] Re-run; expect PASS.
- [ ] Commit `feat(windows): persist translation history and audio`.

### Task 3: Add History window

- [ ] Write ViewModel tests for reload/filter, bookmark persist-before-view, audio playback, missing audio error, single/visible deletion with confirmed snapshot, cancel, reopen stopping audio, disposal.
- [ ] Run App tests; expect FAIL.
- [ ] Add search, History/Saved, All/Today/24h/Week/Month, newest list, play/bookmark/delete, Delete visible confirmation, double-click/Enter reopen. Load error shows path and disables mutation.
- [ ] Build XAML and run tests; expect PASS.
- [ ] Commit `feat(windows): add history window actions`.

### Task 4: Complete Settings model and Fluent window

Extend existing `AppConfig` only; do not create duplicate type. Add speech rate and Start with Windows if absent. Keep API key outside model.

- [ ] Write tests covering every field/default, secret-free JSON, URLs/prompts/languages/hotkey/rate/dimensions/custom-path validation, deep Revert, failed Save unchanged runtime, successful Save close request.
- [ ] Run tests; expect FAIL.
- [ ] Add General, Prompts, Languages, Advanced tabs. Edit deep copy. Folder picker initializes with window HWND. Validation errors keep window open. Cancel writes nothing.
- [ ] Build and test; expect PASS.
- [ ] Commit `feat(windows): add complete settings window`.

### Task 5: Add transactional Settings save

```csharp
public interface IConfigStore { Task<AppConfig> LoadAsync(CancellationToken token = default); Task SaveAsync(AppConfig config, CancellationToken token = default); }
public sealed record HistoryMigrationReceipt(string SourceRoot, string DestinationRoot, string StagingRoot);
public interface IHistoryDirectoryMigrator
{
    Task<HistoryMigrationReceipt?> PrepareAsync(string currentRoot, string requestedRoot, CancellationToken token = default);
    Task CommitAsync(HistoryMigrationReceipt receipt, CancellationToken token = default);
    Task RollbackAsync(HistoryMigrationReceipt receipt, CancellationToken token = default);
}
```

- [ ] Write fake-driven tests: validation no I/O; credential failure no config/runtime; config failure restores prior credential or deletes new one; migration/commit failure rolls back; rollback failure reports primary+rollback; success order prepare, credential, config, migration, runtime.
- [ ] Run Core tests; expect FAIL.
- [ ] Implement coordinator exact order. Never invoke runtime callback before commit. Preserve both exceptions in `SettingsCommitException`.
- [ ] Re-run; expect PASS.
- [ ] Commit `feat(windows): save settings with rollback`.

### Task 6: Add custom history migration

- [ ] Write tests for same path, nested rejection, non-empty destination, source-preserving copy, malformed staged history, reparse rejection, atomic destination rename, late collision, rollback ownership, and destination-volume staging.
- [ ] Run Platform tests; expect FAIL.
- [ ] Normalize case-insensitive paths; stage beside destination; copy only `history.json` and `Audio`; do not follow reparse points; validate staged JSON/audio/file sizes. Commit only by directory move; rollback only receipt-owned staging/destination; never delete source.
- [ ] Re-run; expect PASS. Wire runtime store rebuild only after transaction success.
- [ ] Commit `feat(windows): migrate custom history directory safely`.

### Task 7: Add crash logs and one-time recovery

```csharp
public sealed record CrashLogSummary(string FileName, DateTimeOffset Timestamp, string ExceptionType, string Message, string? StackTrace);
public static CrashLogSummary? SelectUnacknowledged(IEnumerable<CrashLogSummary> logs, string? acknowledgedFileName);
```

- [ ] Write tests for newest selection/acknowledgement, parseable JSON, malformed ignore, atomic state, logging failure swallow, and redaction of bearer/key/password/token. Assert translation/clipboard fields absent.
- [ ] Run tests; expect FAIL.
- [ ] Write crash files under `Logs\crash-<UTC>-<guid>.json`; register WinUI, AppDomain, and TaskScheduler handlers. Show one notice for newest unacknowledged file, optional Open logs, then atomically acknowledge.
- [ ] Re-run; expect PASS.
- [ ] Commit `feat(windows): add crash logs and recovery notice`.

## Verification

```powershell
dotnet test .\windows\NTranslate.slnx -c Release -p:Platform=x64
dotnet build .\windows\NTranslate.slnx -c Release -p:Platform=x64 --no-restore
git diff --check
```

Manual checks: text-only history, Learn/image exclusion, bookmark restart, combined filters, cached audio offline, safe deletion, reopen without API, all Settings fields/key masking/Revert, custom-directory success/failure rollback, config excludes key, one-time crash notice, logs exclude secrets/content.
