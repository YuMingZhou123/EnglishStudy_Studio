using Api.Domain.Content;

namespace Api.Domain.Dictation;

public static class DictationBlankId
{
    public const string FullSentence = "full_sentence";

    public static string ForKeyword(SentenceKeyword keyword)
    {
        return ForKeyword(keyword.Id);
    }

    public static string ForKeyword(Guid keywordId)
    {
        return $"kw_{keywordId:N}";
    }
}
