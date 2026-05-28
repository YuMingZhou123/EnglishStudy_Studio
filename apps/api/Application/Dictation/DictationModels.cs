namespace Api.Application.Dictation;

public sealed record DictationQuestionResponse(
    Guid QuestionId,
    Guid SentenceId,
    string Mode,
    string SceneCode,
    string SceneName,
    string Level,
    string SpeechText,
    string? AudioUrl,
    string? SlowAudioUrl,
    IReadOnlyCollection<DisplayPartResponse> DisplayParts,
    IReadOnlyCollection<TargetWordResponse> TargetWords,
    Guid? ReviewWordId = null);

public sealed record DisplayPartResponse(
    string Type,
    string? Value,
    string? BlankId,
    int? Length);

public sealed record TargetWordResponse(
    string BlankId,
    Guid WordId,
    string SurfaceText,
    string Lemma,
    string MeaningCn,
    string? Phonetic,
    string? PartOfSpeech,
    string? Collocations,
    string? FirstLetter);

public sealed record SubmitDictationRequest(
    Guid SentenceId,
    string Mode,
    IReadOnlyCollection<BlankAnswerRequest>? Answers,
    string? UserAnswer,
    int DurationMs,
    int ReplayCount,
    int HintCount,
    Guid? ReviewWordId = null);

public sealed record BlankAnswerRequest(
    string BlankId,
    string Value);

public sealed record DictationSubmitResponse(
    Guid AttemptId,
    Guid SentenceId,
    string Mode,
    bool IsCorrect,
    double Score,
    string SentenceText,
    string Translation,
    IReadOnlyCollection<BlankResultResponse> BlankResults,
    IReadOnlyCollection<TargetWordResponse> TargetWords);

public sealed record BlankResultResponse(
    string BlankId,
    string Expected,
    string? Answer,
    bool IsCorrect);

public sealed record DictationHistoryItemResponse(
    Guid AttemptId,
    Guid SentenceId,
    string Mode,
    double Score,
    bool IsCorrect,
    string SentenceText,
    string Translation,
    DateTimeOffset CreatedAt);

public sealed record DailyLearningStatResponse(
    DateOnly Date,
    int AttemptCount,
    int CorrectCount,
    double Accuracy);

public sealed record LearningSummaryResponse(
    int DailyDictationGoal,
    int TodayAttemptCount,
    int TodayCorrectCount,
    double TodayAccuracy,
    int WrongWordCount,
    int DueReviewCount,
    int TotalAttemptCount,
    int LearningDayCount,
    int CurrentStreakDays,
    double RecentAccuracy,
    IReadOnlyCollection<DailyLearningStatResponse> RecentDays);

public sealed record WrongWordResponse(
    Guid WordId,
    string Lemma,
    string MeaningCn,
    string? Phonetic,
    string Status,
    int MistakeCount,
    int CorrectStreak,
    DateTimeOffset? NextReviewAt,
    DateTimeOffset? LastReviewedAt,
    DateTimeOffset? LastMistakeAt,
    string? SourceSentenceText,
    string? SourceSentenceTranslation);
