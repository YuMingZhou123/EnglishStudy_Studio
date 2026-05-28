using Api.Application.Media;
using Microsoft.AspNetCore.Mvc;

namespace Api.Controllers;

[ApiController]
[Route("api/media")]
public sealed class MediaController(IMediaService mediaService) : ControllerBase
{
    [HttpGet("objects/{*objectKey}")]
    public async Task<IActionResult> Object(
        string objectKey,
        CancellationToken cancellationToken)
    {
        var mediaObject = await mediaService.OpenObjectAsync(
            objectKey,
            cancellationToken);
        if (mediaObject is null)
        {
            return NotFound();
        }

        return File(mediaObject.Stream, mediaObject.ContentType, enableRangeProcessing: true);
    }
}
