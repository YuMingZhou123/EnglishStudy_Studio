using Api.Application.Dictation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Api.Controllers;

[ApiController]
[Authorize]
[Route("api/vocabulary")]
public sealed class VocabularyController(IDictationService dictationService) : ControllerBase
{
    [HttpGet("wrong-words")]
    public async Task<IReadOnlyCollection<WrongWordResponse>> WrongWords(
        CancellationToken cancellationToken)
    {
        return await dictationService.GetWrongWordsAsync(
            User.GetRequiredUserId(),
            cancellationToken);
    }

    [HttpGet("review/next")]
    public async Task<IActionResult> NextReview(
        [FromQuery] string mode = "beginner",
        CancellationToken cancellationToken = default)
    {
        var result = await dictationService.GetReviewQuestionAsync(
            User.GetRequiredUserId(),
            mode,
            cancellationToken);

        if (result.Succeeded)
        {
            return Ok(result.Value);
        }

        return BadRequest(new { errors = result.Errors });
    }
}
