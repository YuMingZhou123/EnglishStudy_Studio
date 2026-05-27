namespace Api.Domain.Content;

public sealed class Word
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string Lemma { get; set; } = string.Empty;

    public string? Phonetic { get; set; }

    public string? PartOfSpeech { get; set; }

    public string MeaningCn { get; set; } = string.Empty;

    public string? CefrLevel { get; set; }

    public string? ExamTags { get; set; }

    public string? Collocations { get; set; }

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;

    public ICollection<SentenceKeyword> SentenceKeywords { get; } = new List<SentenceKeyword>();
}
