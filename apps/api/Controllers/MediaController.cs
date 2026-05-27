using Api.Application.Common.Interfaces;
using Api.Infrastructure.Persistence;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace Api.Controllers;

[ApiController]
[Route("api/media")]
public sealed class MediaController(
    AppDbContext dbContext,
    IFileStorageService fileStorageService) : ControllerBase
{
    [HttpGet("objects/{*objectKey}")]
    public async Task<IActionResult> Object(
        string objectKey,
        CancellationToken cancellationToken)
    {
        var mediaAsset = await dbContext.MediaAssets
            .AsNoTracking()
            .FirstOrDefaultAsync(asset => asset.ObjectKey == objectKey, cancellationToken);

        if (mediaAsset is null)
        {
            return NotFound();
        }

        var file = await fileStorageService.OpenReadAsync(objectKey, cancellationToken);
        return File(file.Stream, mediaAsset.ContentType, enableRangeProcessing: true);
    }
}
