using Api.Application.Auth;
using Api.Application.Dictation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Api.Controllers;

[ApiController]
[Authorize]
[Route("api/dictation")]
public sealed class DictationController(IDictationService dictationService) : ControllerBase
{
    [HttpGet("next")]
    public async Task<IActionResult> Next(
        [FromQuery] string mode = "beginner",
        CancellationToken cancellationToken = default)
    {
        var result = await dictationService.GetNextQuestionAsync(
            User.GetRequiredUserId(),
            mode,
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("submit")]
    public async Task<IActionResult> Submit(
        SubmitDictationRequest request,
        CancellationToken cancellationToken)
    {
        var result = await dictationService.SubmitAsync(
            User.GetRequiredUserId(),
            request,
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpGet("history")]
    public async Task<IReadOnlyCollection<DictationHistoryItemResponse>> History(
        [FromQuery] int limit = 20,
        CancellationToken cancellationToken = default)
    {
        return await dictationService.GetHistoryAsync(
            User.GetRequiredUserId(),
            limit,
            cancellationToken);
    }

    private ObjectResult ToActionResult<T>(ServiceResult<T> result)
    {
        if (result.Succeeded)
        {
            return Ok(result.Value);
        }

        return BadRequest(new { errors = result.Errors });
    }
}
