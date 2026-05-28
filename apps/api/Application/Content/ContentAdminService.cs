using System.Text.RegularExpressions;
using Api.Application.Auth;
using Api.Application.Common.Interfaces;
using Api.Domain.Content;
using Api.Domain.Dictation;
using Microsoft.EntityFrameworkCore;

namespace Api.Application.Content;

public sealed partial class ContentAdminService(
    IAppDbContext dbContext,
    IFileStorageService fileStorageService,
    ITtsProvider ttsProvider) : IContentAdminService
{
    private const int AdminListLimit = 1_000;

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
            .Take(AdminListLimit)
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
            .Take(AdminListLimit)
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

        await GenerateAudioForSentenceAsync(
            sentence,
            request.Voice,
            request.Speed,
            cancellationToken);
        await dbContext.SaveChangesAsync(cancellationToken);

        return await GetSentenceResultAsync(sentence.Id, cancellationToken);
    }

    public async Task<ServiceResult<GenerateMissingSentenceAudioResponse>> GenerateMissingSentenceAudioAsync(
        GenerateMissingSentenceAudioRequest request,
        CancellationToken cancellationToken = default)
    {
        var limit = Math.Clamp(request.Limit, 1, 20);
        var query = dbContext.Sentences.AsQueryable();

        if (!string.IsNullOrWhiteSpace(request.Status) &&
            !string.Equals(request.Status, "all", StringComparison.OrdinalIgnoreCase))
        {
            query = query.Where(sentence => sentence.Status == NormalizeStatus(request.Status));
        }

        if (!string.IsNullOrWhiteSpace(request.Level) &&
            !string.Equals(request.Level, "all", StringComparison.OrdinalIgnoreCase))
        {
            query = query.Where(sentence => sentence.Level == NormalizeLevel(request.Level));
        }

        query = request.IncludeExternalAudio
            ? query.Where(sentence => sentence.AudioAssetId == null)
            : query.Where(sentence =>
                sentence.AudioAssetId == null &&
                (sentence.AudioUrl == null || sentence.AudioUrl == string.Empty));

        var totalCandidates = await query.CountAsync(cancellationToken);
        var sentences = await query
            .OrderBy(sentence => sentence.UpdatedAt)
            .Take(limit)
            .ToListAsync(cancellationToken);

        var items = new List<GenerateMissingSentenceAudioItemResponse>();
        foreach (var sentence in sentences)
        {
            try
            {
                var mediaAsset = await GenerateAudioForSentenceAsync(
                    sentence,
                    request.Voice,
                    request.Speed,
                    cancellationToken);

                await dbContext.SaveChangesAsync(cancellationToken);
                items.Add(new GenerateMissingSentenceAudioItemResponse(
                    sentence.Id,
                    sentence.Text,
                    true,
                    mediaAsset.Url,
                    null));
            }
            catch (Exception ex)
            {
                items.Add(new GenerateMissingSentenceAudioItemResponse(
                    sentence.Id,
                    sentence.Text,
                    false,
                    null,
                    ex.Message));
            }
        }

        return ServiceResult<GenerateMissingSentenceAudioResponse>.Success(
            new GenerateMissingSentenceAudioResponse(
                totalCandidates,
                items.Count(item => item.Succeeded),
                items.Count(item => !item.Succeeded),
                items));
    }

    private async Task<MediaAsset> GenerateAudioForSentenceAsync(
        Sentence sentence,
        string? voice,
        double speed,
        CancellationToken cancellationToken)
    {
        var audio = await ttsProvider.SynthesizeAsync(
            new TtsRequest(sentence.Text, voice, speed),
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

        return mediaAsset;
    }

    public async Task<ServiceResult<ImportSentencesResponse>> ImportSentencesAsync(
        ImportSentencesRequest request,
        Guid createdBy,
        CancellationToken cancellationToken = default)
    {
        if (request.Items is null || request.Items.Count == 0)
        {
            return ServiceResult<ImportSentencesResponse>.Failure("At least one sentence item is required.");
        }

        var failures = new List<ImportSentenceFailureResponse>();
        var validRows = new List<(int RowNumber, ImportSentenceItemRequest Item, string SceneCode, string Status)>();
        var seenSentenceTexts = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        var rowNumber = 0;
        foreach (var item in request.Items)
        {
            rowNumber += 1;
            if (item is null)
            {
                failures.Add(new ImportSentenceFailureResponse(
                    rowNumber,
                    string.Empty,
                    ["Import row is empty."]));
                continue;
            }

            var errors = ValidateImportItem(item, request.DefaultStatus, seenSentenceTexts);
            if (errors.Count > 0)
            {
                failures.Add(new ImportSentenceFailureResponse(
                    rowNumber,
                    item?.Text ?? string.Empty,
                    errors));
                continue;
            }

            validRows.Add((
                rowNumber,
                item,
                NormalizeCode(item.SceneCode),
                NormalizeStatus(item.Status ?? request.DefaultStatus)));
        }

        if (validRows.Count == 0)
        {
            return ServiceResult<ImportSentencesResponse>.Success(new ImportSentencesResponse(
                request.Items.Count,
                0,
                0,
                0,
                0,
                failures.Count,
                failures));
        }

        var sceneCodes = validRows
            .Select(row => row.SceneCode)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var sceneCache = await dbContext.Scenes
            .Where(scene => sceneCodes.Contains(scene.Code))
            .ToDictionaryAsync(scene => scene.Code, StringComparer.OrdinalIgnoreCase, cancellationToken);

        var lemmas = validRows
            .SelectMany(row => row.Item.Keywords)
            .Select(keyword => NormalizeWord(keyword.Lemma))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var wordCache = await dbContext.Words
            .Where(word => lemmas.Contains(word.Lemma))
            .ToDictionaryAsync(word => word.Lemma, StringComparer.OrdinalIgnoreCase, cancellationToken);

        var sentenceTexts = validRows
            .Select(row => row.Item.Text.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var sentenceCache = await dbContext.Sentences
            .Where(sentence => sentenceTexts.Contains(sentence.Text))
            .ToDictionaryAsync(sentence => sentence.Text, StringComparer.OrdinalIgnoreCase, cancellationToken);

        var now = DateTimeOffset.UtcNow;
        var createdScenes = 0;
        var createdWords = 0;
        var createdSentences = 0;
        var updatedSentences = 0;
        var skippedCount = failures.Count;

        foreach (var row in validRows)
        {
            var (scene, sceneCreated) = GetOrCreateImportScene(row.Item, row.SceneCode, sceneCache, now);
            if (sceneCreated)
            {
                createdScenes += 1;
            }

            var keywordRequests = new List<SentenceKeywordRequest>();
            foreach (var keyword in row.Item.Keywords)
            {
                var (word, wordCreated) = GetOrCreateImportWord(keyword, wordCache, now);
                if (wordCreated)
                {
                    createdWords += 1;
                }

                keywordRequests.Add(new SentenceKeywordRequest(
                    word.Id,
                    keyword.SurfaceText.Trim(),
                    keyword.Priority,
                    TrimToNull(keyword.BlankGroup)));
            }

            var sentenceText = row.Item.Text.Trim();
            if (sentenceCache.TryGetValue(sentenceText, out var sentence))
            {
                if (!request.UpdateExisting)
                {
                    skippedCount += 1;
                    continue;
                }

                sentence.Translation = row.Item.Translation.Trim();
                sentence.Level = NormalizeLevel(row.Item.Level);
                sentence.SceneId = scene.Id;
                sentence.AudioUrl = TrimToNull(row.Item.AudioUrl);
                sentence.Status = row.Status;
                sentence.UpdatedAt = now;

                await dbContext.SentenceKeywords
                    .Where(keyword => keyword.SentenceId == sentence.Id)
                    .ExecuteDeleteAsync(cancellationToken);
                updatedSentences += 1;
            }
            else
            {
                sentence = new Sentence
                {
                    Text = sentenceText,
                    Translation = row.Item.Translation.Trim(),
                    Level = NormalizeLevel(row.Item.Level),
                    SceneId = scene.Id,
                    AudioUrl = TrimToNull(row.Item.AudioUrl),
                    Source = "import",
                    Status = row.Status,
                    CreatedBy = createdBy,
                    CreatedAt = now,
                    UpdatedAt = now
                };

                dbContext.Sentences.Add(sentence);
                sentenceCache[sentence.Text] = sentence;
                createdSentences += 1;
            }

            await AddKeywordsAsync(sentence, keywordRequests, cancellationToken);
        }

        await dbContext.SaveChangesAsync(cancellationToken);

        return ServiceResult<ImportSentencesResponse>.Success(new ImportSentencesResponse(
            request.Items.Count,
            createdScenes,
            createdWords,
            createdSentences,
            updatedSentences,
            skippedCount,
            failures));
    }

    private static List<string> ValidateImportItem(
        ImportSentenceItemRequest item,
        string defaultStatus,
        HashSet<string> seenSentenceTexts)
    {
        var errors = new List<string>();

        var text = item.Text?.Trim() ?? string.Empty;
        var translation = item.Translation?.Trim() ?? string.Empty;
        var sceneCode = NormalizeCode(item.SceneCode);
        var sceneName = item.SceneName?.Trim() ?? string.Empty;
        var status = (item.Status ?? defaultStatus).Trim().ToLowerInvariant();

        if (string.IsNullOrWhiteSpace(text))
        {
            errors.Add("Sentence text is required.");
        }

        if (string.IsNullOrWhiteSpace(translation))
        {
            errors.Add("Sentence translation is required.");
        }

        if (string.IsNullOrWhiteSpace(sceneCode) || string.IsNullOrWhiteSpace(sceneName))
        {
            errors.Add("Scene code and scene name are required.");
        }

        if (item.Keywords is null || item.Keywords.Count == 0)
        {
            errors.Add("At least one keyword is required.");
        }

        if (!IsValidStatus(status))
        {
            errors.Add("Sentence status must be draft, published, or offline.");
        }

        if (!string.IsNullOrWhiteSpace(text) && !seenSentenceTexts.Add(text))
        {
            errors.Add("Duplicate sentence text in import file.");
        }

        if (item.Keywords is not null)
        {
            foreach (var keyword in item.Keywords)
            {
                if (keyword is null)
                {
                    errors.Add("Keyword row is empty.");
                    continue;
                }

                var lemma = NormalizeWord(keyword.Lemma);
                var meaning = keyword.MeaningCn?.Trim() ?? string.Empty;
                var surfaceText = keyword.SurfaceText?.Trim() ?? string.Empty;

                if (string.IsNullOrWhiteSpace(lemma) || string.IsNullOrWhiteSpace(meaning))
                {
                    errors.Add($"Keyword '{keyword.SurfaceText}' requires lemma and Chinese meaning.");
                }

                if (string.IsNullOrWhiteSpace(surfaceText))
                {
                    errors.Add("Keyword surface text is required.");
                }

                if (!string.IsNullOrWhiteSpace(text) &&
                    !string.IsNullOrWhiteSpace(surfaceText) &&
                    !text.Contains(surfaceText, StringComparison.OrdinalIgnoreCase))
                {
                    errors.Add($"Keyword '{surfaceText}' does not appear in the sentence.");
                }
            }
        }

        return errors;
    }

    private (Scene Scene, bool Created) GetOrCreateImportScene(
        ImportSentenceItemRequest item,
        string sceneCode,
        IDictionary<string, Scene> sceneCache,
        DateTimeOffset now)
    {
        if (sceneCache.TryGetValue(sceneCode, out var scene))
        {
            scene.Name = item.SceneName.Trim();
            scene.Description = TrimToNull(item.SceneDescription);
            scene.IsEnabled = true;
            scene.UpdatedAt = now;
            return (scene, false);
        }

        scene = new Scene
        {
            Code = sceneCode,
            Name = item.SceneName.Trim(),
            Description = TrimToNull(item.SceneDescription),
            IsEnabled = true,
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.Scenes.Add(scene);
        sceneCache[sceneCode] = scene;
        return (scene, true);
    }

    private (Word Word, bool Created) GetOrCreateImportWord(
        ImportSentenceKeywordRequest keyword,
        IDictionary<string, Word> wordCache,
        DateTimeOffset now)
    {
        var lemma = NormalizeWord(keyword.Lemma);
        if (wordCache.TryGetValue(lemma, out var word))
        {
            word.MeaningCn = keyword.MeaningCn.Trim();
            word.Phonetic = TrimToNull(keyword.Phonetic);
            word.PartOfSpeech = TrimToNull(keyword.PartOfSpeech);
            word.CefrLevel = TrimToNull(keyword.CefrLevel);
            word.ExamTags = TrimToNull(keyword.ExamTags);
            word.Collocations = TrimToNull(keyword.Collocations);
            word.UpdatedAt = now;
            return (word, false);
        }

        word = new Word
        {
            Lemma = lemma,
            Phonetic = TrimToNull(keyword.Phonetic),
            PartOfSpeech = TrimToNull(keyword.PartOfSpeech),
            MeaningCn = keyword.MeaningCn.Trim(),
            CefrLevel = TrimToNull(keyword.CefrLevel),
            ExamTags = TrimToNull(keyword.ExamTags),
            Collocations = TrimToNull(keyword.Collocations),
            CreatedAt = now,
            UpdatedAt = now
        };

        dbContext.Words.Add(word);
        wordCache[lemma] = word;
        return (word, true);
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
        return DictationMode.NormalizeOrDefault(value);
    }

    private static string NormalizeStatus(string value)
    {
        var normalized = value.Trim().ToLowerInvariant();
        return normalized is "draft" or "published" or "offline"
            ? normalized
            : "draft";
    }

    private static bool IsValidStatus(string value)
    {
        return value is "draft" or "published" or "offline";
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
