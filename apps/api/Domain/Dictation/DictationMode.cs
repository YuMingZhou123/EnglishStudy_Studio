namespace Api.Domain.Dictation;

public static class DictationMode
{
    public const string Beginner = "beginner";
    public const string Intermediate = "intermediate";
    public const string Advanced = "advanced";

    public static string Normalize(string? mode)
    {
        if (string.IsNullOrWhiteSpace(mode))
        {
            return Beginner;
        }

        return mode.Trim().ToLowerInvariant();
    }

    public static string NormalizeOrDefault(string? mode)
    {
        var normalized = Normalize(mode);
        return IsSupported(normalized) ? normalized : Beginner;
    }

    public static bool IsSupported(string mode)
    {
        return mode is Beginner or Intermediate or Advanced;
    }
}
