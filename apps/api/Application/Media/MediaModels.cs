namespace Api.Application.Media;

public sealed record MediaObjectResponse(
    Stream Stream,
    string ContentType,
    long? Size);
