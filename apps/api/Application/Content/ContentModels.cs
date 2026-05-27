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
