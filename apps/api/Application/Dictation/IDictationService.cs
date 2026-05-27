using Api.Application.Auth;

namespace Api.Application.Dictation;

public interface IDictationService
{
    Task<ServiceResult<DictationQuestionResponse>> GetNextQuestionAsync(
        Guid userId,
        string mode,
        CancellationToken cancellationToken = default);

    Task<ServiceResult<DictationSubmitResponse>> SubmitAsync(
        Guid userId,
        SubmitDictationRequest request,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyCollection<DictationHistoryItemResponse>> GetHistoryAsync(
        Guid userId,
        int limit = 20,
        CancellationToken cancellationToken = default);

    Task<LearningSummaryResponse> GetLearningSummaryAsync(
        Guid userId,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyCollection<WrongWordResponse>> GetWrongWordsAsync(
        Guid userId,
        CancellationToken cancellationToken = default);
}
