param(
    [string]$ApiBaseUrl = "http://localhost:5180",
    [string]$WebBaseUrl = "http://localhost:3000",
    [string]$LearnerEmail = "learner@example.com",
    [string]$LearnerPassword = 'Pass123$',
    [string]$AdminEmail = "admin@example.com",
    [string]$AdminPassword = 'Admin123$',
    [switch]$SkipWeb,
    [switch]$IncludeTts
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Add-Type -AssemblyName System.Net.Http

function ConvertTo-JsonBody($value) {
    return $value | ConvertTo-Json -Depth 20 -Compress
}

function New-AuthHeaders([string]$token) {
    return @{ Authorization = "Bearer $token" }
}

function Assert-Condition([bool]$condition, [string]$message) {
    if (-not $condition) {
        throw $message
    }
}

Write-Host "Checking API health..."
$health = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/health"
$ready = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/health/ready"
$swagger = Invoke-WebRequest -Method Get -Uri "$ApiBaseUrl/swagger/index.html" -UseBasicParsing
Assert-Condition ($health.status -eq "Healthy") "API health check failed."
Assert-Condition ($ready.status -eq "Healthy") "API readiness check failed."
Assert-Condition ($swagger.StatusCode -eq 200) "Swagger UI did not return HTTP 200."

if (-not $SkipWeb) {
    Write-Host "Checking Web app..."
    $web = Invoke-WebRequest -Method Get -Uri $WebBaseUrl -UseBasicParsing
    Assert-Condition ($web.StatusCode -eq 200) "Web app did not return HTTP 200."
}

Write-Host "Logging in demo users..."
$learnerAuth = Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/auth/login" `
    -ContentType "application/json" `
    -Body (ConvertTo-JsonBody @{ email = $LearnerEmail; password = $LearnerPassword })
$learnerToken = $learnerAuth.accessToken
Assert-Condition (-not [string]::IsNullOrWhiteSpace($learnerToken)) "Learner login did not return a token."

$adminAuth = Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/auth/login" `
    -ContentType "application/json" `
    -Body (ConvertTo-JsonBody @{ email = $AdminEmail; password = $AdminPassword })
$adminToken = $adminAuth.accessToken
Assert-Condition (-not [string]::IsNullOrWhiteSpace($adminToken)) "Admin login did not return a token."

Write-Host "Running dictation modes..."
$modeResults = @()
foreach ($mode in @("beginner", "intermediate", "advanced")) {
    $question = Invoke-RestMethod `
        -Method Get `
        -Uri "$ApiBaseUrl/api/dictation/next?mode=$mode" `
        -Headers (New-AuthHeaders $learnerToken)

    if ($mode -eq "advanced") {
        $submitBody = @{
            sentenceId = $question.sentenceId
            mode = $mode
            answers = @()
            userAnswer = $question.speechText
            durationMs = 1200
            replayCount = 1
            hintCount = 0
            reviewWordId = $null
        }
    }
    else {
        $answers = @($question.targetWords | ForEach-Object {
            @{ blankId = $_.blankId; value = $_.surfaceText }
        })
        Assert-Condition ($answers.Count -gt 0) "No target words returned for $mode question."

        $submitBody = @{
            sentenceId = $question.sentenceId
            mode = $mode
            answers = $answers
            userAnswer = $null
            durationMs = 1200
            replayCount = 1
            hintCount = 0
            reviewWordId = $null
        }
    }

    $submit = Invoke-RestMethod `
        -Method Post `
        -Uri "$ApiBaseUrl/api/dictation/submit" `
        -Headers (New-AuthHeaders $learnerToken) `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody $submitBody)

    Assert-Condition ($submit.score -eq 100) "$mode dictation did not score 100 with the expected answer."
    $modeResults += [pscustomobject]@{
        mode = $mode
        sentence = $question.speechText
        score = $submit.score
        isCorrect = $submit.isCorrect
    }
}

Write-Host "Checking wrong-word review and learning report..."
$wrongQuestion = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/dictation/next?mode=beginner" `
    -Headers (New-AuthHeaders $learnerToken)
$wrongAnswers = @($wrongQuestion.targetWords | ForEach-Object {
    @{ blankId = $_.blankId; value = "__wrong__" }
})

$wrongSubmit = Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/dictation/submit" `
    -Headers (New-AuthHeaders $learnerToken) `
    -ContentType "application/json" `
    -Body (ConvertTo-JsonBody @{
        sentenceId = $wrongQuestion.sentenceId
        mode = "beginner"
        answers = $wrongAnswers
        userAnswer = $null
        durationMs = 900
        replayCount = 1
        hintCount = 0
        reviewWordId = $null
    })
Assert-Condition ($wrongSubmit.score -lt 100) "Wrong answer unexpectedly scored as correct."

$vocabularyWords = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/vocabulary/words" `
    -Headers (New-AuthHeaders $learnerToken)
Assert-Condition (@($vocabularyWords).Count -gt 0) "Vocabulary book is empty after wrong answer."

$reviewQuestion = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/vocabulary/review/next?mode=beginner" `
    -Headers (New-AuthHeaders $learnerToken)
Assert-Condition (-not [string]::IsNullOrWhiteSpace($reviewQuestion.speechText)) "Wrong-word review did not return a question."

$summary = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/dictation/summary" `
    -Headers (New-AuthHeaders $learnerToken)
$history = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/dictation/history?limit=5" `
    -Headers (New-AuthHeaders $learnerToken)
Assert-Condition ($summary.todayAttemptCount -gt 0) "Learning summary did not include today's attempts."
Assert-Condition (@($history).Count -gt 0) "Dictation history is empty."

Write-Host "Checking admin content and media flows..."
$scenes = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/admin/scenes" `
    -Headers (New-AuthHeaders $adminToken)
$adminWords = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/admin/words" `
    -Headers (New-AuthHeaders $adminToken)
$sentences = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/admin/sentences" `
    -Headers (New-AuthHeaders $adminToken)
Assert-Condition (@($scenes).Count -gt 0) "Admin scenes list is empty."
Assert-Condition (@($adminWords).Count -gt 0) "Admin words list is empty."
Assert-Condition (@($sentences).Count -gt 0) "Admin sentences list is empty."

$smokeSceneCode = "smoke-test"
$scene = $scenes | Where-Object { $_.code -eq $smokeSceneCode } | Select-Object -First 1
if ($null -eq $scene) {
    $scene = Invoke-RestMethod `
        -Method Post `
        -Uri "$ApiBaseUrl/api/admin/scenes" `
        -Headers (New-AuthHeaders $adminToken) `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody @{
            code = $smokeSceneCode
            name = "Smoke Test"
            description = "Reusable smoke test scene"
            isEnabled = $true
        })
}
elseif (-not $scene.isEnabled) {
    $scene = Invoke-RestMethod `
        -Method Put `
        -Uri "$ApiBaseUrl/api/admin/scenes/$($scene.id)" `
        -Headers (New-AuthHeaders $adminToken) `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody @{
            code = $smokeSceneCode
            name = $scene.name
            description = $scene.description
            isEnabled = $true
        })
}

$wordLemma = "smokeword"
$smokeWords = Invoke-RestMethod `
    -Method Get `
    -Uri "$ApiBaseUrl/api/admin/words?keyword=$wordLemma" `
    -Headers (New-AuthHeaders $adminToken)
$word = $smokeWords | Where-Object { $_.lemma -eq $wordLemma } | Select-Object -First 1
if ($null -eq $word) {
    $word = Invoke-RestMethod `
        -Method Post `
        -Uri "$ApiBaseUrl/api/admin/words" `
        -Headers (New-AuthHeaders $adminToken) `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody @{
            lemma = $wordLemma
            phonetic = "/smok/"
            partOfSpeech = "noun"
            meaningCn = "smoke test word"
            cefrLevel = "A1"
            examTags = "smoke"
            collocations = "smoke test"
        })
}

$sentenceText = "Please remember $wordLemma during practice."
$sentence = $sentences | Where-Object { $_.text -eq $sentenceText } | Select-Object -First 1
$existingAudioAssetId = if ($null -ne $sentence -and -not [string]::IsNullOrWhiteSpace($sentence.audioAssetId)) {
    $sentence.audioAssetId
}
else {
    $null
}
$existingAudioUrl = if ($null -ne $sentence -and -not [string]::IsNullOrWhiteSpace($sentence.audioUrl)) {
    $sentence.audioUrl
}
else {
    ""
}
$sentencePayload = @{
    text = $sentenceText
    translation = "Remember this smoke test word during practice."
    level = "beginner"
    sceneId = $scene.id
    audioAssetId = $existingAudioAssetId
    audioUrl = $existingAudioUrl
    status = "draft"
    keywords = @(@{
        wordId = $word.id
        surfaceText = $wordLemma
        priority = 100
        blankGroup = $null
    })
}
if ($null -eq $sentence) {
    $sentence = Invoke-RestMethod `
        -Method Post `
        -Uri "$ApiBaseUrl/api/admin/sentences" `
        -Headers (New-AuthHeaders $adminToken) `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody $sentencePayload)
}
else {
    $sentence = Invoke-RestMethod `
        -Method Put `
        -Uri "$ApiBaseUrl/api/admin/sentences/$($sentence.id)" `
        -Headers (New-AuthHeaders $adminToken) `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody $sentencePayload)
}

$published = Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/admin/sentences/$($sentence.id)/publish" `
    -Headers (New-AuthHeaders $adminToken)
$offline = Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/admin/sentences/$($sentence.id)/offline" `
    -Headers (New-AuthHeaders $adminToken)
Assert-Condition ($published.status -eq "published") "Publishing sentence failed."
Assert-Condition ($offline.status -eq "offline") "Taking sentence offline failed."

$ttsMediaStatus = "Skipped"
if ($IncludeTts) {
    Write-Host "Checking TTS media..."
    if ([string]::IsNullOrWhiteSpace($offline.audioUrl) -or [string]::IsNullOrWhiteSpace($offline.audioAssetId)) {
        $ttsSentence = Invoke-RestMethod `
            -Method Post `
            -Uri "$ApiBaseUrl/api/admin/sentences/$($sentence.id)/generate-audio" `
            -Headers (New-AuthHeaders $adminToken) `
            -ContentType "application/json" `
            -Body (ConvertTo-JsonBody @{
                voice = "en-US"
                speed = 1
            })
    }
    else {
        $ttsSentence = $offline
    }

    Assert-Condition (-not [string]::IsNullOrWhiteSpace($ttsSentence.audioUrl)) "TTS generation did not bind an audio URL."
    Assert-Condition (-not [string]::IsNullOrWhiteSpace($ttsSentence.audioAssetId)) "TTS generation did not bind an audio asset."

    $ttsMedia = Invoke-WebRequest `
        -Method Get `
        -Uri $ttsSentence.audioUrl `
        -UseBasicParsing
    Assert-Condition ($ttsMedia.StatusCode -eq 200) "Generated TTS media could not be read back."
    $ttsMediaStatus = "Healthy"
}

$client = [System.Net.Http.HttpClient]::new()
$client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $adminToken)
$multipart = [System.Net.Http.MultipartFormDataContent]::new()
$fileBytes = [System.Text.Encoding]::UTF8.GetBytes("smoke audio placeholder")
$fileContent = [System.Net.Http.ByteArrayContent]::new($fileBytes)
$fileContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse("audio/mpeg")
$mediaSuffix = "$(Get-Date -Format 'yyyyMMddHHmmss')$(([guid]::NewGuid().ToString('N')).Substring(0, 8))"
$multipart.Add($fileContent, "file", "smoke-$mediaSuffix.mp3")
$multipart.Add([System.Net.Http.StringContent]::new("audio/smoke"), "folder")
$uploadResponse = $client.PostAsync("$ApiBaseUrl/api/admin/media/upload", $multipart).GetAwaiter().GetResult()
$uploadText = $uploadResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
if (-not $uploadResponse.IsSuccessStatusCode) {
    throw "Media upload failed: $uploadText"
}

$media = $uploadText | ConvertFrom-Json
$mediaResponse = Invoke-WebRequest `
    -Method Get `
    -Uri "$ApiBaseUrl/api/media/objects/$($media.objectKey)" `
    -UseBasicParsing
Assert-Condition ($mediaResponse.StatusCode -eq 200) "Uploaded media could not be read back."

$result = [pscustomobject]@{
    api = $health.status
    ready = $ready.status
    swagger = "Healthy"
    web = if ($SkipWeb) { "Skipped" } else { "Healthy" }
    learner = $learnerAuth.user.email
    modes = $modeResults
    wrongScore = $wrongSubmit.score
    vocabularyCount = @($vocabularyWords).Count
    reviewSentence = $reviewQuestion.speechText
    todayAttempts = $summary.todayAttemptCount
    recentHistory = @($history).Count
    adminCounts = [pscustomobject]@{
        scenes = @($scenes).Count
        words = @($adminWords).Count
        sentences = @($sentences).Count
    }
    createdSentenceStatusAfterPublish = $published.status
    createdSentenceStatusAfterOffline = $offline.status
    tts = $ttsMediaStatus
    uploadedObjectKey = $media.objectKey
    mediaGetStatus = $mediaResponse.StatusCode
}

Write-Host "Smoke test passed."
$result | ConvertTo-Json -Depth 8
