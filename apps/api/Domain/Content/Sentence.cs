using Api.Domain.Learning;

namespace Api.Domain.Content;

public sealed class Sentence
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string Text { get; set; } = string.Empty;

    public string Translation { get; set; } = string.Empty;

    public string Level { get; set; } = "beginner";

    public Guid SceneId { get; set; }

    public string? AudioUrl { get; set; }

    public string? SlowAudioUrl { get; set; }

    public Guid? AudioAssetId { get; set; }

    public string Source { get; set; } = "manual";

    public string Status { get; set; } = "draft";

    public Guid? CreatedBy { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public Scene Scene { get; set; } = null!;

    public MediaAsset? AudioAsset { get; set; }

    public ICollection<SentenceKeyword> Keywords { get; } = new List<SentenceKeyword>();

    public ICollection<DictationAttempt> DictationAttempts { get; } = new List<DictationAttempt>();
}
