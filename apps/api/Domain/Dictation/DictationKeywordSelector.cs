using Api.Domain.Content;

namespace Api.Domain.Dictation;

public static class DictationKeywordSelector
{
    public static SentenceKeyword[] Select(Sentence sentence, string mode)
    {
        var ordered = OrderedKeywords(sentence);

        return mode switch
        {
            DictationMode.Beginner => ordered.Take(1).ToArray(),
            DictationMode.Intermediate => ordered.Take(Math.Min(4, Math.Max(2, ordered.Length))).ToArray(),
            DictationMode.Advanced => ordered,
            _ => []
        };
    }

    public static SentenceKeyword[] SelectForReview(
        Sentence sentence,
        string mode,
        Guid reviewWordId)
    {
        var ordered = OrderedKeywords(sentence);
        var targetKeyword = ordered.FirstOrDefault(keyword => keyword.WordId == reviewWordId);
        if (targetKeyword is null)
        {
            return [];
        }

        return mode switch
        {
            DictationMode.Beginner => [targetKeyword],
            DictationMode.Intermediate => ordered
                .Where(keyword => keyword.Id == targetKeyword.Id)
                .Concat(ordered.Where(keyword => keyword.Id != targetKeyword.Id).Take(3))
                .ToArray(),
            DictationMode.Advanced => ordered,
            _ => []
        };
    }

    private static SentenceKeyword[] OrderedKeywords(Sentence sentence)
    {
        return sentence.Keywords
            .OrderByDescending(keyword => keyword.Priority)
            .ThenBy(keyword => keyword.StartIndex)
            .ToArray();
    }
}
