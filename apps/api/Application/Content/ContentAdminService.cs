using System.Text.RegularExpressions;
using Api.Application.Auth;
using Api.Application.Common.Interfaces;
using Api.Domain.Content;
using Microsoft.EntityFrameworkCore;

namespace Api.Application.Content;

public sealed partial class ContentAdminService(
    IAppDbContext dbContext,
    IFileStorageService fileStorageService,
    ITtsProvider ttsProvider) : IContentAdminService
{
    public async Task<IReadOnlyCollection<SceneResponse>> GetScenesAsync(
        CancellationToken cancellationToken = default)
    {
        return await dbContext.Scenes
            .AsNoTracking()
            .OrderBy(scene => scene.Code)
            .Select(scene => new SceneResponse(
                scene.Id,
                scene.Code,
                scene.Name,
                scene.Description,
                scene.IsEnabled))
            .ToListAsync(cancellationToken);
    }

    public async Task<ServiceResult<SceneResponse>> CreateSceneAsync(
        UpsertSceneRequest request,
        CancellationToken cancellationToken = default)
    {
        var code = NormalizeCode(request.Code);
        if (string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(request.Name))
        {
            return ServiceResult<SceneResponse>.Failure("Scene code and name are required.");
        }

        var exists = await dbContext.Scenes.AnyAsync(
            scene => scene.Code == code,
            cancellationToken);
        if (exists)
        {
            return ServiceResult<SceneResponse>.Failure("Scene code already exists.");
        }

        var now = DateTimeOffset.UtcNow;
        var scene = new Scene
        {
            Code = code,
            Name = request.Name.Trim(),
            Description = string.IsNullOrWhiteSpace(request.Description)
                ? null
                : request.Description.Trim(),
            IsEnabled = request.IsEnabled,
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.Scenes.Add(scene);
        await dbContext.SaveChangesAsync(cancellationToken);

        return ServiceResult<SceneResponse>.Success(MapScene(scene));
    }

    public async Task<ServiceResult<SceneResponse>> UpdateSceneAsync(
        Guid sceneId,
        UpsertSceneRequest request,
        CancellationToken cancellationToken = default)
    {
        var scene = await dbContext.Scenes
            .FirstOrDefaultAsync(item => item.Id == sceneId, cancellationToken);

        if (scene is null)
        {
            return ServiceResult<SceneResponse>.Failure("Scene was not found.");
        }

        var code = NormalizeCode(request.Code);
        if (string.IsNullOrWhiteSpace(code) || string.IsNullOrWhiteSpace(request.Name))
        {
            return ServiceResult<SceneResponse>.Failure("Scene code and name are required.");
        }

        var exists = await dbContext.Scenes.AnyAsync(
            item => item.Id != sceneId && item.Code == code,
            cancellationToken);
        if (exists)
        {
            return ServiceResult<SceneResponse>.Failure("Scene code already exists.");
        }

        scene.Code = code;
        scene.Name = request.Name.Trim();
        scene.Description = TrimToNull(request.Description);
        scene.IsEnabled = request.IsEnabled;
        scene.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SaveChangesAsync(cancellationToken);
        return ServiceResult<SceneResponse>.Success(MapScene(scene));
    }

    public async Task<IReadOnlyCollection<WordResponse>> GetWordsAsync(
        string? keyword = null,
        CancellationToken cancellationToken = default)
    {
        var query = dbContext.Words.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(keyword))
        {
            var normalized = keyword.Trim().ToLowerInvariant();
            query = query.Where(word =>
                word.Lemma.ToLower().Contains(normalized) ||
                word.MeaningCn.Contains(normalized));
        }

        var words = await query
            .OrderBy(word => word.Lemma)
            .Take(200)
            .ToListAsync(cancellationToken);

        return words.Select(MapWord).ToArray();
    }

    public async Task<ServiceResult<WordResponse>> CreateWordAsync(
        UpsertWordRequest request,
        CancellationToken cancellationToken = default)
    {
        var lemma = NormalizeWord(request.Lemma);
        if (string.IsNullOrWhiteSpace(lemma) || string.IsNullOrWhiteSpace(request.MeaningCn))
        {
            return ServiceResult<WordResponse>.Failure("Word lemma and Chinese meaning are required.");
        }

        var exists = await dbContext.Words.AnyAsync(word => word.Lemma == lemma, cancellationToken);
        if (exists)
        {
            return ServiceResult<WordResponse>.Failure("Word already exists.");
        }

        var now = DateTimeOffset.UtcNow;
        var word = new Word
        {
            Lemma = lemma,
            Phonetic = TrimToNull(request.Phonetic),
            PartOfSpeech = TrimToNull(request.PartOfSpeech),
            MeaningCn = request.MeaningCn.Trim(),
            CefrLevel = TrimToNull(request.CefrLevel),
            ExamTags = TrimToNull(request.ExamTags),
            Collocations = TrimToNull(request.Collocations),
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.Words.Add(word);
        await dbContext.SaveChangesAsync(cancellationToken);

        return ServiceResult<WordResponse>.Success(MapWord(word));
    }

    public async Task<ServiceResult<WordResponse>> UpdateWordAsync(
        Guid wordId,
        UpsertWordRequest request,
        CancellationToken cancellationToken = default)
    {
        var word = await dbContext.Words
            .FirstOrDefaultAsync(item => item.Id == wordId, cancellationToken);

        if (word is null)
        {
            return ServiceResult<WordResponse>.Failure("Word was not found.");
        }

        var lemma = NormalizeWord(request.Lemma);
        if (string.IsNullOrWhiteSpace(lemma) || string.IsNullOrWhiteSpace(request.MeaningCn))
        {
            return ServiceResult<WordResponse>.Failure("Word lemma and Chinese meaning are required.");
        }

        var exists = await dbContext.Words.AnyAsync(
            item => item.Id != wordId && item.Lemma == lemma,
            cancellationToken);
        if (exists)
        {
            return ServiceResult<WordResponse>.Failure("Word already exists.");
        }

        word.Lemma = lemma;
        word.Phonetic = TrimToNull(request.Phonetic);
        word.PartOfSpeech = TrimToNull(request.PartOfSpeech);
        word.MeaningCn = request.MeaningCn.Trim();
        word.CefrLevel = TrimToNull(request.CefrLevel);
        word.ExamTags = TrimToNull(request.ExamTags);
        word.Collocations = TrimToNull(request.Collocations);
        word.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SaveChangesAsync(cancellationToken);
        return ServiceResult<WordResponse>.Success(MapWord(word));
    }

    public async Task<IReadOnlyCollection<SentenceResponse>> GetSentencesAsync(
        string? status = null,
        string? level = null,
        CancellationToken cancellationToken = default)
    {
        var query = SentencesQuery().AsNoTracking();

        if (!string.IsNullOrWhiteSpace(status))
        {
            var normalizedStatus = NormalizeStatus(status);
            query = query.Where(sentence => sentence.Status == normalizedStatus);
        }

        if (!string.IsNullOrWhiteSpace(level))
        {
            var normalizedLevel = NormalizeLevel(level);
            query = query.Where(sentence => sentence.Level == normalizedLevel);
        }

        var sentences = await query
            .OrderByDescending(sentence => sentence.UpdatedAt)
            .Take(200)
            .ToListAsync(cancellationToken);

        return sentences.Select(MapSentence).ToArray();
    }

    public async Task<ServiceResult<SentenceResponse>> CreateSentenceAsync(
        CreateSentenceRequest request,
        Guid createdBy,
        CancellationToken cancellationToken = default)
    {
        var validation = await ValidateSentenceRequestAsync(
            request.Text,
            request.Translation,
            request.SceneId,
            request.Keywords,
            cancellationToken);
        if (!validation.Succeeded)
        {
            return ServiceResult<SentenceResponse>.Failure(validation.Errors.ToArray());
        }

        var now = DateTimeOffset.UtcNow;
        var sentence = new Sentence
        {
            Text = request.Text.Trim(),
            Translation = request.Translation.Trim(),
            Level = NormalizeLevel(request.Level),
            SceneId = request.SceneId,
            AudioAssetId = request.AudioAssetId,
            AudioUrl = TrimToNull(request.AudioUrl),
            Source = "manual",
            Status = NormalizeStatus(request.Status),
            CreatedBy = createdBy,
            CreatedAt = now,
            UpdatedAt = now
        };

        await AddKeywordsAsync(sentence, request.Keywords, cancellationToken);
        dbContext.Sentences.Add(sentence);
        await dbContext.SaveChangesAsync(cancellationToken);

        return await GetSentenceResultAsync(sentence.Id, cancellationToken);
    }

    public async Task<ServiceResult<SentenceResponse>> UpdateSentenceAsync(
        Guid sentenceId,
        UpdateSentenceRequest request,
        CancellationToken cancellationToken = default)
    {
        var sentence = await dbContext.Sentences
            .FirstOrDefaultAsync(item => item.Id == sentenceId, cancellationToken);

        if (sentence is null)
        {
            return ServiceResult<SentenceResponse>.Failure("Sentence was not found.");
        }

        var validation = await ValidateSentenceRequestAsync(
            request.Text,
            request.Translation,
            request.SceneId,
            request.Keywords,
            cancellationToken);
        if (!validation.Succeeded)
        {
            return ServiceResult<SentenceResponse>.Failure(validation.Errors.ToArray());
        }

        sentence.Text = request.Text.Trim();
        sentence.Translation = request.Translation.Trim();
        sentence.Level = NormalizeLevel(request.Level);
        sentence.SceneId = request.SceneId;
        sentence.AudioAssetId = request.AudioAssetId;
        sentence.AudioUrl = TrimToNull(request.AudioUrl);
        sentence.Status = NormalizeStatus(request.Status);
        sentence.UpdatedAt = DateTimeOffset.UtcNow;

        await dbContext.SentenceKeywords
            .Where(keyword => keyword.SentenceId == sentence.Id)
            .ExecuteDeleteAsync(cancellationToken);
        await AddKeywordsAsync(sentence, request.Keywords, cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);

        return await GetSentenceResultAsync(sentence.Id, cancellationToken);
    }

    public async Task<ServiceResult<SentenceResponse>> SetSentenceStatusAsync(
        Guid sentenceId,
        string status,
        CancellationToken cancellationToken = default)
    {
        var sentence = await dbContext.Sentences
            .FirstOrDefaultAsync(item => item.Id == sentenceId, cancellationToken);

        if (sentence is null)
        {
            return ServiceResult<SentenceResponse>.Failure("Sentence was not found.");
        }

        sentence.Status = NormalizeStatus(status);
        sentence.UpdatedAt = DateTimeOffset.UtcNow;
        await dbContext.SaveChangesAsync(cancellationToken);

        return await GetSentenceResultAsync(sentence.Id, cancellationToken);
    }

    public async Task<ServiceResult<MediaAssetResponse>> UploadMediaAsync(
        UploadMediaRequest request,
        CancellationToken cancellationToken = default)
    {
        if (request.Size <= 0)
        {
            return ServiceResult<MediaAssetResponse>.Failure("File is empty.");
        }

        var folder = NormalizeCode(request.Folder);
        if (string.IsNullOrWhiteSpace(folder))
        {
            folder = "uploads";
        }

        var safeFileName = SafeFileNameRegex().Replace(request.FileName.Trim(), "-");
        var objectKey = $"{folder}/{DateTimeOffset.UtcNow:yyyy/MM/dd}/{Guid.NewGuid():N}-{safeFileName}";
        var storedFile = await fileStorageService.UploadAsync(
            request.Stream,
            objectKey,
            request.ContentType,
            request.Size,
            cancellationToken);

        var now = DateTimeOffset.UtcNow;
        var mediaAsset = new MediaAsset
        {
            Bucket = storedFile.Bucket,
            ObjectKey = storedFile.ObjectKey,
            Url = storedFile.Url,
            ContentType = storedFile.ContentType,
            Size = storedFile.Size,
            Source = "upload",
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.MediaAssets.Add(mediaAsset);
        await dbContext.SaveChangesAsync(cancellationToken);

        return ServiceResult<MediaAssetResponse>.Success(MapMedia(mediaAsset));
    }

    public async Task<ServiceResult<SentenceResponse>> GenerateSentenceAudioAsync(
        Guid sentenceId,
        GenerateSentenceAudioRequest request,
        CancellationToken cancellationToken = default)
    {
        var sentence = await dbContext.Sentences
            .FirstOrDefaultAsync(item => item.Id == sentenceId, cancellationToken);

        if (sentence is null)
        {
            return ServiceResult<SentenceResponse>.Failure("Sentence was not found.");
        }

        var audio = await ttsProvider.SynthesizeAsync(
            new TtsRequest(sentence.Text, request.Voice, request.Speed),
            cancellationToken);

        await using var stream = new MemoryStream(audio.AudioBytes);
        var objectKey = $"audio/tts/{DateTimeOffset.UtcNow:yyyy/MM/dd}/{sentence.Id:N}-{Guid.NewGuid():N}{audio.FileExtension}";
        var storedFile = await fileStorageService.UploadAsync(
            stream,
            objectKey,
            audio.ContentType,
            audio.AudioBytes.LongLength,
            cancellationToken);

        var now = DateTimeOffset.UtcNow;
        var mediaAsset = new MediaAsset
        {
            Bucket = storedFile.Bucket,
            ObjectKey = storedFile.ObjectKey,
            Url = storedFile.Url,
            ContentType = storedFile.ContentType,
            Size = storedFile.Size,
            Source = $"tts:{audio.Provider}",
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.MediaAssets.Add(mediaAsset);
        sentence.AudioAsset = mediaAsset;
        sentence.AudioAssetId = mediaAsset.Id;
        sentence.AudioUrl = mediaAsset.Url;
        sentence.UpdatedAt = now;
        await dbContext.SaveChangesAsync(cancellationToken);

        return await GetSentenceResultAsync(sentence.Id, cancellationToken);
    }

    private IQueryable<Sentence> SentencesQuery()
    {
        return dbContext.Sentences
            .AsSplitQuery()
            .Include(sentence => sentence.Scene)
            .Include(sentence => sentence.AudioAsset)
            .Include(sentence => sentence.Keywords)
            .ThenInclude(keyword => keyword.Word);
    }

    private async Task<ServiceResult<bool>> ValidateSentenceRequestAsync(
        string text,
        string translation,
        Guid sceneId,
        IReadOnlyCollection<SentenceKeywordRequest> keywords,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(text) || string.IsNullOrWhiteSpace(translation))
        {
            return ServiceResult<bool>.Failure("Sentence text and translation are required.");
        }

        var sceneExists = await dbContext.Scenes.AnyAsync(
            scene => scene.Id == sceneId,
            cancellationToken);
        if (!sceneExists)
        {
            return ServiceResult<bool>.Failure("Scene was not found.");
        }

        if (keywords.Count == 0)
        {
            return ServiceResult<bool>.Failure("At least one target keyword is required.");
        }

        foreach (var keyword in keywords)
        {
            if (string.IsNullOrWhiteSpace(keyword.SurfaceText))
            {
                return ServiceResult<bool>.Failure("Keyword surface text is required.");
            }

            if (!text.Contains(keyword.SurfaceText.Trim(), StringComparison.OrdinalIgnoreCase))
            {
                return ServiceResult<bool>.Failure($"Keyword '{keyword.SurfaceText}' does not appear in the sentence.");
            }

            var wordExists = await dbContext.Words.AnyAsync(
                word => word.Id == keyword.WordId,
                cancellationToken);
            if (!wordExists)
            {
                return ServiceResult<bool>.Failure($"Word '{keyword.WordId}' was not found.");
            }
        }

        return ServiceResult<bool>.Success(true);
    }

    private Task AddKeywordsAsync(
        Sentence sentence,
        IReadOnlyCollection<SentenceKeywordRequest> keywords,
        CancellationToken cancellationToken)
    {
        foreach (var request in keywords)
        {
            var surfaceText = request.SurfaceText.Trim();
            var startIndex = sentence.Text.IndexOf(surfaceText, StringComparison.OrdinalIgnoreCase);

            dbContext.SentenceKeywords.Add(new SentenceKeyword
            {
                SentenceId = sentence.Id,
                Sentence = sentence,
                WordId = request.WordId,
                SurfaceText = surfaceText,
                StartIndex = startIndex,
                EndIndex = startIndex + surfaceText.Length,
                BlankGroup = TrimToNull(request.BlankGroup),
                Priority = request.Priority
            });
        }

        return Task.CompletedTask;
    }

    private async Task<ServiceResult<SentenceResponse>> GetSentenceResultAsync(
        Guid sentenceId,
        CancellationToken cancellationToken)
    {
        var sentence = await SentencesQuery()
            .FirstOrDefaultAsync(item => item.Id == sentenceId, cancellationToken);

        return sentence is null
            ? ServiceResult<SentenceResponse>.Failure("Sentence was not found.")
            : ServiceResult<SentenceResponse>.Success(MapSentence(sentence));
    }

    private static SceneResponse MapScene(Scene scene)
    {
        return new SceneResponse(scene.Id, scene.Code, scene.Name, scene.Description, scene.IsEnabled);
    }

    private static WordResponse MapWord(Word word)
    {
        return new WordResponse(
            word.Id,
            word.Lemma,
            word.Phonetic,
            word.PartOfSpeech,
            word.MeaningCn,
            word.CefrLevel,
            word.ExamTags,
            word.Collocations);
    }

    private static MediaAssetResponse MapMedia(MediaAsset mediaAsset)
    {
        return new MediaAssetResponse(
            mediaAsset.Id,
            mediaAsset.Bucket,
            mediaAsset.ObjectKey,
            mediaAsset.Url,
            mediaAsset.ContentType,
            mediaAsset.Size,
            mediaAsset.Source);
    }

    private static SentenceResponse MapSentence(Sentence sentence)
    {
        return new SentenceResponse(
            sentence.Id,
            sentence.Text,
            sentence.Translation,
            sentence.Level,
            sentence.SceneId,
            sentence.Scene.Name,
            sentence.AudioAsset?.Url ?? sentence.AudioUrl,
            sentence.SlowAudioUrl,
            sentence.AudioAssetId,
            sentence.Source,
            sentence.Status,
            sentence.Keywords
                .OrderByDescending(keyword => keyword.Priority)
                .ThenBy(keyword => keyword.StartIndex)
                .Select(keyword => new SentenceKeywordResponse(
                    keyword.Id,
                    keyword.WordId,
                    keyword.SurfaceText,
                    keyword.StartIndex,
                    keyword.EndIndex,
                    keyword.BlankGroup,
                    keyword.Priority,
                    MapWord(keyword.Word)))
                .ToArray());
    }

    private static string NormalizeLevel(string value)
    {
        var normalized = value.Trim().ToLowerInvariant();
        return normalized is "beginner" or "intermediate" or "advanced"
            ? normalized
            : "beginner";
    }

    private static string NormalizeStatus(string value)
    {
        var normalized = value.Trim().ToLowerInvariant();
        return normalized is "draft" or "published" or "offline"
            ? normalized
            : "draft";
    }

    private static string NormalizeCode(string? value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? string.Empty
            : CodeRegex().Replace(value.Trim().ToLowerInvariant(), "-").Trim('-');
    }

    private static string NormalizeWord(string? value)
    {
        return string.IsNullOrWhiteSpace(value)
            ? string.Empty
            : value.Trim().ToLowerInvariant();
    }

    private static string? TrimToNull(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }

    [GeneratedRegex("[^a-z0-9-]+", RegexOptions.Compiled)]
    private static partial Regex CodeRegex();

    [GeneratedRegex("[^a-zA-Z0-9._-]+", RegexOptions.Compiled)]
    private static partial Regex SafeFileNameRegex();
}
