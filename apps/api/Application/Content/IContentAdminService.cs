using Api.Application.Auth;

namespace Api.Application.Content;

public interface IContentAdminService
{
    Task<IReadOnlyCollection<SceneResponse>> GetScenesAsync(CancellationToken cancellationToken = default);

    Task<ServiceResult<SceneResponse>> CreateSceneAsync(
        UpsertSceneRequest request,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyCollection<WordResponse>> GetWordsAsync(
        string? keyword = null,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<WordResponse>> CreateWordAsync(
        UpsertWordRequest request,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyCollection<SentenceResponse>> GetSentencesAsync(
        string? status = null,
        string? level = null,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<SentenceResponse>> CreateSentenceAsync(
        CreateSentenceRequest request,
        Guid createdBy,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<SentenceResponse>> UpdateSentenceAsync(
        Guid sentenceId,
        UpdateSentenceRequest request,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<SentenceResponse>> SetSentenceStatusAsync(
        Guid sentenceId,
        string status,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<MediaAssetResponse>> UploadMediaAsync(
        UploadMediaRequest request,
        CancellationToken cancellationToken = default);
}
