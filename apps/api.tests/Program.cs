using Api.Domain.Content;
using Api.Domain.Dictation;

Run("answer normalization ignores case, punctuation, and repeated spaces", () =>
{
    var normalized = DictationAnswerNormalizer.Normalize("  Schedule,   a MEETING!  ");
    AssertEqual("schedule a meeting", normalized);
});

Run("blank grading accepts surface text and lemma", () =>
{
    var keywords = CreateSentence().Keywords.ToArray();
    var surfaceBlankId = DictationBlankId.ForKeyword(keywords[0]);
    var lemmaBlankId = DictationBlankId.ForKeyword(keywords[4]);

    var results = DictationGrader.GradeBlanks(
        [keywords[0], keywords[4]],
        new Dictionary<string, string>
        {
            [surfaceBlankId] = "Schedule",
            [lemmaBlankId] = "decide!"
        });

    AssertTrue(results.All(result => result.IsCorrect), "Expected surface and lemma answers to be correct.");
    AssertEqual(100, DictationGrader.CalculateBlankScore(results));
});

Run("keyword selector follows difficulty rules", () =>
{
    var sentence = CreateSentence();

    var beginner = DictationKeywordSelector.Select(sentence, DictationMode.Beginner);
    var intermediate = DictationKeywordSelector.Select(sentence, DictationMode.Intermediate);
    var advanced = DictationKeywordSelector.Select(sentence, DictationMode.Advanced);

    AssertEqual(1, beginner.Length);
    AssertEqual("schedule", beginner[0].Word.Lemma);
    AssertEqual(4, intermediate.Length);
    AssertEqual(sentence.Keywords.Count, advanced.Length);
});

Run("review keyword is kept first for intermediate review", () =>
{
    var sentence = CreateSentence();
    var reviewWordId = sentence.Keywords.Last().WordId;

    var selected = DictationKeywordSelector.SelectForReview(
        sentence,
        DictationMode.Intermediate,
        reviewWordId);

    AssertEqual(4, selected.Length);
    AssertEqual(reviewWordId, selected[0].WordId);
});

Run("advanced grading gives full score for normalized exact answer", () =>
{
    var sentence = CreateSentence();
    var grade = DictationGrader.GradeAdvanced(
        sentence,
        "please schedule a meeting before we make a decision",
        sentence.Keywords.ToArray());

    AssertEqual(100, grade.Score);
    AssertTrue(grade.KeywordResults.All(result => result.IsCorrect), "Expected all target keywords to be found.");
});

Run("advanced grading penalizes missing words", () =>
{
    var sentence = CreateSentence();
    var grade = DictationGrader.GradeAdvanced(sentence, "please schedule a meeting", sentence.Keywords.ToArray());

    AssertTrue(grade.Score < 100, "Expected incomplete advanced answer to lose score.");
    AssertTrue(grade.FeedbackResults.Any(result => !result.IsCorrect), "Expected at least one incorrect feedback item.");
});

Console.WriteLine("Domain rule tests passed.");

static Sentence CreateSentence()
{
    var scene = new Scene
    {
        Id = Guid.NewGuid(),
        Code = "workplace",
        Name = "Workplace"
    };

    var sentence = new Sentence
    {
        Id = Guid.NewGuid(),
        Text = "Please schedule a meeting before we make a decision.",
        Translation = "Please arrange a meeting before we decide.",
        Level = DictationMode.Intermediate,
        SceneId = scene.Id,
        Scene = scene,
        Status = "published"
    };

    sentence.Keywords.Add(CreateKeyword(sentence, "schedule", "schedule", 0, 8, 100));
    sentence.Keywords.Add(CreateKeyword(sentence, "meeting", "meeting", 11, 18, 90));
    sentence.Keywords.Add(CreateKeyword(sentence, "before", "before", 19, 25, 80));
    sentence.Keywords.Add(CreateKeyword(sentence, "make", "make", 29, 33, 70));
    sentence.Keywords.Add(CreateKeyword(sentence, "decide", "decision", 36, 44, 60));

    return sentence;
}

static SentenceKeyword CreateKeyword(
    Sentence sentence,
    string lemma,
    string surfaceText,
    int startIndex,
    int endIndex,
    int priority)
{
    var word = new Word
    {
        Id = Guid.NewGuid(),
        Lemma = lemma,
        MeaningCn = lemma
    };

    return new SentenceKeyword
    {
        Id = Guid.NewGuid(),
        SentenceId = sentence.Id,
        Sentence = sentence,
        WordId = word.Id,
        Word = word,
        SurfaceText = surfaceText,
        StartIndex = startIndex,
        EndIndex = endIndex,
        Priority = priority
    };
}

static void Run(string name, Action test)
{
    try
    {
        test();
        Console.WriteLine($"[pass] {name}");
    }
    catch (Exception exception)
    {
        throw new InvalidOperationException($"Domain rule test failed: {name}", exception);
    }
}

static void AssertEqual<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected {expected}, got {actual}.");
    }
}

static void AssertTrue(bool condition, string message)
{
    if (!condition)
    {
        throw new InvalidOperationException(message);
    }
}
