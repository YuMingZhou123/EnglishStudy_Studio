namespace Api.Domain.Content;

public sealed class MediaAsset
{
    public Guid Id { get; set; } = Guid.NewGuid();

    public string Bucket { get; set; } = string.Empty;

    public string ObjectKey { get; set; } = string.Empty;

    public string Url { get; set; } = string.Empty;

    public string ContentType { get; set; } = string.Empty;

    public long Size { get; set; }

    public string Source { get; set; } = "manual";

    public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;

    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
