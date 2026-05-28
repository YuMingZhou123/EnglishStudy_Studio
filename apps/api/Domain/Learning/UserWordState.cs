using Api.Domain.Content;
using Api.Domain.Identity;

namespace Api.Domain.Learning;

public sealed class UserWordState
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid UserId { get; set; }

    public Guid WordId { get; set; }

    public string Status { get; set; } = "Learning";

    public string Source { get; set; } = "dictation";

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
}
