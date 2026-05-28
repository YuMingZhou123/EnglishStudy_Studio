namespace Api.Application.Media;

public interface IMediaService
{
    Task<MediaObjectResponse?> OpenObjectAsync(
        string objectKey,
        CancellationToken cancellationToken = default);
}
