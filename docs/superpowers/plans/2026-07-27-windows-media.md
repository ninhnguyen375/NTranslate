# Windows Learn, Image, and Speech Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Learn, grammar, image translation/search, TTS, memory/audio cache, and stale-request protection to Windows translator.

**Architecture:** Core owns modes, request coordination, speech policy, and orchestration. Platform owns image normalization, browser launch, and Windows media playback. App ViewModel binds these services without embedding API or cache logic.

**Tech Stack:** .NET 10, C# 14, WinUI 3, Windows Imaging APIs, `Windows.Media.Playback.MediaPlayer`, xUnit

## Global Constraints

- Windows 10 22H2 build 19045+, x64.
- Image decoded limit: 100 MiB; normalized PNG limit: 10 MiB.
- Image and Learn operations never create history; grammar translation does.
- Every async public operation accepts `CancellationToken`.
- Generation check gates every UI mutation; cancellation alone is insufficient.
- Never log source text, image data/base64, speech text, bearer token, or API key.
- No third-party HTTP, image, browser, cache, or media dependency.

---

## File Map

- `NTranslate.Core/Translation/TranslationContracts.cs`: operation contracts.
- `NTranslate.Core/Translation/RequestCoordinator.cs`: cancellation/generation leases.
- `NTranslate.Core/Translation/ImageSearchPolicy.cs`: safe query fallback/URL.
- `NTranslate.Core/Speech/*`: model/rate/state/cache coordination.
- `NTranslate.Platform/Images/WindowsImageNormalizer.cs`: bounded PNG normalization.
- `NTranslate.Platform/Shell/WindowsBrowserLauncher.cs`: HTTPS Google Images launch.
- `NTranslate.Platform/Media/WindowsSpeechPlayer.cs`: audio validation/playback.
- `NTranslate.App/ViewModels/TranslatorViewModel.cs`: feature orchestration.
- `NTranslate.App/Views/TranslatorWindow.xaml(.cs)`: controls and lifecycle bridge.

### Task 1: Add translation operation contracts and generation gate

**Files:**
- Create: `windows/src/NTranslate.Core/Translation/TranslationContracts.cs`
- Create: `windows/src/NTranslate.Core/Translation/RequestCoordinator.cs`
- Test: `windows/tests/NTranslate.Core.Tests/Translation/RequestCoordinatorTests.cs`

**Interfaces:**

```csharp
public enum TranslationMode { Translate, Learn, ImageTranslate, ImageSearch }
public sealed record TextTranslationRequest(string Text, string SourceLanguage, string TargetLanguage, TranslationMode Mode);
public sealed record ImageTranslationRequest(ReadOnlyMemory<byte> PngData, string TargetLanguage);
public sealed record TranslationResult(string Text);

public readonly record struct RequestGeneration(long Value);
public sealed class RequestCoordinator : IDisposable
{
    public RequestGeneration Current { get; }
    public bool IsInFlight { get; }
    public RequestLease Begin(CancellationToken outerCancellationToken = default);
    public bool Accepts(RequestGeneration generation);
    public void CancelCurrent();
}
```

- [ ] Write tests proving `Begin` cancels old lease, generation always increases, old completion cannot clear a new request, `CancelCurrent` rejects old results, and dispose cancels active token. Use `TaskCompletionSource`, no timing sleeps.
- [ ] Run `dotnet test .\windows\NTranslate.slnx --filter FullyQualifiedName~RequestCoordinatorTests`; expect compile FAIL.
- [ ] Implement lock-protected state. Call `CancellationTokenSource.Cancel()` outside lock. `RequestLease.TryComplete()` succeeds exactly once only for current generation.
- [ ] Re-run focused test; expect PASS.
- [ ] Commit `feat(windows): reject stale translation requests` with required co-author trailer.

### Task 2: Add bounded Windows image normalization

**Files:**
- Create: `windows/src/NTranslate.Platform/Images/IImageNormalizer.cs`
- Create: `windows/src/NTranslate.Platform/Images/WindowsImageNormalizer.cs`
- Test: `windows/tests/NTranslate.Platform.Tests/Images/WindowsImageNormalizerTests.cs`
- Create: tiny valid/invalid fixtures under `shared/contracts/fixtures/images/`

```csharp
public sealed record NormalizedImage(ReadOnlyMemory<byte> PngData, uint PixelWidth, uint PixelHeight);
public interface IImageNormalizer
{
    Task<NormalizedImage> NormalizePngAsync(Stream source, CancellationToken cancellationToken);
}
```

- [ ] Write tests for PNG signature/dimensions, invalid raster, overflow-safe decoded size, >10 MiB encoded rejection, and cancellation.
- [ ] Run focused test; expect compile FAIL.
- [ ] Implement with `BitmapDecoder`, BGRA8 premultiplied decode, and `BitmapEncoder.PngEncoderId`. Before decode enforce `(ulong)width * height <= (100UL * 1024 * 1024) / 4`; after encode enforce `<= 10 * 1024 * 1024`. Check cancellation around each WinRT stage.
- [ ] Run focused test; expect PASS on build 19045.
- [ ] Commit `feat(windows): normalize clipboard images safely`.

### Task 3: Add image search policy and launcher

**Files:**
- Create: `windows/src/NTranslate.Core/Translation/ImageSearchPolicy.cs`
- Create: `windows/src/NTranslate.Platform/Shell/IBrowserLauncher.cs`
- Create: `windows/src/NTranslate.Platform/Shell/WindowsBrowserLauncher.cs`
- Test: matching Core and Platform test files.

```csharp
public static class ImageSearchPolicy
{
    public static string ResolveQuery(string? generatedQuery, string fallbackText);
    public static Uri CreateGoogleImagesUri(string query);
}
public interface IBrowserLauncher { Task OpenAsync(Uri uri, CancellationToken cancellationToken); }
```

- [ ] Write tests for generated query preference, blank/error fallback, Unicode query escaping, `tbm=isch`, rejection of non-HTTPS/non-Google hosts, and pre-cancellation.
- [ ] Run focused tests; expect compile FAIL.
- [ ] Build URL `https://www.google.com/search?tbm=isch&q={Uri.EscapeDataString(query)}`. Launch through `ProcessStartInfo { UseShellExecute = true }` only after validation.
- [ ] Re-run focused tests; expect PASS.
- [ ] Commit `feat(windows): add contextual image search`.

### Task 4: Add speech state, model, and rate policies

**Files:**
- Create: `windows/src/NTranslate.Core/Speech/SpeechContracts.cs`
- Create: `SpeechPlaybackState.cs`, `SpeechModelResolver.cs`, `SpeechRatePolicy.cs`
- Test: matching Core speech tests.

```csharp
public enum SpeechChannel { Source, Result }
public enum SpeechPhase { Idle, Loading, Playing, Paused, Failed }
public enum SpeechButtonAction { Play, Loading, Pause, Resume, Retry }
public readonly record struct SpeechCacheKey(SpeechChannel Channel, string Text, string Model);
public sealed record SpeechIdentity(SpeechCacheKey CacheKey, Guid? HistoryRecordId);
```

- [ ] Write tests for independent channels, load/play/pause/resume/finish, wrong identity rejection, stale generation rejection, failed-to-retry mapping, Vietnamese/Chinese/default model mapping, and rates `0.5...1.5` in `0.1` increments with invalid fallback `1.0`.
- [ ] Run focused tests; expect compile FAIL.
- [ ] Implement state per channel. Keep `HistoryRecordId` outside memory-cache identity so same text/model bytes can attach to later record.
- [ ] Re-run focused tests; expect PASS.
- [ ] Commit `feat(windows): add speech playback state`.

### Task 5: Add Windows speech player

**Files:**
- Create: `windows/src/NTranslate.Platform/Media/ISpeechPlayer.cs`
- Create: `windows/src/NTranslate.Platform/Media/WindowsSpeechPlayer.cs`
- Test: `windows/tests/NTranslate.Platform.Tests/Media/WindowsSpeechPlayerTests.cs`
- Create: short valid MP3 and invalid bytes fixtures.

```csharp
public interface ISpeechPlayer : IAsyncDisposable
{
    event EventHandler? PlaybackEnded;
    event EventHandler<Exception>? PlaybackFailed;
    Task ValidateAsync(ReadOnlyMemory<byte> audio, CancellationToken cancellationToken);
    Task PlayAsync(SpeechChannel channel, ReadOnlyMemory<byte> audio, double rate, CancellationToken cancellationToken);
    void Pause();
    void Resume();
    void Stop();
    void SetRate(double rate);
}
```

- [ ] Write tests for valid/invalid audio, cancellation, normalized playback rate, stop clearing active channel, and event unsubscription on disposal.
- [ ] Run focused tests; expect compile FAIL.
- [ ] Implement one `MediaPlayer`, `InMemoryRandomAccessStream`, and `MediaSource`. Wait for media open before changing state. New channel stops old playback. Unsubscribe all WinRT events in `DisposeAsync`.
- [ ] Re-run focused tests; expect PASS or exact documented interactive-media skip only if Windows runner cannot initialize media.
- [ ] Commit `feat(windows): validate and play speech audio`.

### Task 6: Add speech coordinator and cache

**Files:**
- Create: `windows/src/NTranslate.Core/Speech/SpeechCoordinator.cs`
- Test: `windows/tests/NTranslate.Core.Tests/Speech/SpeechCoordinatorTests.cs`
- Create focused fake API/player/history stores.

```csharp
public sealed class SpeechCoordinator : IAsyncDisposable
{
    public event EventHandler<string>? NonFatalError;
    public Task PrefetchAsync(SpeechIdentity identity, CancellationToken cancellationToken);
    public Task TogglePlaybackAsync(SpeechIdentity identity, double rate, CancellationToken cancellationToken);
    public void Invalidate(SpeechChannel channel, bool stopPlayback);
    public void InvalidateAll(bool stopPlayback);
}
```

- [ ] Write tests: fetch/validate/cache/play; second play no network; invalid audio no cache/history; pause/resume no fetch; source/result cancellation independent; stale fetch cannot play; prefetch does not play; exact history record/kind attachment; cancellation returns idle; history attach failure preserves memory cache and raises nonfatal error.
- [ ] Run focused tests; expect compile FAIL.
- [ ] Implement session dictionary keyed by `SpeechCacheKey`. Do not add LRU or global disk cache. Attach only validated bytes and only when identity has matching history record.
- [ ] Re-run focused tests; expect PASS.
- [ ] Commit `feat(windows): add speech prefetch and cache`.

### Task 7: Integrate advanced translator flows

**Files:**
- Modify: `windows/src/NTranslate.App/ViewModels/TranslatorViewModel.cs`
- Test: `windows/tests/NTranslate.App.Tests/ViewModels/TranslatorViewModelTests.cs`

**Behavior:**
- Translate same source/target invokes grammar and records history.
- Learn chooses one-token/sentence prompt and never records history.
- Image mode clears source association; disables source language/Learn/source speech/history; keeps target and result speech.
- Search generated query falls back to source on API failure but never opens after cancellation.
- Source/language/image/window changes cancel translation and both relevant speech operations.
- Optional speech prefetch occurs only after accepted successful text translation.

- [ ] Add deterministic ViewModel tests for every behavior above plus “second request wins when first completes last.”
- [ ] Run focused App tests; expect FAIL.
- [ ] Wire `RequestCoordinator`, existing `OpenAiCompatibleClient`, `IImageNormalizer`, `IBrowserLauncher`, `SpeechCoordinator`, and history boundary. Check lease before result, history, status, browser, or speech UI mutation.
- [ ] Re-run focused tests; expect PASS.
- [ ] Commit `feat(windows): integrate learn image and speech flows`.

### Task 8: Expose Fluent controls and lifecycle cancellation

**Files:**
- Modify: `windows/src/NTranslate.App/Views/TranslatorWindow.xaml`
- Modify: `windows/src/NTranslate.App/Views/TranslatorWindow.xaml.cs`
- Test: App accessibility/binding tests.

- [ ] Write tests asserting accessible names, image preview name, independent speech bindings, `Ctrl+Enter`, `Ctrl+Shift+L`, `Ctrl+Shift+C`, and close cancellation.
- [ ] Run focused tests; expect FAIL.
- [ ] Add Translate/Learn/Images/source-result speech/image preview/progress controls. Code-behind only bridges clipboard stream and window events; no prompts/network/cache logic.
- [ ] Re-run tests; expect PASS.
- [ ] Commit `feat(windows): expose learn image and speech controls`.

## Verification

```powershell
dotnet restore .\windows\NTranslate.slnx
dotnet build .\windows\NTranslate.slnx -c Release -p:Platform=x64 --no-restore
dotnet test .\windows\NTranslate.slnx -c Release -p:Platform=x64 --no-build
dotnet test .\windows\tests\NTranslate.Core.Tests\NTranslate.Core.Tests.csproj -c Release --filter "FullyQualifiedName~RequestCoordinatorTests|FullyQualifiedName~SpeechCoordinatorTests" -- RunConfiguration.MaxCpuCount=1
git diff --check
```

Expected: build has zero errors; tests have zero failures; cancellation tests pass deterministically; no secrets or request content appear in diff/logging.
