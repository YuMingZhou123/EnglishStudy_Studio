using System.Text.Json;
using Api.Application.Auth;
using Api.Application.Common.Interfaces;
using Api.Domain.Content;
using Api.Domain.Dictation;
using Api.Domain.Learning;
using Microsoft.EntityFrameworkCore;

namespace Api.Application.Dictation;

public sealed class DictationService(IAppDbContext dbContext) : IDictationService
{
    private const int DailyDictationGoal = 10;

    public async Task<ServiceResult<DictationQuestionResponse>> GetNextQuestionAsync(
        Guid userId,
        string mode,
        CancellationToken cancellationToken = default)
    {
        mode = DictationMode.Normalize(mode);
        if (!DictationMode.IsSupported(mode))
        {
            return ServiceResult<DictationQuestionResponse>.Failure("Unsupported dictation mode.");
        }

        var attemptedSentenceIds = await dbContext.DictationAttempts
            .Where(attempt => attempt.UserId == userId)
            .OrderByDescending(attempt => attempt.CreatedAt)
            .Take(20)
            .Select(attempt => attempt.SentenceId)
            .ToListAsync(cancellationToken);

        var query = PublishedSentencesQuery()
            .Where(sentence => sentence.Level == mode);

        var sentence = await query
            .Where(sentence => !attemptedSentenceIds.Contains(sentence.Id))
            .OrderBy(sentence => sentence.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        sentence ??= await query
            .OrderBy(sentence => sentence.CreatedAt)
            .FirstOrDefaultAsync(cancellationToken);

        if (sentence is null)
        {
            return ServiceResult<DictationQuestionResponse>.Failure("No published dictation sentence is available.");
        }

        return ServiceResult<DictationQuestionResponse>.Success(BuildQuestion(sentence, mode));
    }

    public async Task<ServiceResult<DictationQuestionResponse>> GetReviewQuestionAsync(
        Guid userId,
        string mode,
        CancellationToken cancellationToken = default)
    {
        mode = DictationMode.Normalize(mode);
        if (!DictationMode.IsSupported(mode))
        {
            return ServiceResult<DictationQuestionResponse>.Failure("Unsupported dictation mode.");
        }

        var dueWordIds = await GetReviewWordIdsAsync(
            userId,
            dueOnly: true,
            cancellationToken);

        if (dueWordIds.Count == 0)
        {
            dueWordIds = await GetReviewWordIdsAsync(
                userId,
                dueOnly: false,
                cancellationToken);
        }

        if (dueWordIds.Count == 0)
        {
            return ServiceResult<DictationQuestionResponse>.Failure("No wrong word is available for review.");
        }

        foreach (var wordId in dueWordIds)
        {
            var sentence = await PublishedSentencesQuery()
                .Where(item => item.Level == mode)
                .Where(item => item.Keywords.Any(keyword => keyword.WordId == wordId))
                .OrderBy(item => item.CreatedAt)
                .FirstOrDefaultAsync(cancellationToken);

            if (sentence is not null)
            {
                return ServiceResult<DictationQuestionResponse>.Success(
                    BuildReviewQuestion(sentence, mode, wordId));
            }
        }

        foreach (var wordId in dueWordIds)
        {
            var sentence = await PublishedSentencesQuery()
                .Where(item => item.Keywords.Any(keyword => keyword.WordId == wordId))
                .OrderBy(item => item.CreatedAt)
                .FirstOrDefaultAsync(cancellationToken);

            if (sentence is not null)
            {
                return ServiceResult<DictationQuestionResponse>.Success(
                    BuildReviewQuestion(sentence, mode, wordId));
            }
        }

        return ServiceResult<DictationQuestionResponse>.Failure("No published sentence can be used for wrong word review.");
    }

    public async Task<ServiceResult<DictationSubmitResponse>> SubmitAsync(
        Guid userId,
        SubmitDictationRequest request,
        CancellationToken cancellationToken = default)
    {
        var mode = DictationMode.Normalize(request.Mode);
        if (!DictationMode.IsSupported(mode))
        {
            return ServiceResult<DictationSubmitResponse>.Failure("Unsupported dictation mode.");
        }

        var sentence = await PublishedSentencesQuery()
            .FirstOrDefaultAsync(item => item.Id == request.SentenceId, cancellationToken);

        if (sentence is null)
        {
            return ServiceResult<DictationSubmitResponse>.Failure("Sentence was not found.");
        }

        var selectedKeywords = request.ReviewWordId.HasValue
            ? DictationKeywordSelector.SelectForReview(sentence, mode, request.ReviewWordId.Value)
            : DictationKeywordSelector.Select(sentence, mode);
        if (selectedKeywords.Length == 0)
        {
            return ServiceResult<DictationSubmitResponse>.Failure("Review word does not appear in the sentence.");
        }

        var targetWords = selectedKeywords.Select(MapTargetWord).ToArray();
        var blankResults = Array.Empty<BlankResultResponse>();
        IReadOnlyCollection<DictationBlankResult> wordStateResults = Array.Empty<DictationBlankResult>();
        double score;

        if (mode == DictationMode.Advanced)
        {
            var advancedGrade = DictationGrader.GradeAdvanced(sentence, request.UserAnswer, selectedKeywords);
            blankResults = MapBlankResults(advancedGrade.FeedbackResults);
            wordStateResults = advancedGrade.KeywordResults;
            score = advancedGrade.Score;
        }
        else
        {
            wordStateResults = DictationGrader.GradeBlanks(
                selectedKeywords,
                BuildAnswerMap(request.Answers));
            blankResults = MapBlankResults(wordStateResults);
            score = DictationGrader.CalculateBlankScore(wordStateResults);
        }

        var isCorrect = score >= 99.99;
        var now = DateTimeOffset.UtcNow;
        var normalizedAnswer = mode == DictationMode.Advanced
            ? DictationAnswerNormalizer.Normalize(request.UserAnswer)
            : DictationAnswerNormalizer.Normalize(string.Join(
                " ",
                request.Answers?.OrderBy(answer => answer.BlankId).Select(answer => answer.Value) ?? Array.Empty<string>()));

        var attempt = new DictationAttempt
        {
            UserId = userId,
            SentenceId = sentence.Id,
            Mode = mode,
            UserAnswer = mode == DictationMode.Advanced
                ? request.UserAnswer ?? string.Empty
                : JsonSerializer.Serialize(request.Answers ?? Array.Empty<BlankAnswerRequest>()),
            NormalizedAnswer = normalizedAnswer,
            Score = score,
            IsCorrect = isCorrect,
            DetailJson = JsonSerializer.Serialize(blankResults),
            HintCount = Math.Max(0, request.HintCount),
            ReplayCount = Math.Max(0, request.ReplayCount),
            DurationMs = Math.Max(0, request.DurationMs),
            CreatedAt = now
        };

        dbContext.DictationAttempts.Add(attempt);
        await UpdateUserWordStatesAsync(
            userId,
            sentence.Id,
            selectedKeywords,
            wordStateResults,
            now,
            cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);

        return ServiceResult<DictationSubmitResponse>.Success(new DictationSubmitResponse(
            attempt.Id,
            sentence.Id,
            mode,
            isCorrect,
            score,
            sentence.Text,
            sentence.Translation,
            blankResults,
            targetWords));
    }

    public async Task<IReadOnlyCollection<DictationHistoryItemResponse>> GetHistoryAsync(
        Guid userId,
        int limit = 20,
        CancellationToken cancellationToken = default)
    {
        limit = Math.Clamp(limit, 1, 100);

        return await dbContext.DictationAttempts
            .AsNoTracking()
            .Where(attempt => attempt.UserId == userId)
            .Include(attempt => attempt.Sentence)
            .OrderByDescending(attempt => attempt.CreatedAt)
            .Take(limit)
            .Select(attempt => new DictationHistoryItemResponse(
                attempt.Id,
                attempt.SentenceId,
                attempt.Mode,
                attempt.Score,
                attempt.IsCorrect,
                attempt.Sentence.Text,
                attempt.Sentence.Translation,
                attempt.CreatedAt))
            .ToListAsync(cancellationToken);
    }

    public async Task<IReadOnlyCollection<WrongWordResponse>> GetWrongWordsAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var states = await dbContext.UserWordStates
            .AsNoTracking()
            .Where(state => state.UserId == userId && state.MistakeCount > 0)
            .Include(state => state.Word)
            .Include(state => state.LastMistakeSentence)
            .OrderByDescending(state => state.UpdatedAt)
            .ToListAsync(cancellationToken);

        return states.Select(MapVocabularyWord).ToArray();
    }

    public async Task<IReadOnlyCollection<WrongWordResponse>> GetVocabularyWordsAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var states = await dbContext.UserWordStates
            .AsNoTracking()
            .Where(state => state.UserId == userId)
            .Include(state => state.Word)
            .Include(state => state.LastMistakeSentence)
            .OrderBy(state => state.NextReviewAt ?? state.UpdatedAt)
            .ThenByDescending(state => state.UpdatedAt)
            .ToListAsync(cancellationToken);

        return states.Select(MapVocabularyWord).ToArray();
    }

    public async Task<ServiceResult<WrongWordResponse>> AddVocabularyWordAsync(
        Guid userId,
        AddVocabularyWordRequest request,
        CancellationToken cancellationToken = default)
    {
        var word = await dbContext.Words
            .FirstOrDefaultAsync(item => item.Id == request.WordId, cancellationToken);
        if (word is null)
        {
            return ServiceResult<WrongWordResponse>.Failure("Word was not found.");
        }

        var now = DateTimeOffset.UtcNow;
        var state = await dbContext.UserWordStates
            .Include(item => item.Word)
            .Include(item => item.LastMistakeSentence)
            .FirstOrDefaultAsync(
                item => item.UserId == userId && item.WordId == request.WordId,
                cancellationToken);

        if (state is null)
        {
            state = UserWordState.CreateManual(userId, request.WordId, now);
            state.Word = word;

            dbContext.UserWordStates.Add(state);
        }
        else
        {
            state.MarkManualAdded(now);
        }

        await dbContext.SaveChangesAsync(cancellationToken);
        return ServiceResult<WrongWordResponse>.Success(MapVocabularyWord(state));
    }

    public async Task<LearningSummaryResponse> GetLearningSummaryAsync(
        Guid userId,
        CancellationToken cancellationToken = default)
    {
        var now = DateTimeOffset.UtcNow;
        var localNow = DateTimeOffset.Now;
        var today = DateOnly.FromDateTime(localNow.DateTime);
        var localTodayStart = new DateTimeOffset(
            today.Year,
            today.Month,
            today.Day,
            0,
            0,
            0,
            localNow.Offset);
        var todayStart = localTodayStart.ToUniversalTime();
        var tomorrowStart = localTodayStart.AddDays(1).ToUniversalTime();
        var recentStart = localTodayStart.AddDays(-6).ToUniversalTime();

        var recentAttempts = await dbContext.DictationAttempts
            .AsNoTracking()
            .Where(attempt =>
                attempt.UserId == userId &&
                attempt.CreatedAt >= recentStart &&
                attempt.CreatedAt < tomorrowStart)
            .Select(attempt => new
            {
                attempt.CreatedAt,
                attempt.IsCorrect
            })
            .ToListAsync(cancellationToken);

        var allAttemptDates = await dbContext.DictationAttempts
            .AsNoTracking()
            .Where(attempt => attempt.UserId == userId)
            .Select(attempt => attempt.CreatedAt)
            .ToListAsync(cancellationToken);

        var wrongWordCount = await dbContext.UserWordStates
            .AsNoTracking()
            .CountAsync(
                state => state.UserId == userId && state.MistakeCount > 0,
                cancellationToken);

        var dueReviewCount = await dbContext.UserWordStates
            .AsNoTracking()
            .CountAsync(
                state =>
                    state.UserId == userId &&
                    (state.MistakeCount > 0 || state.Source == UserWordState.SourceManual) &&
                    (state.NextReviewAt == null || state.NextReviewAt <= now),
                cancellationToken);

        var totalAttemptCount = allAttemptDates.Count;
        var learningDates = allAttemptDates
            .Select(item => DateOnly.FromDateTime(item.ToLocalTime().DateTime))
            .ToHashSet();

        var currentStreakDays = 0;
        for (var date = today; learningDates.Contains(date); date = date.AddDays(-1))
        {
            currentStreakDays += 1;
        }

        var todayAttempts = recentAttempts
            .Where(attempt => DateOnly.FromDateTime(attempt.CreatedAt.ToLocalTime().DateTime) == today)
            .ToArray();

        var recentDays = Enumerable.Range(0, 7)
            .Select(offset => today.AddDays(offset - 6))
            .Select(date =>
            {
                var attempts = recentAttempts
                    .Where(attempt => DateOnly.FromDateTime(attempt.CreatedAt.ToLocalTime().DateTime) == date)
                    .ToArray();
                var correctCount = attempts.Count(attempt => attempt.IsCorrect);

                return new DailyLearningStatResponse(
                    date,
                    attempts.Length,
                    correctCount,
                    CalculateAccuracy(attempts.Length, correctCount));
            })
            .ToArray();

        var todayCorrectCount = todayAttempts.Count(attempt => attempt.IsCorrect);
        var recentCorrectCount = recentAttempts.Count(attempt => attempt.IsCorrect);

        return new LearningSummaryResponse(
            DailyDictationGoal,
            todayAttempts.Length,
            todayCorrectCount,
            CalculateAccuracy(todayAttempts.Length, todayCorrectCount),
            wrongWordCount,
            dueReviewCount,
            totalAttemptCount,
            learningDates.Count,
            currentStreakDays,
            CalculateAccuracy(recentAttempts.Count, recentCorrectCount),
            recentDays);
    }

    private IQueryable<Sentence> PublishedSentencesQuery()
    {
        return dbContext.Sentences
            .AsSplitQuery()
            .Include(sentence => sentence.Scene)
            .Include(sentence => sentence.Keywords)
            .ThenInclude(keyword => keyword.Word)
            .Where(sentence => sentence.Status == "published" && sentence.Scene.IsEnabled);
    }

    private async Task<IReadOnlyCollection<Guid>> GetReviewWordIdsAsync(
        Guid userId,
        bool dueOnly,
        CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        var query = dbContext.UserWordStates
            .AsNoTracking()
            .Where(state =>
                state.UserId == userId &&
                (state.MistakeCount > 0 || state.Source == UserWordState.SourceManual));

        if (dueOnly)
        {
            query = query.Where(state => state.NextReviewAt == null || state.NextReviewAt <= now);
        }

        return await query
            .OrderBy(state => state.NextReviewAt ?? state.UpdatedAt)
            .ThenByDescending(state => state.MistakeCount)
            .Select(state => state.WordId)
            .Take(30)
            .ToListAsync(cancellationToken);
    }

    private static DictationQuestionResponse BuildQuestion(Sentence sentence, string mode)
    {
        var selectedKeywords = DictationKeywordSelector.Select(sentence, mode);
        return BuildQuestion(sentence, mode, selectedKeywords, null);
    }

    private static DictationQuestionResponse BuildReviewQuestion(
        Sentence sentence,
        string mode,
        Guid reviewWordId)
    {
        var selectedKeywords = DictationKeywordSelector.SelectForReview(sentence, mode, reviewWordId);
        return BuildQuestion(sentence, mode, selectedKeywords, reviewWordId);
    }

    private static DictationQuestionResponse BuildQuestion(
        Sentence sentence,
        string mode,
        IReadOnlyCollection<SentenceKeyword> selectedKeywords,
        Guid? reviewWordId)
    {
        return new DictationQuestionResponse(
            sentence.Id,
            sentence.Id,
            mode,
            sentence.Scene.Code,
            sentence.Scene.Name,
            sentence.Level,
            sentence.Text,
            sentence.AudioUrl,
            sentence.SlowAudioUrl,
            BuildDisplayParts(sentence.Text, selectedKeywords, mode),
            selectedKeywords.Select(MapTargetWord).ToArray(),
            reviewWordId);
    }

    private static IReadOnlyCollection<DisplayPartResponse> BuildDisplayParts(
        string sentenceText,
        IReadOnlyCollection<SentenceKeyword> keywords,
        string mode)
    {
        if (mode == DictationMode.Advanced)
        {
            return
            [
                new DisplayPartResponse("blank", null, DictationBlankId.FullSentence, sentenceText.Length)
            ];
        }

        var parts = new List<DisplayPartResponse>();
        var cursor = 0;

        foreach (var keyword in keywords.OrderBy(keyword => keyword.StartIndex))
        {
            var start = Math.Clamp(keyword.StartIndex, 0, sentenceText.Length);
            var end = Math.Clamp(keyword.EndIndex, start, sentenceText.Length);

            if (start < cursor)
            {
                continue;
            }

            if (start > cursor)
            {
                parts.Add(new DisplayPartResponse(
                    "text",
                    sentenceText[cursor..start],
                    null,
                    null));
            }

            parts.Add(new DisplayPartResponse(
                "blank",
                null,
                DictationBlankId.ForKeyword(keyword),
                Math.Max(1, end - start)));

            cursor = end;
        }

        if (cursor < sentenceText.Length)
        {
            parts.Add(new DisplayPartResponse(
                "text",
                sentenceText[cursor..],
                null,
                null));
        }

        return parts;
    }

    private async Task UpdateUserWordStatesAsync(
        Guid userId,
        Guid sentenceId,
        IReadOnlyCollection<SentenceKeyword> keywords,
        IReadOnlyCollection<DictationBlankResult> results,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var resultMap = results.ToDictionary(result => result.BlankId, result => result.IsCorrect);

        foreach (var keyword in keywords)
        {
            var blankId = DictationBlankId.ForKeyword(keyword);
            var isCorrect = resultMap.TryGetValue(blankId, out var resultCorrect) && resultCorrect;

            var state = await dbContext.UserWordStates
                .FirstOrDefaultAsync(
                    item => item.UserId == userId && item.WordId == keyword.WordId,
                    cancellationToken);

            if (state is null && isCorrect)
            {
                continue;
            }

            if (state is null)
            {
                state = UserWordState.CreateFromDictation(userId, keyword.WordId, now);
                dbContext.UserWordStates.Add(state);
            }

            state.ApplyDictationResult(isCorrect, sentenceId, now);
        }
    }

    private static TargetWordResponse MapTargetWord(SentenceKeyword keyword)
    {
        return new TargetWordResponse(
            DictationBlankId.ForKeyword(keyword),
            keyword.WordId,
            keyword.SurfaceText,
            keyword.Word.Lemma,
            keyword.Word.MeaningCn,
            keyword.Word.Phonetic,
            keyword.Word.PartOfSpeech,
            keyword.Word.Collocations,
            string.IsNullOrWhiteSpace(keyword.SurfaceText)
                ? null
                : keyword.SurfaceText[..1]);
    }

    private static WrongWordResponse MapVocabularyWord(UserWordState state)
    {
        return new WrongWordResponse(
            state.WordId,
            state.Word.Lemma,
            state.Word.MeaningCn,
            state.Word.Phonetic,
            state.Status,
            state.Source,
            state.MistakeCount,
            state.CorrectStreak,
            state.NextReviewAt,
            state.LastReviewedAt,
            state.LastMistakeAt,
            state.CreatedAt,
            state.LastMistakeSentence?.Text,
            state.LastMistakeSentence?.Translation);
    }

    private static IReadOnlyDictionary<string, string> BuildAnswerMap(
        IReadOnlyCollection<BlankAnswerRequest>? answers)
    {
        return (answers ?? Array.Empty<BlankAnswerRequest>())
            .GroupBy(answer => answer.BlankId)
            .ToDictionary(group => group.Key, group => group.Last().Value);
    }

    private static BlankResultResponse[] MapBlankResults(
        IReadOnlyCollection<DictationBlankResult> results)
    {
        return results
            .Select(result => new BlankResultResponse(
                result.BlankId,
                result.Expected,
                result.Answer,
                result.IsCorrect))
            .ToArray();
    }

    private static double CalculateAccuracy(int totalCount, int correctCount)
    {
        return totalCount == 0
            ? 0
            : Math.Round(correctCount * 100.0 / totalCount, 2);
    }
}
