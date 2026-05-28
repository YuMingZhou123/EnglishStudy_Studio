param(
    [string]$ContentPath = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($ContentPath)) {
    $ContentPath = Join-Path $PSScriptRoot "..\content\mvp-sentence-pack.json"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.csv"
}

$ContentPath = [System.IO.Path]::GetFullPath($ContentPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $ContentPath)) {
    throw "Content file not found: $ContentPath"
}

$json = Get-Content -LiteralPath $ContentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($json.items)

$rows = for ($index = 0; $index -lt $items.Count; $index++) {
    $item = $items[$index]
    $keywords = @($item.keywords) | ForEach-Object {
        "$($_.lemma) [$($_.surfaceText)] - $($_.meaningCn)"
    }

    [pscustomobject]@{
        RowNumber = $index + 1
        SceneCode = $item.sceneCode
        SceneName = $item.sceneName
        Level = $item.level
        Text = $item.text
        Translation = $item.translation
        KeywordCount = @($item.keywords).Count
        Keywords = $keywords -join "; "
        ReviewStatus = ""
        SentenceNotes = ""
        TranslationNotes = ""
        KeywordNotes = ""
        AudioNotes = ""
        FinalNotes = ""
    }
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    rows = $rows.Count
} | ConvertTo-Json -Depth 3
