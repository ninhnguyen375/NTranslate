using System.Net;
using System.Text;
using System.Text.Json;
using NTranslate.Core.OpenAI;

namespace NTranslate.Core.Tests.OpenAI;

public sealed class OpenAiCompatibleClientTests
{
    private static readonly Uri Endpoint = new("https://example.test/v1/chat/completions");

    [Fact]
    public async Task CompleteChatAsyncSendsAuthenticatedTextRequestAndTrimsResult()
    {
        var handler = new CapturingHandler(_ => JsonResponse("""{"choices":[{"message":{"content":"  xin chào  "}}]}"""));
        var client = new OpenAiCompatibleClient(new HttpClient(handler));

        var result = await client.CompleteChatAsync(
            Endpoint,
            "secret-key",
            new ChatCompletionRequest("test-model", "Translate to Vietnamese.", new TextChatInput("hello")),
            CancellationToken.None);

        Assert.Equal("xin chào", result);
        Assert.NotNull(handler.Request);
        Assert.Equal(HttpMethod.Post, handler.Request.Method);
        Assert.Equal(Endpoint, handler.Request.RequestUri);
        Assert.Equal("Bearer", handler.Request.Headers.Authorization?.Scheme);
        Assert.Equal("secret-key", handler.Request.Headers.Authorization?.Parameter);
        using var body = JsonDocument.Parse(handler.Body!);
        Assert.Equal("test-model", body.RootElement.GetProperty("model").GetString());
        Assert.False(body.RootElement.GetProperty("stream").GetBoolean());
        var messages = body.RootElement.GetProperty("messages");
        Assert.Equal("system", messages[0].GetProperty("role").GetString());
        Assert.Equal("Translate to Vietnamese.", messages[0].GetProperty("content").GetString());
        Assert.Equal("user", messages[1].GetProperty("role").GetString());
        Assert.Equal("<selected-text>hello</selected-text>", messages[1].GetProperty("content").GetString());
    }

    [Fact]
    public async Task CompleteChatAsyncSendsOrderedImageParts()
    {
        var handler = new CapturingHandler(_ => JsonResponse("""{"choices":[{"message":{"content":"done"}}]}"""));
        var client = new OpenAiCompatibleClient(new HttpClient(handler));

        await client.CompleteChatAsync(
            Endpoint,
            "key",
            new ChatCompletionRequest("model", "Read image.", new ImageChatInput(Convert.FromBase64String("iVBORw0KGgo="), "Vietnamese")),
            CancellationToken.None);

        using var body = JsonDocument.Parse(handler.Body!);
        var parts = body.RootElement.GetProperty("messages")[1].GetProperty("content");
        Assert.Equal(2, parts.GetArrayLength());
        Assert.Equal("text", parts[0].GetProperty("type").GetString());
        Assert.Equal("Translate all readable text in this image into Vietnamese. Return only the translation.", parts[0].GetProperty("text").GetString());
        Assert.Equal("image_url", parts[1].GetProperty("type").GetString());
        Assert.Equal("data:image/png;base64,iVBORw0KGgo=", parts[1].GetProperty("image_url").GetProperty("url").GetString());
    }

    [Fact]
    public async Task SynthesizeSpeechAsyncReturnsExactBytes()
    {
        byte[] expected = Convert.FromBase64String("SUQzBAAAAAA=");
        var handler = new CapturingHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(expected) });
        var client = new OpenAiCompatibleClient(new HttpClient(handler));

        var result = await client.SynthesizeSpeechAsync(
            new Uri("https://example.test/v1/audio/speech"),
            "speech-key",
            new SpeechRequest("test-speech-model", "hello"),
            CancellationToken.None);

        Assert.Equal(expected, result);
        Assert.Equal("speech-key", handler.Request!.Headers.Authorization?.Parameter);
        using var body = JsonDocument.Parse(handler.Body!);
        Assert.Equal("test-speech-model", body.RootElement.GetProperty("model").GetString());
        Assert.Equal("hello", body.RootElement.GetProperty("input").GetString());
    }

    [Fact]
    public async Task CompleteChatAsyncPropagatesCancellation()
    {
        var handler = new CapturingHandler(async (_, cancellationToken) =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellationToken);
            return JsonResponse("{}");
        });
        var client = new OpenAiCompatibleClient(new HttpClient(handler));
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() => client.CompleteChatAsync(
            Endpoint,
            "key",
            new ChatCompletionRequest("model", "prompt", new TextChatInput("text")),
            cancellation.Token));
    }

    [Theory]
    [InlineData("{\"choices\":[{\"message\":{\"content\":\"   \"}}]}", OpenAiErrorCode.BlankCompletion)]
    [InlineData("{}", OpenAiErrorCode.InvalidResponse)]
    [InlineData("{\"choices\":{}}", OpenAiErrorCode.InvalidResponse)]
    [InlineData("{\"choices\":[null]}", OpenAiErrorCode.InvalidResponse)]
    [InlineData("not-json", OpenAiErrorCode.InvalidResponse)]
    public async Task CompleteChatAsyncRejectsInvalidSuccessfulResponse(string responseBody, OpenAiErrorCode expectedCode)
    {
        var client = CreateClient(JsonResponse(responseBody));

        var error = await Assert.ThrowsAsync<OpenAiClientException>(() => client.CompleteChatAsync(
            Endpoint,
            "key",
            new ChatCompletionRequest("model", "prompt", new TextChatInput("text")),
            CancellationToken.None));

        Assert.Equal(expectedCode, error.Code);
    }

    [Theory]
    [InlineData(HttpStatusCode.Unauthorized)]
    [InlineData(HttpStatusCode.TooManyRequests)]
    public async Task HttpErrorsExposeStatusWithoutApiKey(HttpStatusCode status)
    {
        const string key = "key-must-not-leak";
        var client = CreateClient(new HttpResponseMessage(status)
        {
            Content = new StringContent("server error", Encoding.UTF8, "application/json")
        });

        var error = await Assert.ThrowsAsync<OpenAiClientException>(() => client.CompleteChatAsync(
            Endpoint,
            key,
            new ChatCompletionRequest("model", "prompt", new TextChatInput("text")),
            CancellationToken.None));

        Assert.Equal(OpenAiErrorCode.HttpError, error.Code);
        Assert.Equal(status, error.StatusCode);
        Assert.DoesNotContain(key, error.ToString(), StringComparison.Ordinal);
    }

    [Fact]
    public async Task HttpErrorResponseBodyRedactsApiKey()
    {
        const string key = "key-must-not-leak";
        var client = CreateClient(new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = new StringContent($"upstream echoed Bearer {key} and {key}")
        });

        var error = await Assert.ThrowsAsync<OpenAiClientException>(() => client.CompleteChatAsync(
            Endpoint,
            key,
            new ChatCompletionRequest("model", "prompt", new TextChatInput("text")),
            CancellationToken.None));

        Assert.DoesNotContain(key, error.ToString(), StringComparison.Ordinal);
        Assert.Contains("[REDACTED]", error.ResponseBody, StringComparison.Ordinal);
    }

    [Fact]
    public async Task HttpErrorResponseBodyIsCappedAt4096Characters()
    {
        string responseBody = new('x', 5000);
        var client = CreateClient(new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = new StringContent(responseBody)
        });

        var error = await Assert.ThrowsAsync<OpenAiClientException>(() => client.SynthesizeSpeechAsync(
            Endpoint,
            "key",
            new SpeechRequest("model", "text"),
            CancellationToken.None));

        Assert.Equal(new string('x', 4096), error.ResponseBody);
    }

    [Theory]
    [InlineData("")]
    [InlineData(" ")]
    public async Task BlankApiKeyIsRejectedBeforeNetwork(string apiKey)
    {
        var handler = new CapturingHandler(_ => throw new InvalidOperationException("Network must not be called."));
        var client = new OpenAiCompatibleClient(new HttpClient(handler));

        var error = await Assert.ThrowsAsync<ArgumentException>(() => client.CompleteChatAsync(
            Endpoint,
            apiKey,
            new ChatCompletionRequest("model", "prompt", new TextChatInput("text")),
            CancellationToken.None));

        Assert.Equal("apiKey", error.ParamName);
        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task NonLoopbackHttpEndpointIsRejectedBeforeSendingApiKey()
    {
        var handler = new CapturingHandler(_ => throw new InvalidOperationException("Network must not be called."));
        var client = new OpenAiCompatibleClient(new HttpClient(handler));

        await Assert.ThrowsAsync<ArgumentException>(() => client.CompleteChatAsync(
            new Uri("http://api.example.test/v1/chat/completions"),
            "key-must-not-leak",
            new ChatCompletionRequest("model", "prompt", new TextChatInput("text")),
            CancellationToken.None));

        Assert.Equal(0, handler.CallCount);
    }

    [Fact]
    public async Task LoopbackHttpEndpointIsAllowedForLocalGateway()
    {
        var handler = new CapturingHandler(_ => JsonResponse("""{"choices":[{"message":{"content":"done"}}]}"""));
        var client = new OpenAiCompatibleClient(new HttpClient(handler));

        var result = await client.CompleteChatAsync(
            new Uri("http://localhost:20128/v1/chat/completions"),
            "key",
            new ChatCompletionRequest("model", "prompt", new TextChatInput("text")),
            CancellationToken.None);

        Assert.Equal("done", result);
    }

    [Fact]
    public async Task BlankRequestFieldsAreRejectedBeforeNetwork()
    {
        var handler = new CapturingHandler(_ => throw new InvalidOperationException("Network must not be called."));
        var client = new OpenAiCompatibleClient(new HttpClient(handler));

        await Assert.ThrowsAsync<ArgumentException>(() => client.CompleteChatAsync(
            Endpoint,
            "key",
            new ChatCompletionRequest(" ", "prompt", new TextChatInput("text")),
            CancellationToken.None));
        await Assert.ThrowsAsync<ArgumentException>(() => client.CompleteChatAsync(
            Endpoint,
            "key",
            new ChatCompletionRequest("model", "prompt", new TextChatInput(" ")),
            CancellationToken.None));
        await Assert.ThrowsAsync<ArgumentException>(() => client.CompleteChatAsync(
            new Uri("relative", UriKind.Relative),
            "key",
            new ChatCompletionRequest("model", "prompt", new TextChatInput("text")),
            CancellationToken.None));
        await Assert.ThrowsAsync<ArgumentException>(() => client.SynthesizeSpeechAsync(
            Endpoint,
            "key",
            new SpeechRequest("model", " "),
            CancellationToken.None));

        Assert.Equal(0, handler.CallCount);
    }

    private static OpenAiCompatibleClient CreateClient(HttpResponseMessage response) =>
        new(new HttpClient(new CapturingHandler(_ => response)));

    private static HttpResponseMessage JsonResponse(string json) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };

    private sealed class CapturingHandler : HttpMessageHandler
    {
        private readonly Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> responseFactory;

        public CapturingHandler(Func<HttpRequestMessage, HttpResponseMessage> responseFactory)
            : this((request, _) => Task.FromResult(responseFactory(request))) { }

        public CapturingHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> responseFactory) =>
            this.responseFactory = responseFactory;

        public HttpRequestMessage? Request { get; private set; }
        public string? Body { get; private set; }
        public int CallCount { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            CallCount++;
            Request = request;
            Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
            return await responseFactory(request, cancellationToken);
        }
    }
}
