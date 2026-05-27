using System.Text.Json;
using System.Text.RegularExpressions;
using Api.Application.Auth;
using Api.Application.Common.Interfaces;
using Api.Domain.Content;
using Api.Domain.Learning;
using Microsoft.EntityFrameworkCore;

namespace Api.Application.Dictation;

public sealed partial class DictationService(IAppDbContext dbContext) : IDictationService
{
    private const string Beginner = "beginner";
    private const string Intermediate = "intermediate";
    private const string Advanced = "advanced";

    public async Task<ServiceResult<DictationQuestionResponse>> GetNextQuestionAsync(
        Guid userId,
        string mode,
        CancellationToken cancellationToken = default)
    {
        mode = NormalizeMode(mode);
        if (!IsValidMode(mode))
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

    public async Task<ServiceResult<DictationSubmitResponse>> SubmitAsync(
        Guid userId,
        SubmitDictationRequest request,
        CancellationToken cancellationToken = default)
    {
        var mode = NormalizeMode(request.Mode);
        if (!IsValidMode(mode))
        {
            return ServiceResult<DictationSubmitResponse>.Failure("Unsupported dictation mode.");
        }

        var sentence = await PublishedSentencesQuery()
            .FirstOrDefaultAsync(item => item.Id == request.SentenceId, cancellationToken);

        if (sentence is null)
        {
            return ServiceResult<DictationSubmitResponse>.Failure("Sentence was not found.");
        }

        var selectedKeywords = SelectKeywords(sentence, mode).ToArray();
        var targetWords = selectedKeywords.Select(MapTargetWord).ToArray();
        var blankResults = mode == Advanced
            ? GradeAdvanced(sentence, request.UserAnswer, selectedKeywords)
            : GradeBlanks(selectedKeywords, request.Answers);

        var score = blankResults.Length == 0
            ? 0
            : Math.Round(blankResults.Count(result => result.IsCorrect) * 100.0 / blankResults.Length, 2);
        var isCorrect = score >= 99.99;
        var now = DateTimeOffset.UtcNow;
        var normalizedAnswer = mode == Advanced
            ? NormalizeAnswer(request.UserAnswer)
            : NormalizeAnswer(string.Join(
                " ",
                request.Answers?.OrderBy(answer => answer.BlankId).Select(answer => answer.Value) ?? Array.Empty<string>()));

        var attempt = new DictationAttempt
        {
            UserId = userId,
            SentenceId = sentence.Id,
            Mode = mode,
            UserAnswer = mode == Advanced
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
        await UpdateUserWordStatesAsync(userId, selectedKeywords, blankResults, now, cancellationToken);
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
        return await dbContext.UserWordStates
            .AsNoTracking()
            .Where(state => state.UserId == userId && state.MistakeCount > 0)
            .Include(state => state.Word)
            .OrderByDescending(state => state.UpdatedAt)
            .Select(state => new WrongWordResponse(
                state.WordId,
                state.Word.Lemma,
                state.Word.MeaningCn,
                state.Word.Phonetic,
                state.Status,
                state.MistakeCount,
                state.CorrectStreak,
                state.NextReviewAt,
                state.LastReviewedAt))
            .ToListAsync(cancellationToken);
    }

    private IQueryable<Sentence> PublishedSentencesQuery()
    {
        return dbContext.Sentences
            .AsSplitQuery()
            .Include(sentence => sentence.Scene)
            .Include(sentence => sentence.Keywords)
            .ThenInclude(keyword => keyword.Word)
            .Where(sentence => sentence.Status == "published");
    }

    private static DictationQuestionResponse BuildQuestion(Sentence sentence, string mode)
    {
        var selectedKeywords = SelectKeywords(sentence, mode).ToArray();
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
            selectedKeywords.Select(MapTargetWord).ToArray());
    }

    private static IReadOnlyCollection<DisplayPartResponse> BuildDisplayParts(
        string sentenceText,
        IReadOnlyCollection<SentenceKeyword> keywords,
        string mode)
    {
        if (mode == Advanced)
        {
            return
            [
                new DisplayPartResponse("blank", null, "full_sentence", sentenceText.Length)
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
                BuildBlankId(keyword),
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

    private static SentenceKeyword[] SelectKeywords(Sentence sentence, string mode)
    {
        var ordered = sentence.Keywords
            .OrderByDescending(keyword => keyword.Priority)
            .ThenBy(keyword => keyword.StartIndex)
            .ToArray();

        return mode switch
        {
            Beginner => ordered.Take(1).ToArray(),
            Intermediate => ordered.Take(Math.Min(4, Math.Max(2, ordered.Length))).ToArray(),
            Advanced => ordered,
            _ => []
        };
    }

    private static BlankResultResponse[] GradeBlanks(
        IReadOnlyCollection<SentenceKeyword> keywords,
        IReadOnlyCollection<BlankAnswerRequest>? answers)
    {
        var answerMap = (answers ?? Array.Empty<BlankAnswerRequest>())
            .GroupBy(answer => answer.BlankId)
            .ToDictionary(group => group.Key, group => group.Last().Value);

        return keywords
            .Select(keyword =>
            {
                var blankId = BuildBlankId(keyword);
                answerMap.TryGetValue(blankId, out var answer);
                var normalizedAnswer = NormalizeAnswer(answer);
                var expectedValues = new[]
                {
                    NormalizeAnswer(keyword.SurfaceText),
                    NormalizeAnswer(keyword.Word.Lemma)
                };

                return new BlankResultResponse(
                    blankId,
                    keyword.SurfaceText,
                    answer,
                    expectedValues.Contains(normalizedAnswer));
            })
            .ToArray();
    }

    private static BlankResultResponse[] GradeAdvanced(
        Sentence sentence,
        string? userAnswer,
        IReadOnlyCollection<SentenceKeyword> keywords)
    {
        var normalizedExpected = NormalizeAnswer(sentence.Text);
        var normalizedAnswer = NormalizeAnswer(userAnswer);

        if (normalizedExpected == normalizedAnswer)
        {
            return
            [
                new BlankResultResponse("full_sentence", sentence.Text, userAnswer, true)
            ];
        }

        var answerTokens = normalizedAnswer
            .Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        var keywordResults = keywords
            .Select(keyword =>
            {
                var surface = NormalizeAnswer(keyword.SurfaceText);
                var lemma = NormalizeAnswer(keyword.Word.Lemma);
                return new BlankResultResponse(
                    BuildBlankId(keyword),
                    keyword.SurfaceText,
                    userAnswer,
                    answerTokens.Contains(surface) || answerTokens.Contains(lemma));
            })
            .ToArray();

        return keywordResults.Length == 0
            ? [new BlankResultResponse("full_sentence", sentence.Text, userAnswer, false)]
            : keywordResults;
    }

    private async Task UpdateUserWordStatesAsync(
        Guid userId,
        IReadOnlyCollection<SentenceKeyword> keywords,
        IReadOnlyCollection<BlankResultResponse> results,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var resultMap = results.ToDictionary(result => result.BlankId, result => result.IsCorrect);

        foreach (var keyword in keywords)
        {
            var blankId = BuildBlankId(keyword);
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
                state = new UserWordState
                {
                    UserId = userId,
                    WordId = keyword.WordId,
                    Status = "Reviewing",
                    Source = "dictation",
                    CreatedAt = now
                };

                dbContext.UserWordStates.Add(state);
            }

            if (isCorrect)
            {
                state.CorrectStreak += 1;
                state.Status = state.CorrectStreak >= 3 ? "Mastered" : state.Status;
            }
            else
            {
                state.MistakeCount += 1;
                state.CorrectStreak = 0;
                state.Status = "Reviewing";
                state.NextReviewAt = now.AddDays(1);
            }

            state.LastReviewedAt = now;
            state.UpdatedAt = now;
        }
    }

    private static TargetWordResponse MapTargetWord(SentenceKeyword keyword)
    {
        return new TargetWordResponse(
            BuildBlankId(keyword),
            keyword.WordId,
            keyword.SurfaceText,
            keyword.Word.Lemma,
            keyword.Word.MeaningCn,
            string.IsNullOrWhiteSpace(keyword.SurfaceText)
                ? null
                : keyword.SurfaceText[..1]);
    }

    private static string BuildBlankId(SentenceKeyword keyword)
    {
        return $"kw_{keyword.Id:N}";
    }

    private static string NormalizeMode(string? mode)
    {
        return string.IsNullOrWhiteSpace(mode)
            ? Beginner
            : mode.Trim().ToLowerInvariant();
    }

    private static bool IsValidMode(string mode)
    {
        return mode is Beginner or Intermediate or Advanced;
    }

    private static string NormalizeAnswer(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var normalized = value.Trim().ToLowerInvariant();
        normalized = NonAnswerCharactersRegex().Replace(normalized, " ");
        normalized = WhitespaceRegex().Replace(normalized, " ");
        return normalized.Trim();
    }

    [GeneratedRegex("[^a-z0-9'\\s]+", RegexOptions.Compiled)]
    private static partial Regex NonAnswerCharactersRegex();

    [GeneratedRegex("\\s+", RegexOptions.Compiled)]
    private static partial Regex WhitespaceRegex();
}
