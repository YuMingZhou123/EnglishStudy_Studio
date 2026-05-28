using Api.Domain.Content;
using Api.Domain.Identity;

namespace Api.Domain.Learning;

public sealed class UserWordState
{
    public const string StatusNew = "New";
    public const string StatusReviewing = "Reviewing";
    public const string StatusMastered = "Mastered";
    public const string SourceDictation = "dictation";
    public const string SourceManual = "manual";

    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid UserId { get; set; }

    public Guid WordId { get; set; }

    public string Status { get; set; } = StatusNew;

    public string Source { get; set; } = SourceDictation;

    public int MistakeCount { get; set; }

    public int CorrectStreak { get; set; }

    public DateTimeOffset? NextReviewAt { get; set; }

    public DateTimeOffset? LastReviewedAt { get; set; }

    public DateTimeOffset? LastMistakeAt { get; set; }

    public Guid? LastMistakeSentenceId { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ApplicationUser User { get; set; } = null!;

    public Word Word { get; set; } = null!;

    public Sentence? LastMistakeSentence { get; set; }

    public static UserWordState CreateManual(
        Guid userId,
        Guid wordId,
        DateTimeOffset now)
    {
        return new UserWordState
        {
            UserId = userId,
            WordId = wordId,
            Status = StatusNew,
            Source = SourceManual,
            NextReviewAt = now,
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public static UserWordState CreateFromDictation(
        Guid userId,
        Guid wordId,
        DateTimeOffset now)
    {
        return new UserWordState
        {
            UserId = userId,
            WordId = wordId,
            Status = StatusReviewing,
            Source = SourceDictation,
            CreatedAt = now,
            UpdatedAt = now
        };
    }

    public void MarkManualAdded(DateTimeOffset now)
    {
        Source = string.Equals(Source, SourceDictation, StringComparison.OrdinalIgnoreCase)
            ? Source
            : SourceManual;
        Status = MistakeCount > 0 ? Status : StatusNew;
        NextReviewAt ??= now;
        UpdatedAt = now;
    }

    public void ApplyDictationResult(
        bool isCorrect,
        Guid sentenceId,
        DateTimeOffset now)
    {
        if (isCorrect)
        {
            CorrectStreak += 1;
            Status = CorrectStreak >= 3 ? StatusMastered : StatusReviewing;
            NextReviewAt = CorrectStreak switch
            {
                1 => now.AddDays(1),
                2 => now.AddDays(3),
                _ => now.AddDays(7)
            };
        }
        else
        {
            MistakeCount += 1;
            CorrectStreak = 0;
            Status = StatusReviewing;
            NextReviewAt = now.AddDays(1);
            LastMistakeAt = now;
            LastMistakeSentenceId = sentenceId;
        }

        LastReviewedAt = now;
        UpdatedAt = now;
    }
}
