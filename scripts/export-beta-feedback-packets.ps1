param(
    [string]$FeedbackPath = "",
    [string]$OutputDirectory = "",
    [int]$UserCount = 10
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($FeedbackPath)) {
    $FeedbackPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $PSScriptRoot "..\feedback\beta-feedback-packets"
}

if ($UserCount -lt 1) {
    throw "UserCount must be greater than 0."
}

$FeedbackPath = [System.IO.Path]::GetFullPath($FeedbackPath)
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

function ConvertTo-MarkdownText($value) {
    $text = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Replace("\", "\\").Replace("|", "\|").Replace("`r`n", "<br>").Replace("`n", "<br>")
}

function Get-MarkdownLink([string]$label, [string]$path) {
    $uri = ([System.Uri][System.IO.Path]::GetFullPath($path)).AbsoluteUri
    return "[$label]($uri)"
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

function Test-Filled($row) {
    return -not [string]::IsNullOrWhiteSpace([string]$row.CompletedTest) -or
        -not [string]::IsNullOrWhiteSpace([string]$row.IndependentCompletion) -or
        -not [string]::IsNullOrWhiteSpace([string]$row.Notes)
}

$fields = @(
    "UserId",
    "UserType",
    "EnglishLevel",
    "CompletedTest",
    "IndependentCompletion",
    "StuckStep",
    "UnderstandsDifficulty",
    "WillingNext",
    "PerceivedUseful",
    "AudioIssue",
    "PageIssue",
    "ContentIssue",
    "Priority",
    "Notes"
)

$sourceRows = @()
if (Test-Path -LiteralPath $FeedbackPath) {
    $sourceRows = @(Import-Csv -LiteralPath $FeedbackPath -Encoding UTF8)
}

if ($sourceRows.Count -eq 0) {
    $sourceRows = for ($index = 1; $index -le $UserCount; $index++) {
        [pscustomobject]@{ UserId = "U{0:D2}" -f $index }
    }
}

$rows = @(for ($index = 0; $index -lt $sourceRows.Count; $index++) {
    $sourceRow = $sourceRows[$index]
    $row = [ordered]@{}
    foreach ($field in $fields) {
        $row[$field] = Get-FieldValue $sourceRow $field
    }

    if ([string]::IsNullOrWhiteSpace($row["UserId"])) {
        $row["UserId"] = "U{0:D2}" -f ($index + 1)
    }

    [pscustomobject]$row
})

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
}

$packetFiles = New-Object System.Collections.Generic.List[object]
foreach ($row in $rows) {
    $userId = [string]$row.UserId
    $safeUserId = ($userId -replace "[^A-Za-z0-9_-]", "-")
    $outputPath = Join-Path $OutputDirectory ("beta-feedback-{0}.md" -f $safeUserId)
    $filled = Test-Filled $row

    $lines = @(
        "# Internal Beta Feedback $userId",
        "",
        "Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "",
        ('Source CSV: `' + $FeedbackPath + '`'),
        "",
        "## Session Tasks",
        "",
        "- Register a new account or sign in with a learner account.",
        "- Complete 2 beginner dictation questions.",
        "- Complete 2 intermediate dictation questions.",
        "- Complete 1 advanced dictation question.",
        "- Try normal speed, slow speed, first-letter hint, and Chinese hint.",
        "- Intentionally answer 1 question incorrectly and check feedback.",
        "- Open vocabulary review and learning records.",
        "",
        "## Allowed Values",
        "",
        '- `CompletedTest`, `IndependentCompletion`: `yes` or `no`.',
        '- `UnderstandsDifficulty`, `PerceivedUseful`: `yes`, `partial`, or `no`.',
        '- `WillingNext`: `yes`, `average`, or `no`.',
        '- `Priority`: `P0`, `P1`, or `P2`.',
        "",
        "## Feedback",
        "",
        "| Field | Value |",
        "| --- | --- |"
    )

    foreach ($field in $fields) {
        $lines += "| $field | $(ConvertTo-MarkdownText $row.$field) |"
    }

    Set-Content -LiteralPath $outputPath -Value ($lines -join "`r`n") -Encoding UTF8

    $packetFiles.Add([pscustomobject]@{
        userId = $userId
        outputPath = $outputPath
        filled = $filled
    })
}

$indexPath = Join-Path $OutputDirectory "index.md"
$indexLines = @(
    "# Internal Beta Feedback Packets",
    "",
    "Generated at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "",
    'Use these packets to record one beta session per tester. The canonical feedback desk remains `feedback/internal-beta-feedback.html`.',
    "",
    "| User | Filled | File |",
    "| --- | --- | --- |"
) + @($packetFiles | ForEach-Object {
    "| $($_.userId) | $($_.filled) | $(Get-MarkdownLink 'Open' $_.outputPath) |"
})

Set-Content -LiteralPath $indexPath -Value ($indexLines -join "`r`n") -Encoding UTF8

[pscustomobject]@{
    outputDirectory = $OutputDirectory
    indexPath = $indexPath
    userCount = $rows.Count
    packetCount = $packetFiles.Count
    packets = $packetFiles
} | ConvertTo-Json -Depth 6
