namespace Api.Application.Common.Interfaces;

public interface ITtsProvider
{
    Task<TtsAudioResult> SynthesizeAsync(
        TtsRequest request,
        CancellationToken cancellationToken = default);
}

public sealed record TtsRequest(
    string Text,
    string? Voice = null,
    double Speed = 1);

public sealed record TtsAudioResult(
    byte[] AudioBytes,
    string ContentType,
    string FileExtension,
    string Provider,
    string? Voice);
