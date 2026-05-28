using Api.Domain.Content;

namespace Api.Domain.Dictation;

public static class DictationGrader
{
    public static DictationBlankResult[] GradeBlanks(
        IReadOnlyCollection<SentenceKeyword> keywords,
        IReadOnlyDictionary<string, string> answers)
    {
        return keywords
            .Select(keyword =>
            {
                var blankId = DictationBlankId.ForKeyword(keyword);
                answers.TryGetValue(blankId, out var answer);
                var normalizedAnswer = DictationAnswerNormalizer.Normalize(answer);
                var expectedValues = new[]
                {
                    DictationAnswerNormalizer.Normalize(keyword.SurfaceText),
                    DictationAnswerNormalizer.Normalize(keyword.Word.Lemma)
                };

                return new DictationBlankResult(
                    blankId,
                    keyword.SurfaceText,
                    answer,
                    expectedValues.Contains(normalizedAnswer));
            })
            .ToArray();
    }

    public static AdvancedDictationGrade GradeAdvanced(
        Sentence sentence,
        string? userAnswer,
        IReadOnlyCollection<SentenceKeyword> keywords)
    {
        var expectedTokens = DictationAnswerNormalizer.Tokenize(sentence.Text);
        var answerTokens = DictationAnswerNormalizer.Tokenize(userAnswer);
        var distance = CalculateLevenshteinDistance(expectedTokens, answerTokens);
        var denominator = Math.Max(expectedTokens.Length, 1);
        var score = Math.Round(Math.Max(0, denominator - distance) * 100.0 / denominator, 2);

        var feedbackResults = expectedTokens
            .Select((expected, index) =>
            {
                var answer = index < answerTokens.Length ? answerTokens[index] : null;
                return new DictationBlankResult(
                    $"word_{index + 1}",
                    expected,
                    answer,
                    string.Equals(expected, answer, StringComparison.OrdinalIgnoreCase));
            })
            .ToArray();

        var answerTokenSet = answerTokens.ToHashSet(StringComparer.OrdinalIgnoreCase);
        var keywordResults = keywords
            .Select(keyword =>
            {
                var surface = DictationAnswerNormalizer.Normalize(keyword.SurfaceText);
                var lemma = DictationAnswerNormalizer.Normalize(keyword.Word.Lemma);
                return new DictationBlankResult(
                    DictationBlankId.ForKeyword(keyword),
                    keyword.SurfaceText,
                    userAnswer,
                    answerTokenSet.Contains(surface) || answerTokenSet.Contains(lemma));
            })
            .ToArray();

        return new AdvancedDictationGrade(score, feedbackResults, keywordResults);
    }

    public static double CalculateBlankScore(IReadOnlyCollection<DictationBlankResult> results)
    {
        return results.Count == 0
            ? 0
            : Math.Round(results.Count(result => result.IsCorrect) * 100.0 / results.Count, 2);
    }

    private static int CalculateLevenshteinDistance(
        IReadOnlyList<string> expectedTokens,
        IReadOnlyList<string> answerTokens)
    {
        var distances = new int[expectedTokens.Count + 1, answerTokens.Count + 1];

        for (var i = 0; i <= expectedTokens.Count; i++)
        {
            distances[i, 0] = i;
        }

        for (var j = 0; j <= answerTokens.Count; j++)
        {
            distances[0, j] = j;
        }

        for (var i = 1; i <= expectedTokens.Count; i++)
        {
            for (var j = 1; j <= answerTokens.Count; j++)
            {
                var substitutionCost = string.Equals(
                    expectedTokens[i - 1],
                    answerTokens[j - 1],
                    StringComparison.OrdinalIgnoreCase)
                    ? 0
                    : 1;

                distances[i, j] = Math.Min(
                    Math.Min(
                        distances[i - 1, j] + 1,
                        distances[i, j - 1] + 1),
                    distances[i - 1, j - 1] + substitutionCost);
            }
        }

        return distances[expectedTokens.Count, answerTokens.Count];
    }
}

public sealed record DictationBlankResult(
    string BlankId,
    string Expected,
    string? Answer,
    bool IsCorrect);

public sealed record AdvancedDictationGrade(
    double Score,
    IReadOnlyCollection<DictationBlankResult> FeedbackResults,
    IReadOnlyCollection<DictationBlankResult> KeywordResults);
