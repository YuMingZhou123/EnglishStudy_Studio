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
}
