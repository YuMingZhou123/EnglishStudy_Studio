namespace Api.Application.Content;

public sealed record SceneResponse(
    Guid Id,
    string Code,
    string Name,
    string? Description,
    bool IsEnabled);

public sealed record UpsertSceneRequest(
    string Code,
    string Name,
    string? Description,
    bool IsEnabled = true);

public sealed record WordResponse(
    Guid Id,
    string Lemma,
    string? Phonetic,
    string? PartOfSpeech,
    string MeaningCn,
    string? CefrLevel,
    string? ExamTags,
    string? Collocations);

public sealed record UpsertWordRequest(
    string Lemma,
    string? Phonetic,
    string? PartOfSpeech,
    string MeaningCn,
    string? CefrLevel,
    string? ExamTags,
    string? Collocations);

public sealed record MediaAssetResponse(
    Guid Id,
    string Bucket,
    string ObjectKey,
    string Url,
    string ContentType,
    long Size,
    string Source);

public sealed record SentenceKeywordRequest(
    Guid WordId,
    string SurfaceText,
    int Priority,
    string? BlankGroup = null);

public sealed record SentenceKeywordResponse(
    Guid Id,
    Guid WordId,
    string SurfaceText,
    int StartIndex,
    int EndIndex,
    string? BlankGroup,
    int Priority,
    WordResponse Word);

public sealed record SentenceResponse(
    Guid Id,
    string Text,
    string Translation,
    string Level,
    Guid SceneId,
    string SceneName,
    string? AudioUrl,
    string? SlowAudioUrl,
    Guid? AudioAssetId,
    string Source,
    string Status,
    IReadOnlyCollection<SentenceKeywordResponse> Keywords);

public sealed record CreateSentenceRequest(
    string Text,
    string Translation,
    string Level,
    Guid SceneId,
    Guid? AudioAssetId,
    string? AudioUrl,
    IReadOnlyCollection<SentenceKeywordRequest> Keywords,
    string Status = "draft");

public sealed record UpdateSentenceRequest(
    string Text,
    string Translation,
    string Level,
    Guid SceneId,
    Guid? AudioAssetId,
    string? AudioUrl,
    IReadOnlyCollection<SentenceKeywordRequest> Keywords,
    string Status);

public sealed record UploadMediaRequest(
    Stream Stream,
    string FileName,
    string ContentType,
    long Size,
    string Folder);

public sealed record GenerateSentenceAudioRequest(
    string? Voice = null,
    double Speed = 1);

public sealed record GenerateMissingSentenceAudioRequest(
    int Limit = 10,
    string? Level = null,
    string Status = "published",
    string? Voice = null,
    double Speed = 1,
    bool IncludeExternalAudio = false);

public sealed record GenerateMissingSentenceAudioItemResponse(
    Guid SentenceId,
    string Text,
    bool Succeeded,
    string? AudioUrl,
    string? Error);

public sealed record GenerateMissingSentenceAudioResponse(
    int TotalCandidates,
    int GeneratedCount,
    int FailedCount,
    IReadOnlyCollection<GenerateMissingSentenceAudioItemResponse> Items);

public sealed record ImportSentenceKeywordRequest(
    string Lemma,
    string MeaningCn,
    string SurfaceText,
    int Priority = 100,
    string? Phonetic = null,
    string? PartOfSpeech = null,
    string? CefrLevel = null,
    string? ExamTags = null,
    string? Collocations = null,
    string? BlankGroup = null);

public sealed record ImportSentenceItemRequest(
    string Text,
    string Translation,
    string Level,
    string SceneCode,
    string SceneName,
    IReadOnlyCollection<ImportSentenceKeywordRequest> Keywords,
    string? SceneDescription = null,
    string? AudioUrl = null,
    string? Status = null);

public sealed record ImportSentencesRequest(
    IReadOnlyCollection<ImportSentenceItemRequest> Items,
    string DefaultStatus = "draft",
    bool UpdateExisting = true);

public sealed record ImportSentenceFailureResponse(
    int RowNumber,
    string Text,
    IReadOnlyCollection<string> Errors);

public sealed record ImportSentencesResponse(
    int TotalCount,
    int CreatedScenes,
    int CreatedWords,
    int CreatedSentences,
    int UpdatedSentences,
    int SkippedCount,
    IReadOnlyCollection<ImportSentenceFailureResponse> Failures);
