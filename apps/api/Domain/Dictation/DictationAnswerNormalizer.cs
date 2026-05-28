using System.Text.RegularExpressions;

namespace Api.Domain.Dictation;

public static partial class DictationAnswerNormalizer
{
    public static string Normalize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var normalized = value.Trim().ToLowerInvariant();
        normalized = NonAnswerCharactersRegex().Replace(normalized, " ");
        normalized = WhitespaceRegex().Replace(normalized, " ");
        return normalized.Trim();
    }

    public static string[] Tokenize(string? value)
    {
        return Normalize(value).Split(
            ' ',
            StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
    }

    [GeneratedRegex("[^a-z0-9'\\s]+", RegexOptions.Compiled)]
    private static partial Regex NonAnswerCharactersRegex();

    [GeneratedRegex("\\s+", RegexOptions.Compiled)]
    private static partial Regex WhitespaceRegex();
}
