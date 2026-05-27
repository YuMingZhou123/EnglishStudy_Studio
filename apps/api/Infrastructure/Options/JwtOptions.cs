namespace Api.Infrastructure.Options;

public sealed class JwtOptions
{
    public const string SectionName = "Jwt";

    public string Issuer { get; init; } = "EnglishStudyStudio";

    public string Audience { get; init; } = "EnglishStudyStudio";

    public string SigningKey { get; init; } = "change-this-local-development-key";

    public int ExpireMinutes { get; init; } = 1440;
}
