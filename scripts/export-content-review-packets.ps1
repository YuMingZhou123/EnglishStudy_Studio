param(
    [string]$ReviewPath = "",
    [string]$OutputDirectory = "",
    [int]$BatchSize = 20
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($ReviewPath)) {
    $ReviewPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot "..\content\review-packets"
}

if ($BatchSize -lt 1) {
    throw "BatchSize must be greater than 0."
}

$ReviewPath = [System.IO.Path]::GetFullPath($ReviewPath)
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$ContentReviewHtmlPath = Join-Path $RepoRoot "content\mvp-content-review.html"

if (-not (Test-Path -LiteralPath $ReviewPath)) {
    throw "Review file not found: $ReviewPath. Run .\scripts\export-content-review-sheet.ps1 first."
}

function ConvertTo-MarkdownText($value) {
    $text = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Replace("\", "\\").Replace("|", "\|").Replace("`r`n", "<br>").Replace("`n", "<br>")
}

function Get-Status($value) {
    return ([string]$value).Trim().ToLowerInvariant()
}

function Get-WordCount([string]$text) {
    return [regex]::Matches($text, "[A-Za-z]+(?:'[A-Za-z]+)?").Count
}

function Get-FieldValue($row, [string]$fieldName) {
    if ($null -eq $row) {
        return ""
    }

    $property = $row.PSObject.Properties[$fieldName]
    if ($null -eq $property) {
        return ""
    }

    return [string]$property.Value
}

function Get-MarkdownLink([string]$label, [string]$path) {
    $uri = ([System.Uri][System.IO.Path]::GetFullPath($path)).AbsoluteUri
    return "[$label]($uri)"
}

function ConvertTo-FileUriWithQuery([string]$path, [hashtable]$Query = @{}) {
    $uri = ([System.Uri][System.IO.Path]::GetFullPath($path)).AbsoluteUri
    if ($Query.Count -eq 0) {
        return $uri
    }

    $pairs = foreach ($key in ($Query.Keys | Sort-Object)) {
        $escapedKey = [System.Uri]::EscapeDataString([string]$key)
        $escapedValue = [System.Uri]::EscapeDataString([string]$Query[$key])
        "$escapedKey=$escapedValue"
    }

    return "${uri}?$($pairs -join '&')"
}

$rows = @(Import-Csv -LiteralPath $ReviewPath -Encoding UTF8)
if ($rows.Count -eq 0) {
    throw "Review CSV has no rows: $ReviewPath"
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$packetFiles = New-Object System.Collections.Generic.List[object]
$batchCount = [math]::Ceiling($rows.Count / $BatchSize)

for ($index = 0; $index -lt $batchCount; $index++) {
    $start = ($index * $BatchSize) + 1
    $end = [math]::Min(($index + 1) * $BatchSize, $rows.Count)
    $batchRows = @($rows | Where-Object {
        $rowNumber = 0
        [int]::TryParse([string]$_.RowNumber, [ref]$rowNumber) -and
            $rowNumber -ge $start -and
            $rowNumber -le $end
    })

    $passRows = @($batchRows | Where-Object { (Get-Status $_.ReviewStatus) -eq "pass" })
    $fixRows = @($batchRows | Where-Object {
        $status = Get-Status $_.ReviewStatus
        $status.StartsWith("fix_") -or $status -eq "remove"
    })
    $blankRows = @($batchRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ReviewStatus) })
    $fileName = "content-review-batch-{0:D3}-{1:D3}.md" -f $start, $end
    $outputPath = Join-Path $OutputDirectory $fileName
    $reviewDeskUri = ConvertTo-FileUriWithQuery $ContentReviewHtmlPath @{ batch = "$start-$end"; status = "blank" }

    $lines = @(
        "# Content Review Batch $start-$end",
        "",
        "Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "",
        ('Source CSV: `' + $ReviewPath + '`'),
        "",
        "## Reviewer Instructions",
        "",
        "- Open the review desk for actual audio playback: [Rows $start-$end]($reviewDeskUri).",
        "- Review sentence text, translation, target keywords, and obvious audio concerns.",
        '- Use one status per row: `pass`, `fix_sentence`, `fix_translation`, `fix_keyword`, `fix_audio`, or `remove`.',
        '- Set `Audio reviewed` to `yes` only after listening to the row in the review desk.',
        '- Leave a note whenever the status is not `pass`.',
        '- Edit only the `Status`, `Audio reviewed`, and `Notes` columns, then run `.\scripts\import-content-review-packets.ps1 -ValidateOnly` before importing.',
        "",
        "## Batch Summary",
        "",
        "- Total: $($batchRows.Count)",
        "- Pass: $($passRows.Count)",
        "- Fix/remove: $($fixRows.Count)",
        "- Blank: $($blankRows.Count)",
        "",
        "## Rows",
        "",
        "| Row | Scene | Level | Words | Keywords | Status | Audio reviewed | Sentence | Translation | Target keywords | Notes |",
        "| ---: | --- | --- | ---: | ---: | --- | --- | --- | --- | --- | --- |"
    )

    foreach ($row in $batchRows) {
        $notes = @(
            [string]$row.SentenceNotes,
            [string]$row.TranslationNotes,
            [string]$row.KeywordNotes,
            [string]$row.AudioNotes,
            [string]$row.FinalNotes
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

        $wordCount = Get-WordCount $row.Text
        $lines += "| $($row.RowNumber) | $(ConvertTo-MarkdownText $row.SceneCode) | $(ConvertTo-MarkdownText $row.Level) | $wordCount | $($row.KeywordCount) | $(ConvertTo-MarkdownText $row.ReviewStatus) | $(ConvertTo-MarkdownText (Get-FieldValue $row 'AudioReviewed')) | $(ConvertTo-MarkdownText $row.Text) | $(ConvertTo-MarkdownText $row.Translation) | $(ConvertTo-MarkdownText $row.Keywords) | $(ConvertTo-MarkdownText ($notes -join '; ')) |"
    }

    Set-Content -LiteralPath $outputPath -Value ($lines -join "`r`n") -Encoding UTF8

    $packetFiles.Add([pscustomobject]@{
        batch = "$start-$end"
        outputPath = $outputPath
        totalRows = $batchRows.Count
        passRows = $passRows.Count
        fixRows = $fixRows.Count
        blankRows = $blankRows.Count
    })
}

$indexPath = Join-Path $OutputDirectory "index.md"
$indexLines = @(
    "# Content Review Packets",
    "",
    "Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "",
    'Use these packets to split the MVP content review across reviewers. The canonical editable review desk remains `content/mvp-content-review.html`.',
    "",
    "| Batch | Pass | Fix/remove | Blank | File |",
    "| --- | ---: | ---: | ---: | --- |"
) + @($packetFiles | ForEach-Object {
    "| $($_.batch) | $($_.passRows) | $($_.fixRows) | $($_.blankRows) | $(Get-MarkdownLink 'Open' $_.outputPath) |"
})

Set-Content -LiteralPath $indexPath -Value ($indexLines -join "`r`n") -Encoding UTF8

[pscustomobject]@{
    outputDirectory = $OutputDirectory
    indexPath = $indexPath
    batchSize = $BatchSize
    packetCount = $packetFiles.Count
    packets = $packetFiles
} | ConvertTo-Json -Depth 6
