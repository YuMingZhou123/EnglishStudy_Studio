using Api.Domain.Content;
using Api.Domain.Identity;

namespace Api.Domain.Learning;

public sealed class DictationAttempt
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid UserId { get; set; }

    public Guid SentenceId { get; set; }

    public string Mode { get; set; } = "beginner";

    public string UserAnswer { get; set; } = string.Empty;

    public string NormalizedAnswer { get; set; } = string.Empty;

    public double Score { get; set; }

    public bool IsCorrect { get; set; }

    public string? DetailJson { get; set; }

    public int HintCount { get; set; }

    public int ReplayCount { get; set; }

    public int DurationMs { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ApplicationUser User { get; set; } = null!;

    public Sentence Sentence { get; set; } = null!;
}
