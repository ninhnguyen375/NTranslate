using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace NTranslate.Core.OpenAI;

public sealed class OpenAiCompatibleClient(HttpClient httpClient)
{
    private const int ErrorBodyLimit = 4096;

    public async Task<string> CompleteChatAsync(Uri endpoint, string apiKey, ChatCompletionRequest request, CancellationToken cancellationToken)
    {
        ValidateEndpointAndKey(endpoint, apiKey);
        ArgumentNullException.ThrowIfNull(request);
        RequireText(request.Model, nameof(request.Model));
        RequireText(request.SystemPrompt, nameof(request.SystemPrompt));
        ValidateInput(request.Input);

        using var message = CreateRequest(endpoint, apiKey, WriteChatBody(request));
        using var response = await httpClient.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        await EnsureSuccessAsync(response, apiKey, cancellationToken).ConfigureAwait(false);

        try
        {
            await using var content = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
            using var document = await JsonDocument.ParseAsync(content, cancellationToken: cancellationToken).ConfigureAwait(false);
            if (!document.RootElement.TryGetProperty("choices", out var choices)
                || choices.ValueKind != JsonValueKind.Array
                || choices.GetArrayLength() == 0
                || choices[0].ValueKind != JsonValueKind.Object
                || !choices[0].TryGetProperty("message", out var responseMessage)
                || responseMessage.ValueKind != JsonValueKind.Object
                || !responseMessage.TryGetProperty("content", out var contentElement)
                || contentElement.ValueKind != JsonValueKind.String)
            {
                throw new OpenAiClientException(OpenAiErrorCode.InvalidResponse, "Chat response schema is invalid.");
            }

            string result = contentElement.GetString()!.Trim();
            return result.Length == 0
                ? throw new OpenAiClientException(OpenAiErrorCode.BlankCompletion, "Chat completion is blank.")
                : result;
        }
        catch (JsonException exception)
        {
            throw new OpenAiClientException(OpenAiErrorCode.InvalidResponse, "Chat response schema is invalid.", innerException: exception);
        }
    }

    public async Task<byte[]> SynthesizeSpeechAsync(Uri endpoint, string apiKey, SpeechRequest request, CancellationToken cancellationToken)
    {
        ValidateEndpointAndKey(endpoint, apiKey);
        ArgumentNullException.ThrowIfNull(request);
        RequireText(request.Model, nameof(request.Model));
        RequireText(request.Input, nameof(request.Input));

        using var message = CreateRequest(endpoint, apiKey, WriteSpeechBody(request));
        using var response = await httpClient.SendAsync(message, HttpCompletionOption.ResponseHeadersRead, cancellationToken).ConfigureAwait(false);
        await EnsureSuccessAsync(response, apiKey, cancellationToken).ConfigureAwait(false);
        return await response.Content.ReadAsByteArrayAsync(cancellationToken).ConfigureAwait(false);
    }

    private static HttpRequestMessage CreateRequest(Uri endpoint, string apiKey, byte[] body)
    {
        var message = new HttpRequestMessage(HttpMethod.Post, endpoint)
        {
            Content = new ByteArrayContent(body)
        };
        message.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        message.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey.Trim());
        return message;
    }

    private static byte[] WriteChatBody(ChatCompletionRequest request) => WriteJson(writer =>
    {
        writer.WriteStartObject();
        writer.WriteString("model", request.Model.Trim());
        writer.WriteBoolean("stream", false);
        writer.WriteStartArray("messages");
        WriteMessage(writer, "system", request.SystemPrompt);
        writer.WriteStartObject();
        writer.WriteString("role", "user");
        writer.WritePropertyName("content");
        switch (request.Input)
        {
            case TextChatInput text:
                writer.WriteStringValue($"<selected-text>{text.Text}</selected-text>");
                break;
            case ImageChatInput image:
                writer.WriteStartArray();
                writer.WriteStartObject();
                writer.WriteString("type", "text");
                writer.WriteString("text", $"Translate all readable text in this image into {image.TargetLanguage}. Return only the translation.");
                writer.WriteEndObject();
                writer.WriteStartObject();
                writer.WriteString("type", "image_url");
                writer.WriteStartObject("image_url");
                writer.WriteString("url", $"data:image/png;base64,{Convert.ToBase64String(image.PngBytes)}");
                writer.WriteEndObject();
                writer.WriteEndObject();
                writer.WriteEndArray();
                break;
        }
        writer.WriteEndObject();
        writer.WriteEndArray();
        writer.WriteEndObject();
    });

    private static byte[] WriteSpeechBody(SpeechRequest request) => WriteJson(writer =>
    {
        writer.WriteStartObject();
        writer.WriteString("model", request.Model.Trim());
        writer.WriteString("input", request.Input.Trim());
        writer.WriteEndObject();
    });

    private static byte[] WriteJson(Action<Utf8JsonWriter> write)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            write(writer);
        }
        return stream.ToArray();
    }

    private static void WriteMessage(Utf8JsonWriter writer, string role, string content)
    {
        writer.WriteStartObject();
        writer.WriteString("role", role);
        writer.WriteString("content", content);
        writer.WriteEndObject();
    }

    private static async Task EnsureSuccessAsync(HttpResponseMessage response, string apiKey, CancellationToken cancellationToken)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        string body = await ReadErrorBodyAsync(response.Content, cancellationToken).ConfigureAwait(false);
        throw new OpenAiClientException(
            OpenAiErrorCode.HttpError,
            $"OpenAI-compatible endpoint returned HTTP {(int)response.StatusCode}.",
            response.StatusCode,
            Redact(body, apiKey));
    }

    private static async Task<string> ReadErrorBodyAsync(HttpContent content, CancellationToken cancellationToken)
    {
        await using var stream = await content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true, bufferSize: 1024, leaveOpen: false);
        char[] buffer = new char[ErrorBodyLimit];
        int total = 0;
        while (total < buffer.Length)
        {
            int read = await reader.ReadAsync(buffer.AsMemory(total, buffer.Length - total), cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }
            total += read;
        }
        return new string(buffer, 0, total);
    }

    private static string Redact(string value, string secret) =>
        value.Replace(secret, "[REDACTED]", StringComparison.Ordinal);

    private static void ValidateEndpointAndKey(Uri endpoint, string apiKey)
    {
        ArgumentNullException.ThrowIfNull(endpoint);
        if (!endpoint.IsAbsoluteUri
            || (endpoint.Scheme != Uri.UriSchemeHttps && !(endpoint.Scheme == Uri.UriSchemeHttp && endpoint.IsLoopback)))
        {
            throw new ArgumentException("Endpoint must use HTTPS, except for HTTP loopback endpoints.", nameof(endpoint));
        }
        RequireText(apiKey, nameof(apiKey));
    }

    private static void ValidateInput(ChatInput input)
    {
        ArgumentNullException.ThrowIfNull(input);
        switch (input)
        {
            case TextChatInput text:
                RequireText(text.Text, nameof(text.Text));
                break;
            case ImageChatInput image:
                ArgumentNullException.ThrowIfNull(image.PngBytes);
                if (image.PngBytes.Length == 0)
                {
                    throw new ArgumentException("PNG bytes must not be empty.", nameof(image.PngBytes));
                }
                RequireText(image.TargetLanguage, nameof(image.TargetLanguage));
                break;
            default:
                throw new ArgumentException("Unsupported chat input.", nameof(input));
        }
    }

    private static void RequireText(string value, string paramName)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            throw new ArgumentException("Value must not be blank.", paramName);
        }
    }
}
