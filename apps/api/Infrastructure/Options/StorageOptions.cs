namespace Api.Infrastructure.Options;

public sealed class StorageOptions
{
    public const string SectionName = "Storage";

    public string Endpoint { get; init; } = "localhost:9000";

    public string Bucket { get; init; } = "english-study";

    public string AccessKey { get; init; } = "englishstudy";

    public string SecretKey { get; init; } = "englishstudysecret";

    public bool UseSSL { get; init; }

    public Uri GetEndpointUri()
    {
        if (Endpoint.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
            Endpoint.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            return new Uri(Endpoint);
        }

        var scheme = UseSSL ? "https" : "http";
        return new Uri($"{scheme}://{Endpoint}");
    }
}
