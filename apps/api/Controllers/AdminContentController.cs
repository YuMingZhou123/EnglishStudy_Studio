using Api.Application.Auth;
using Api.Application.Content;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Api.Controllers;

[ApiController]
[Authorize(Roles = "Admin,ContentAdmin")]
[Route("api/admin")]
public sealed class AdminContentController(IContentAdminService contentAdminService) : ControllerBase
{
    [HttpGet("scenes")]
    public async Task<IReadOnlyCollection<SceneResponse>> Scenes(CancellationToken cancellationToken)
    {
        return await contentAdminService.GetScenesAsync(cancellationToken);
    }

    [HttpPost("scenes")]
    public async Task<IActionResult> CreateScene(
        UpsertSceneRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.CreateSceneAsync(request, cancellationToken);
        return ToActionResult(result);
    }

    [HttpPut("scenes/{sceneId:guid}")]
    public async Task<IActionResult> UpdateScene(
        Guid sceneId,
        UpsertSceneRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.UpdateSceneAsync(
            sceneId,
            request,
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpGet("words")]
    public async Task<IReadOnlyCollection<WordResponse>> Words(
        [FromQuery] string? keyword,
        CancellationToken cancellationToken)
    {
        return await contentAdminService.GetWordsAsync(keyword, cancellationToken);
    }

    [HttpPost("words")]
    public async Task<IActionResult> CreateWord(
        UpsertWordRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.CreateWordAsync(request, cancellationToken);
        return ToActionResult(result);
    }

    [HttpPut("words/{wordId:guid}")]
    public async Task<IActionResult> UpdateWord(
        Guid wordId,
        UpsertWordRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.UpdateWordAsync(
            wordId,
            request,
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpGet("sentences")]
    public async Task<IReadOnlyCollection<SentenceResponse>> Sentences(
        [FromQuery] string? status,
        [FromQuery] string? level,
        CancellationToken cancellationToken)
    {
        return await contentAdminService.GetSentencesAsync(status, level, cancellationToken);
    }

    [HttpPost("sentences")]
    public async Task<IActionResult> CreateSentence(
        CreateSentenceRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.CreateSentenceAsync(
            request,
            User.GetRequiredUserId(),
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPut("sentences/{sentenceId:guid}")]
    public async Task<IActionResult> UpdateSentence(
        Guid sentenceId,
        UpdateSentenceRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.UpdateSentenceAsync(
            sentenceId,
            request,
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("sentences/{sentenceId:guid}/publish")]
    public async Task<IActionResult> PublishSentence(
        Guid sentenceId,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.SetSentenceStatusAsync(
            sentenceId,
            "published",
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("sentences/{sentenceId:guid}/offline")]
    public async Task<IActionResult> OfflineSentence(
        Guid sentenceId,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.SetSentenceStatusAsync(
            sentenceId,
            "offline",
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("sentences/{sentenceId:guid}/generate-audio")]
    public async Task<IActionResult> GenerateSentenceAudio(
        Guid sentenceId,
        GenerateSentenceAudioRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.GenerateSentenceAudioAsync(
            sentenceId,
            request,
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("sentences/generate-missing-audio")]
    public async Task<IActionResult> GenerateMissingSentenceAudio(
        GenerateMissingSentenceAudioRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.GenerateMissingSentenceAudioAsync(
            request,
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("sentences/import")]
    public async Task<IActionResult> ImportSentences(
        ImportSentencesRequest request,
        CancellationToken cancellationToken)
    {
        var result = await contentAdminService.ImportSentencesAsync(
            request,
            User.GetRequiredUserId(),
            cancellationToken);

        return ToActionResult(result);
    }

    [HttpPost("media/upload")]
    [RequestSizeLimit(50_000_000)]
    public async Task<IActionResult> UploadMedia(
        IFormFile file,
        [FromForm] string folder,
        CancellationToken cancellationToken)
    {
        if (file.Length <= 0)
        {
            return BadRequest(new { errors = new[] { "File is empty." } });
        }

        await using var stream = file.OpenReadStream();
        var result = await contentAdminService.UploadMediaAsync(
            new UploadMediaRequest(
                stream,
                file.FileName,
                string.IsNullOrWhiteSpace(file.ContentType)
                    ? "application/octet-stream"
                    : file.ContentType,
                file.Length,
                folder),
            cancellationToken);

        return ToActionResult(result);
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
