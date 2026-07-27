using System.Net;

namespace NTranslate.Core.OpenAI;

public sealed record ChatCompletionRequest(string Model, string SystemPrompt, ChatInput Input);
public abstract record ChatInput;
public sealed record TextChatInput(string Text) : ChatInput;
public sealed record ImageChatInput(byte[] PngBytes, string TargetLanguage) : ChatInput;
public sealed record SpeechRequest(string Model, string Input);

public enum OpenAiErrorCode
{
    InvalidResponse,
    BlankCompletion,
    HttpError
}

public sealed class OpenAiClientException : Exception
{
    public OpenAiClientException(OpenAiErrorCode code, string message, HttpStatusCode? statusCode = null, string? responseBody = null, Exception? innerException = null)
        : base(message, innerException)
    {
        Code = code;
        StatusCode = statusCode;
        ResponseBody = responseBody;
    }

    public OpenAiErrorCode Code { get; }
    public HttpStatusCode? StatusCode { get; }
    public string? ResponseBody { get; }
}
