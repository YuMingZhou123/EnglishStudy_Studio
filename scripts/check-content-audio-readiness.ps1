param(
    [string]$ApiBaseUrl = "http://localhost:5180",
    [string]$AdminEmail = "admin@example.com",
    [string]$AdminPassword = 'Admin123$',
    [string]$Status = "published",
    [string]$OutputPath = "",
    [switch]$SkipReadback,
    [switch]$AssertReady
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Add-Type -AssemblyName System.Net.Http

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\content-audio-readiness.md"
}

$ApiBaseUrl = $ApiBaseUrl.TrimEnd("/")
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

function ConvertTo-JsonBody($value) {
    return $value | ConvertTo-Json -Depth 20 -Compress
}

function ConvertTo-MarkdownText($value) {
    $text = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Replace("\", "\\").Replace("|", "\|").Replace("`r`n", "<br>").Replace("`n", "<br>")
}

function Resolve-AudioUrl([string]$AudioUrl) {
    $value = ([string]$AudioUrl).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ""
    }

    $uri = $null
    if ([System.Uri]::TryCreate($value, [System.UriKind]::Absolute, [ref]$uri)) {
        return $value
    }

    if ($value.StartsWith("/")) {
        return "$ApiBaseUrl$value"
    }

    return "$ApiBaseUrl/$value"
}

function Test-AudioReadback([string]$Url) {
    $request = $null
    $response = $null

    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(
            [System.Net.Http.HttpMethod]::Get,
            $Url)
        $request.Headers.Range = [System.Net.Http.Headers.RangeHeaderValue]::new(0, 0)

        $sendTask = $script:AudioHttpClient.SendAsync(
            $request,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        $response = $sendTask.GetAwaiter().GetResult()

        $statusCode = [int]$response.StatusCode
        $contentType = if ($null -ne $response.Content.Headers.ContentType) {
            [string]$response.Content.Headers.ContentType
        }
        else {
            ""
        }
        $contentLength = if ($null -ne $response.Content.Headers.ContentLength) {
            [string]$response.Content.Headers.ContentLength
        }
        else {
            ""
        }

        return [pscustomobject]@{
            readable = $statusCode -eq 200 -or $statusCode -eq 206
            statusCode = $statusCode
            contentType = $contentType
            contentLength = $contentLength
            error = ""
        }
    }
    catch {
        $statusCode = $null
        $exceptionResponse = $null
        $responseProperty = $_.Exception.PSObject.Properties["Response"]
        if ($null -ne $responseProperty) {
            $exceptionResponse = $responseProperty.Value
        }

        if ($null -ne $exceptionResponse) {
            try {
                $statusCode = [int]$exceptionResponse.StatusCode
            }
            catch {
                $statusCode = $null
            }
        }

        return [pscustomobject]@{
            readable = $false
            statusCode = $statusCode
            contentType = ""
            contentLength = ""
            error = $_.Exception.Message
        }
    }
    finally {
        if ($null -ne $response) {
            $response.Dispose()
        }

        if ($null -ne $request) {
            $request.Dispose()
        }
    }
}

function New-ProblemRow {
    param(
        [int]$RowNumber,
        $Sentence,
        [string]$State,
        [string]$Readback,
        [string]$Message
    )

    [pscustomobject]@{
        rowNumber = $RowNumber
        sentenceId = [string]$Sentence.id
        level = [string]$Sentence.level
        sceneName = [string]$Sentence.sceneName
        state = $State
        readback = $Readback
        message = $Message
        text = [string]$Sentence.text
        audioUrl = [string]$Sentence.audioUrl
        audioAssetId = [string]$Sentence.audioAssetId
    }
}

$apiReachable = $false
$adminAuthenticated = $false
$sentencesFetched = $false
$serviceError = ""
$token = ""
$sentences = @()

try {
    $health = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/health" -TimeoutSec 5
    $apiReachable = $true
    if ($null -ne $health.PSObject.Properties["status"] -and $health.status -ne "Healthy") {
        $serviceError = "API health returned status '$($health.status)'."
    }
}
catch {
    $serviceError = "API health check failed: $($_.Exception.Message)"
}

if ($apiReachable -and [string]::IsNullOrWhiteSpace($serviceError)) {
    try {
        $auth = Invoke-RestMethod `
            -Method Post `
            -Uri "$ApiBaseUrl/api/auth/login" `
            -ContentType "application/json" `
            -TimeoutSec 10 `
            -Body (ConvertTo-JsonBody @{ email = $AdminEmail; password = $AdminPassword })

        $token = [string]$auth.accessToken
        $adminAuthenticated = -not [string]::IsNullOrWhiteSpace($token)
        if (-not $adminAuthenticated) {
            $serviceError = "Admin login did not return an access token."
        }
    }
    catch {
        $serviceError = "Admin login failed: $($_.Exception.Message)"
    }
}

if ($apiReachable -and $adminAuthenticated -and [string]::IsNullOrWhiteSpace($serviceError)) {
    try {
        $encodedStatus = [System.Uri]::EscapeDataString($Status)
        $sentenceResponse = Invoke-RestMethod `
                -Method Get `
                -Uri "$ApiBaseUrl/api/admin/sentences?status=$encodedStatus" `
                -Headers @{ Authorization = "Bearer $token" } `
                -TimeoutSec 20
        $sentences = @($sentenceResponse)
        $sentencesFetched = $true
    }
    catch {
        $serviceError = "Published sentence query failed: $($_.Exception.Message)"
    }
}

$rows = New-Object System.Collections.Generic.List[object]
$checkedAudioRows = 0
$script:AudioHttpClient = [System.Net.Http.HttpClient]::new()
$script:AudioHttpClient.Timeout = [TimeSpan]::FromSeconds(10)

for ($index = 0; $index -lt $sentences.Count; $index++) {
    $sentence = $sentences[$index]
    $rowNumber = $index + 1
    $audioUrl = ([string]$sentence.audioUrl).Trim()
    $audioAssetId = ([string]$sentence.audioAssetId).Trim()
    $hasAudioUrl = -not [string]::IsNullOrWhiteSpace($audioUrl)
    $hasAudioAsset = -not [string]::IsNullOrWhiteSpace($audioAssetId)

    if (-not $hasAudioUrl -and -not $hasAudioAsset) {
        $rows.Add((New-ProblemRow $rowNumber $sentence "missing" "not_checked" "Sentence has no audioUrl and no audioAssetId."))
        continue
    }

    if (-not $hasAudioUrl) {
        $rows.Add((New-ProblemRow $rowNumber $sentence "no_url" "not_checked" "Sentence has an audio asset id but no readable audioUrl."))
        continue
    }

    if ($SkipReadback) {
        continue
    }

    $checkedAudioRows += 1
    $resolvedUrl = Resolve-AudioUrl $audioUrl
    $readback = Test-AudioReadback $resolvedUrl
    if (-not [bool]$readback.readable) {
        $statusText = if ($null -eq $readback.statusCode) { "no status" } else { "HTTP $($readback.statusCode)" }
        $message = if ([string]::IsNullOrWhiteSpace([string]$readback.error)) {
            "Audio URL returned $statusText."
        }
        else {
            "Audio readback failed: $($readback.error)"
        }

        $rows.Add((New-ProblemRow $rowNumber $sentence "unreadable" $statusText $message))
    }
}

$script:AudioHttpClient.Dispose()

$problemRows = @($rows.ToArray())
$missingAudioRows = @($problemRows | Where-Object { $_.state -eq "missing" })
$noUrlRows = @($problemRows | Where-Object { $_.state -eq "no_url" })
$unreadableAudioRows = @($problemRows | Where-Object { $_.state -eq "unreadable" })
$boundAudioRows = @($sentences | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.audioUrl) -or
        -not [string]::IsNullOrWhiteSpace([string]$_.audioAssetId)
    })
$externalAudioRows = @($sentences | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.audioUrl) -and
        [string]::IsNullOrWhiteSpace([string]$_.audioAssetId)
    })
$ready =
    $apiReachable -and
    $adminAuthenticated -and
    $sentencesFetched -and
    $sentences.Count -gt 0 -and
    $missingAudioRows.Count -eq 0 -and
    $noUrlRows.Count -eq 0 -and
    $unreadableAudioRows.Count -eq 0

$summaryLines = @(
    "| Metric | Value |",
    "| --- | ---: |",
    "| API reachable | $apiReachable |",
    "| Admin authenticated | $adminAuthenticated |",
    "| Sentences fetched | $sentencesFetched |",
    "| Published rows checked | $($sentences.Count) |",
    "| Bound audio rows | $($boundAudioRows.Count) |",
    "| External URL rows | $($externalAudioRows.Count) |",
    "| Readback checked rows | $checkedAudioRows |",
    "| Missing audio rows | $($missingAudioRows.Count) |",
    "| Audio asset without URL rows | $($noUrlRows.Count) |",
    "| Unreadable audio rows | $($unreadableAudioRows.Count) |"
)

$problemLines = if ($problemRows.Count -eq 0) {
    @("- No audio technical problems found. Human listening review is still required.")
}
else {
    @(
        "| Row | State | Readback | Level | Scene | Message | Sentence |",
        "| ---: | --- | --- | --- | --- | --- | --- |"
    ) + @($problemRows | Select-Object -First 120 | ForEach-Object {
        "| $($_.rowNumber) | $(ConvertTo-MarkdownText $_.state) | $(ConvertTo-MarkdownText $_.readback) | $(ConvertTo-MarkdownText $_.level) | $(ConvertTo-MarkdownText $_.sceneName) | $(ConvertTo-MarkdownText $_.message) | $(ConvertTo-MarkdownText $_.text) |"
    })
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# Content Audio Readiness",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- Audio technical readiness: $ready",
    "- Human listening review required: True",
    "- API base URL: $ApiBaseUrl",
    "- Sentence status: $Status",
    "- Readback skipped: $([bool]$SkipReadback)",
    "- Service error: $(ConvertTo-MarkdownText $serviceError)",
    "",
    "## Summary",
    ""
) + $summaryLines + @(
    "",
    "## Problem Rows",
    ""
) + $problemLines + @(
    "",
    "## Reviewer Note",
    "",
    '- This report only checks whether published sentences have bound audio and whether the audio URL can be read.',
    '- It does not judge pronunciation quality, speech speed, voice choice, clipping, noise, or whether the audio matches the sentence.',
    '- Do not mark a row as `pass` until the human content review includes the actual audio experience.'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

$result = [pscustomobject]@{
    outputPath = $OutputPath
    apiReachable = $apiReachable
    adminAuthenticated = $adminAuthenticated
    sentencesFetched = $sentencesFetched
    status = $Status
    totalPublished = $sentences.Count
    boundAudioRows = $boundAudioRows.Count
    externalAudioRows = $externalAudioRows.Count
    checkedAudioRows = $checkedAudioRows
    missingAudioRows = $missingAudioRows.Count
    noUrlRows = $noUrlRows.Count
    unreadableAudioRows = $unreadableAudioRows.Count
    problemRows = $problemRows.Count
    ready = $ready
    humanListeningReviewRequired = $true
    serviceError = $serviceError
}

if ($AssertReady -and -not $ready) {
    $result | ConvertTo-Json -Depth 8
    throw "Content audio technical readiness failed."
}

$result | ConvertTo-Json -Depth 8
