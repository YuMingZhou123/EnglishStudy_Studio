using Api.Application.Common.Interfaces;
using Microsoft.EntityFrameworkCore;

namespace Api.Application.Media;

public sealed class MediaService(
    IAppDbContext dbContext,
    IFileStorageService fileStorageService) : IMediaService
{
    public async Task<MediaObjectResponse?> OpenObjectAsync(
        string objectKey,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(objectKey))
        {
            return null;
        }

        var mediaAsset = await dbContext.MediaAssets
            .AsNoTracking()
            .FirstOrDefaultAsync(
                asset => asset.ObjectKey == objectKey,
                cancellationToken);

        if (mediaAsset is null)
        {
            return null;
        }

        var storedFile = await fileStorageService.OpenReadAsync(
            mediaAsset.ObjectKey,
            cancellationToken);

        return new MediaObjectResponse(
            storedFile.Stream,
            mediaAsset.ContentType,
            storedFile.Size);
    }
}
