namespace Api.Domain.Content;

public sealed class SentenceKeyword
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public Guid SentenceId { get; set; }

    public Guid WordId { get; set; }

    public string SurfaceText { get; set; } = string.Empty;

    public int StartIndex { get; set; }

    public int EndIndex { get; set; }

    public string? BlankGroup { get; set; }

    public int Priority { get; set; }

    public Sentence Sentence { get; set; } = null!;

    public Word Word { get; set; } = null!;
}
