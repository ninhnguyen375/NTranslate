# Windows Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create Windows solution, portable Core behavior, OpenAI-compatible client, shared parity fixtures, and Credential Locker API-key storage.

**Architecture:** `NTranslate.Core` contains platform-free models and policies. `NTranslate.Platform` contains Windows adapters. Shared JSON fixtures define observable parity with the existing Swift implementation without cross-language FFI.

**Tech Stack:** .NET 10, C# 14, xUnit, `HttpClient`, `System.Text.Json`, Windows Runtime Credential Locker

## Global Constraints

- Support Windows 10 22H2 build 19045 or newer, x64 first.
- Keep existing Swift/AppKit app unchanged.
- Use BCL and native Windows APIs before packages.
- Enable nullable references, implicit usings, deterministic builds, and warnings as errors.
- Never serialize, log, fixture, or commit an API key.
- Every production change starts with a failing focused test.
- Do not run `./install-app.sh`; it only builds macOS `NTranslate.app`.

---

## File Map

- `windows/NTranslate.slnx`: solution membership.
- `windows/Directory.Build.props`: shared .NET compiler/build settings.
- `windows/src/NTranslate.Core/NTranslate.Core.csproj`: platform-free library.
- `windows/src/NTranslate.Core/Configuration/AppConfig.cs`: config records/defaults/validation.
- `windows/src/NTranslate.Core/Configuration/ConfigJson.cs`: secret-free JSON and legacy-key extraction.
- `windows/src/NTranslate.Core/Languages/LanguagePolicy.cs`: detection, pair resolution, swap.
- `windows/src/NTranslate.Core/Prompts/PromptRenderer.cs`: mode and placeholder rendering.
- `windows/src/NTranslate.Core/OpenAI/OpenAiModels.cs`: chat, image, speech DTOs and errors.
- `windows/src/NTranslate.Core/OpenAI/OpenAiCompatibleClient.cs`: HTTP transport.
- `windows/src/NTranslate.Core/Credentials/IApiKeyStore.cs`: credential boundary.
- `windows/src/NTranslate.Platform/NTranslate.Platform.csproj`: Windows adapter library.
- `windows/src/NTranslate.Platform/Credentials/CredentialLockerApiKeyStore.cs`: Credential Locker adapter.
- `windows/tests/NTranslate.Core.Tests/`: focused unit/contract tests.
- `windows/tests/NTranslate.Platform.Tests/`: Windows integration tests.
- `shared/contracts/`: JSON schemas and parity vectors.

### Shared interfaces

```csharp
public sealed record HotkeyConfig(string Key, bool Option, bool Command, bool Control, bool Shift);
public sealed record UiConfig(double Width, double Height, bool AutoCopy, bool SimulateCopy);
public sealed record ConfigValidationIssue(string Field, string Message);

public sealed record AppConfig(
    string ApiBaseUrl,
    string ApiSpeechUrl,
    string Model,
    string SourceLang,
    string TargetLang,
    string NativeLang,
    IReadOnlyList<string> Languages,
    IReadOnlyList<string> TargetLanguages,
    int MaxTranslateLength,
    string SystemPrompt,
    string LearnPrompt,
    string SentenceLearnPrompt,
    string GrammarPrompt,
    bool AutoPrefetchSpeech,
    string SpeechSourceModel,
    string SpeechSourceModelVietnamese,
    string SpeechSourceModelChinese,
    string SpeechTargetModel,
    string? HistoryDirectory,
    HotkeyConfig Hotkey,
    UiConfig Ui)
{
    public static AppConfig Default { get; }
    public IReadOnlyList<ConfigValidationIssue> Validate();
}

public sealed record LegacyConfigParseResult(AppConfig Config, string? LegacyApiKey, bool RequiresRewrite);

public interface IApiKeyStore
{
    Task<string?> LoadAsync(CancellationToken cancellationToken = default);
    Task SaveAsync(string apiKey, CancellationToken cancellationToken = default);
    Task DeleteAsync(CancellationToken cancellationToken = default);
}
```

### Task 1: Create solution and shared parity fixture harness

**Files:**
- Create: `windows/NTranslate.slnx`
- Create: `windows/Directory.Build.props`
- Create: four project files under `windows/src` and `windows/tests`
- Create: `windows/tests/NTranslate.Core.Tests/SharedFixtureLoader.cs`
- Create: `windows/tests/NTranslate.Core.Tests/SharedFixtureLoaderTests.cs`
- Create: `shared/contracts/config.schema.json`
- Create: `shared/contracts/prompt-vectors.json`
- Create: `shared/contracts/language-vectors.json`
- Create: `shared/contracts/openai-chat-vectors.json`
- Create: `shared/contracts/openai-speech-vectors.json`

**Interfaces:**
- Produces: `SharedFixtureLoader.Load(string name) -> JsonDocument` for Core tests.
- Consumes: repository root containing `.git` and `shared/contracts`.

- [ ] **Step 1: Create solution/projects only, then write failing fixture test**

Use `dotnet new sln --format slnx`, `dotnet new classlib`, and `dotnet new xunit`; remove generated `Class1.cs` and `UnitTest1.cs`. Test:

```csharp
public sealed class SharedFixtureLoaderTests
{
    [Theory]
    [InlineData("config.schema.json")]
    [InlineData("prompt-vectors.json")]
    [InlineData("language-vectors.json")]
    [InlineData("openai-chat-vectors.json")]
    [InlineData("openai-speech-vectors.json")]
    public void LoadsSecretFreeJson(string name)
    {
        using var document = SharedFixtureLoader.Load(name);
        var json = document.RootElement.GetRawText();
        Assert.DoesNotContain("sk-", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("Bearer ", json, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("\"apiKey\"", json, StringComparison.OrdinalIgnoreCase);
    }
}
```

- [ ] **Step 2: Verify RED**

```powershell
dotnet test .\windows\NTranslate.slnx --filter FullyQualifiedName~SharedFixtureLoaderTests
```

Expected: FAIL because `SharedFixtureLoader` or fixtures do not exist.

- [ ] **Step 3: Add build settings and fixture loader**

`windows/Directory.Build.props`:

```xml
<Project>
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <LangVersion>14</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <Deterministic>true</Deterministic>
  </PropertyGroup>
</Project>
```

Platform projects override target with `net10.0-windows10.0.19041.0`. Platform references Core. Test projects reference their production project; Platform tests also reference Core.

```csharp
internal static class SharedFixtureLoader
{
    internal static JsonDocument Load(string name)
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var path = Path.Combine(directory.FullName, "shared", "contracts", name);
            if (Directory.Exists(Path.Combine(directory.FullName, ".git")) && File.Exists(path))
                return JsonDocument.Parse(File.ReadAllText(path));
            directory = directory.Parent;
        }
        throw new DirectoryNotFoundException($"Repository root not found for fixture {name}.");
    }
}
```

Add deterministic vectors for config fields, prompt replacement/mode, English/Vietnamese/Chinese detection, text/image chat, speech bytes, blank completion, HTTP 401 and 429. Use fake key `test-key` only in test source, never fixture data.

- [ ] **Step 4: Verify GREEN**

```powershell
dotnet restore .\windows\NTranslate.slnx
dotnet test .\windows\NTranslate.slnx -c Release --filter FullyQualifiedName~SharedFixtureLoaderTests
```

Expected: all fixture-loader tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add windows shared/contracts
git commit -m "feat(windows): add core solution and parity fixtures`n`nCo-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 2: Add secret-free config

**Files:**
- Create: `windows/src/NTranslate.Core/Configuration/AppConfig.cs`
- Create: `windows/src/NTranslate.Core/Configuration/ConfigJson.cs`
- Create: `windows/src/NTranslate.Core/Configuration/ConfigValidationIssue.cs`
- Create: `windows/tests/NTranslate.Core.Tests/Configuration/AppConfigTests.cs`

**Interfaces:**
- Produces: `AppConfig.Default`, `AppConfig.Validate()`, `ConfigJson.Serialize(AppConfig)`, `ConfigJson.Parse(string)`.
- Consumes: defaults from `config.json.example`, excluding `apiKey`.

- [ ] **Step 1: Write failing tests**

```csharp
[Fact]
public void LegacyKeyIsExtractedButNeverSerialized()
{
    var json = """{"apiBaseURL":"http://localhost/v1/chat/completions","apiKey":"legacy-secret"}""";
    var parsed = ConfigJson.Parse(json);
    Assert.Equal("legacy-secret", parsed.LegacyApiKey);
    Assert.True(parsed.RequiresRewrite);
    Assert.DoesNotContain("apiKey", ConfigJson.Serialize(parsed.Config), StringComparison.OrdinalIgnoreCase);
}

[Fact]
public void ValidationRejectsUnsafeOrEmptyValues()
{
    var config = AppConfig.Default with
    {
        ApiBaseUrl = "file:///tmp/key",
        Model = " ",
        MaxTranslateLength = 0,
        Hotkey = new("1", false, false, false, false),
        Ui = new(0, -1, false, false)
    };
    Assert.Equal(new[] { "ApiBaseUrl", "Model", "MaxTranslateLength", "Hotkey.Key", "Hotkey.Modifiers", "Ui.Width", "Ui.Height" },
        config.Validate().Select(issue => issue.Field));
}
```

Also test duplicate languages, unknown selected languages, absent speech URL derivation, unknown JSON-field tolerance, deterministic camel-case output, and no secret field.

- [ ] **Step 2: Verify RED**

```powershell
dotnet test .\windows\NTranslate.slnx --filter FullyQualifiedName~AppConfigTests
```

Expected: compile FAIL for absent config types.

- [ ] **Step 3: Implement minimum config model and JSON**

Use `JsonSerializerOptions` with camel case, indentation, trailing comma rejection, and case-insensitive input. Parse legacy JSON once with `JsonDocument` to extract `apiKey`; deserialize remaining fields with defaults. Only accept absolute `http`/`https` endpoints. Keep filesystem writes outside Core.

```csharp
public static class ConfigJson
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };

    public static string Serialize(AppConfig config) => JsonSerializer.Serialize(config, Options);

    public static LegacyConfigParseResult Parse(string json)
    {
        using var document = JsonDocument.Parse(json);
        var legacyKey = document.RootElement.TryGetProperty("apiKey", out var key) ? key.GetString()?.Trim() : null;
        var config = JsonSerializer.Deserialize<AppConfig>(json, Options) ?? AppConfig.Default;
        return new(config, string.IsNullOrWhiteSpace(legacyKey) ? null : legacyKey, key.ValueKind != JsonValueKind.Undefined);
    }
}
```

- [ ] **Step 4: Verify GREEN**

```powershell
dotnet test .\windows\NTranslate.slnx -c Release --filter FullyQualifiedName~AppConfigTests
```

Expected: all config tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add windows/src/NTranslate.Core/Configuration windows/tests/NTranslate.Core.Tests/Configuration
git commit -m "feat(windows): add secure app configuration`n`nCo-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 3: Add language and prompt policy

**Files:**
- Create: `windows/src/NTranslate.Core/Languages/LanguagePolicy.cs`
- Create: `windows/src/NTranslate.Core/Prompts/PromptRenderer.cs`
- Create: `windows/tests/NTranslate.Core.Tests/Languages/LanguagePolicyTests.cs`
- Create: `windows/tests/NTranslate.Core.Tests/Prompts/PromptRendererTests.cs`

**Interfaces:**
- Produces: `LanguagePair`, `LanguagePolicy.Detect/ResolvePair/SwapPair`, `PromptMode`, `PromptRenderer.SelectMode/RenderTranslation/RenderGrammar/RenderLearn`.
- Consumes: `AppConfig` and shared vectors.

- [ ] **Step 1: Write vector-driven failing tests**

```csharp
[Theory]
[InlineData("hello", "English")]
[InlineData("xin chào", "Vietnamese")]
[InlineData("你好", "Chinese")]
public void DetectsSupportedLanguage(string text, string expected) =>
    Assert.Equal(expected, LanguagePolicy.Detect(text));

[Theory]
[InlineData("word", PromptMode.LearnWord)]
[InlineData("two words", PromptMode.LearnSentence)]
public void SelectsLearnPromptByWhitespaceTokenCount(string text, PromptMode expected) =>
    Assert.Equal(expected, PromptRenderer.SelectLearnMode(text));
```

Add tests for same-language grammar, auto-detected target avoiding source, recent target preference, native fallback, swap, and exact replacement of four supported placeholders only.

- [ ] **Step 2: Verify RED**

```powershell
dotnet test .\windows\NTranslate.slnx --filter "FullyQualifiedName~LanguagePolicyTests|FullyQualifiedName~PromptRendererTests"
```

Expected: compile FAIL for absent policies.

- [ ] **Step 3: Implement parity policy**

Detect Vietnamese via normalized diacritic set, Chinese via Unicode scalar range `U+4E00...U+9FFF`, English fallback. Keep detection deterministic and dependency-free. Resolve Auto detect before selecting a target; choose first recent target different from source, then configured target, then native/first available target.

```csharp
public enum PromptMode { Translate, Grammar, LearnWord, LearnSentence }

public static PromptMode SelectMode(string text, string source, string target, bool learn) =>
    learn
        ? (text.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries).Length == 1 ? PromptMode.LearnWord : PromptMode.LearnSentence)
        : string.Equals(source, target, StringComparison.OrdinalIgnoreCase) ? PromptMode.Grammar : PromptMode.Translate;
```

Render only `{{config.sourceLang}}`, `{{config.targetLang}}`, `{{config.nativeLang}}`, and `{{lang}}` with ordinal replacement.

- [ ] **Step 4: Verify GREEN**

```powershell
dotnet test .\windows\NTranslate.slnx -c Release --filter "FullyQualifiedName~LanguagePolicyTests|FullyQualifiedName~PromptRendererTests"
```

Expected: all policy tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add windows/src/NTranslate.Core/Languages windows/src/NTranslate.Core/Prompts windows/tests/NTranslate.Core.Tests/Languages windows/tests/NTranslate.Core.Tests/Prompts
git commit -m "feat(windows): add language and prompt policies`n`nCo-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 4: Add OpenAI-compatible HTTP client

**Files:**
- Create: `windows/src/NTranslate.Core/OpenAI/OpenAiModels.cs`
- Create: `windows/src/NTranslate.Core/OpenAI/OpenAiCompatibleClient.cs`
- Create: `windows/tests/NTranslate.Core.Tests/OpenAI/OpenAiCompatibleClientTests.cs`

**Interfaces:**
- Produces: `CompleteChatAsync`, `SynthesizeSpeechAsync`, typed requests/errors.
- Consumes: caller-owned `HttpClient`, URI, key, and cancellation token.

```csharp
public sealed record ChatCompletionRequest(string Model, string SystemPrompt, ChatInput Input);
public abstract record ChatInput;
public sealed record TextChatInput(string Text) : ChatInput;
public sealed record ImageChatInput(byte[] PngBytes, string TargetLanguage) : ChatInput;
public sealed record SpeechRequest(string Model, string Input);
```

- [ ] **Step 1: Write failing transport tests**

Use a test `HttpMessageHandler` that captures request headers/body and returns deterministic responses. Assert bearer auth, `stream:false`, selected-text wrapper, ordered text/image parts, trimmed result, exact speech bytes, cancellation, empty-response error, malformed schema, 401/429 status, 4096-character error cap, and no key in exceptions.

- [ ] **Step 2: Verify RED**

```powershell
dotnet test .\windows\NTranslate.slnx --filter FullyQualifiedName~OpenAiCompatibleClientTests
```

Expected: compile FAIL for absent client/models.

- [ ] **Step 3: Implement client**

```csharp
public sealed class OpenAiCompatibleClient(HttpClient httpClient)
{
    public Task<string> CompleteChatAsync(Uri endpoint, string apiKey, ChatCompletionRequest request, CancellationToken cancellationToken);
    public Task<byte[]> SynthesizeSpeechAsync(Uri endpoint, string apiKey, SpeechRequest request, CancellationToken cancellationToken);
}
```

Build request bodies with `Utf8JsonWriter`. Send with `HttpCompletionOption.ResponseHeadersRead`. Reject blank URI/key/model/input before network. Parse `choices[0].message.content`; reject blank content. On non-success, retain at most 4096 response characters and never include authorization data.

- [ ] **Step 4: Verify GREEN**

```powershell
dotnet test .\windows\NTranslate.slnx -c Release --filter FullyQualifiedName~OpenAiCompatibleClientTests
```

Expected: all HTTP tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add windows/src/NTranslate.Core/OpenAI windows/tests/NTranslate.Core.Tests/OpenAI
git commit -m "feat(windows): add OpenAI-compatible client`n`nCo-Authored-By: Claude <noreply@anthropic.com>"
```

### Task 5: Add Credential Locker adapter

**Files:**
- Create: `windows/src/NTranslate.Core/Credentials/IApiKeyStore.cs`
- Create: `windows/src/NTranslate.Platform/Credentials/CredentialLockerApiKeyStore.cs`
- Create: `windows/tests/NTranslate.Platform.Tests/Credentials/CredentialLockerApiKeyStoreTests.cs`

**Interfaces:**
- Produces: exact `IApiKeyStore` interface above and `CredentialLockerApiKeyStore`.
- Consumes: Windows `PasswordVault`.

- [ ] **Step 1: Write serialized integration test**

Use unique resource `local.ninh.ntranslate.tests.<GUID>` and username `apiKey`. Assert missing load, save/load, update, whitespace-delete, idempotent delete, and exact cleanup in `finally`.

- [ ] **Step 2: Verify RED**

```powershell
dotnet test .\windows\NTranslate.slnx --filter FullyQualifiedName~CredentialLockerApiKeyStoreTests
```

Expected: compile FAIL for absent store.

- [ ] **Step 3: Implement exact credential operations**

```csharp
public sealed class CredentialLockerApiKeyStore(string resource = DefaultResource, string userName = DefaultUserName) : IApiKeyStore
{
    public const string DefaultResource = "local.ninh.ntranslate";
    public const string DefaultUserName = "apiKey";

    public Task<string?> LoadAsync(CancellationToken cancellationToken = default);
    public Task SaveAsync(string apiKey, CancellationToken cancellationToken = default);
    public Task DeleteAsync(CancellationToken cancellationToken = default);
}
```

`LoadAsync` retrieves exact resource/user and calls `RetrievePassword`; item-not-found returns null. Save trims input, removes existing exact item, and adds `PasswordCredential`; blank delegates to delete. Delete is idempotent. Wrap other WinRT failures in `CredentialStoreException` without secret text.

- [ ] **Step 4: Verify GREEN twice**

```powershell
dotnet test .\windows\NTranslate.slnx -c Release --filter FullyQualifiedName~CredentialLockerApiKeyStoreTests
dotnet test .\windows\NTranslate.slnx -c Release
```

Expected: all tests PASS twice; no test credentials remain.

- [ ] **Step 5: Commit**

```powershell
git add windows/src/NTranslate.Core/Credentials windows/src/NTranslate.Platform/Credentials windows/tests/NTranslate.Platform.Tests/Credentials
git commit -m "feat(windows): store API keys in Credential Locker`n`nCo-Authored-By: Claude <noreply@anthropic.com>"
```

## Plan Verification

```powershell
dotnet restore .\windows\NTranslate.slnx
dotnet test .\windows\NTranslate.slnx -c Release
git status --short
```

Expected: restore succeeds, all tests pass, only later-plan files may remain uncommitted.
