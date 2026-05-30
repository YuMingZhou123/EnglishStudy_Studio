param(
    [string]$ReviewPath = "",
    [string]$Batch = "",
    [string]$OutputPath = "",
    [int]$BatchSize = 20,
    [switch]$Open
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ReviewPath)) {
    $ReviewPath = Join-Path $RepoRoot "content\mvp-content-review.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\content-review-session.md"
}

if ($BatchSize -lt 1) {
    throw "BatchSize must be greater than 0."
}

$ReviewPath = [System.IO.Path]::GetFullPath($ReviewPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $ReviewPath)) {
    throw "Review file not found: $ReviewPath. Run .\scripts\prepare-mvp-acceptance.ps1 first."
}

function ConvertTo-MarkdownText($value) {
    $text = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Replace("\", "\\").Replace("|", "\|").Replace("`r`n", "<br>").Replace("`n", "<br>")
}

function ConvertTo-FileUri([string]$path) {
    return ([System.Uri][System.IO.Path]::GetFullPath($path)).AbsoluteUri
}

function ConvertTo-FileUriWithQuery([string]$path, [hashtable]$Query = @{}) {
    $uri = ConvertTo-FileUri $path
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

function Get-Status($value) {
    return ([string]$value).Trim().ToLowerInvariant()
}

function Get-BatchRange([string]$BatchValue, $rows) {
    if (-not [string]::IsNullOrWhiteSpace($BatchValue)) {
        if ($BatchValue -notmatch "^(\d+)-(\d+)$") {
            throw "Batch must use start-end format, for example 1-20."
        }

        $start = [int]$Matches[1]
        $end = [int]$Matches[2]
        if ($start -lt 1 -or $end -lt $start -or $end -gt $rows.Count) {
            throw "Batch range is outside review rows: $BatchValue"
        }

        return [pscustomobject]@{
            start = $start
            end = $end
            reason = "requested"
        }
    }

    $target = $null
    $reason = "next blank row"
    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace([string]$row.ReviewStatus)) {
            $target = $row
            break
        }
    }

    if ($null -eq $target) {
        foreach ($row in $rows) {
            $status = Get-Status $row.ReviewStatus
            if ($status.StartsWith("fix_") -or $status -eq "remove") {
                $target = $row
                $reason = "next fix/remove row"
                break
            }
        }
    }

    if ($null -eq $target) {
        $target = $rows[0]
        $reason = "all rows have review status"
    }

    $rowNumber = 1
    if (-not [int]::TryParse([string]$target.RowNumber, [ref]$rowNumber)) {
        $rowNumber = 1
    }

    $startRow = ([math]::Floor(($rowNumber - 1) / $BatchSize) * $BatchSize) + 1
    $endRow = [math]::Min($startRow + $BatchSize - 1, $rows.Count)

    return [pscustomobject]@{
        start = $startRow
        end = $endRow
        reason = $reason
    }
}

$rows = @(Import-Csv -LiteralPath $ReviewPath -Encoding UTF8)
if ($rows.Count -eq 0) {
    throw "Review CSV has no rows: $ReviewPath"
}

$range = Get-BatchRange $Batch $rows
$batchRows = @($rows | Where-Object {
    $rowNumber = 0
    [int]::TryParse([string]$_.RowNumber, [ref]$rowNumber) -and
        $rowNumber -ge $range.start -and
        $rowNumber -le $range.end
})

if ($batchRows.Count -eq 0) {
    throw "No review rows found for batch $($range.start)-$($range.end)."
}

$passRows = @($batchRows | Where-Object { (Get-Status $_.ReviewStatus) -eq "pass" })
$fixRows = @($batchRows | Where-Object {
    $status = Get-Status $_.ReviewStatus
    $status.StartsWith("fix_") -or $status -eq "remove"
})
$blankRows = @($batchRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ReviewStatus) })
$batchName = "$($range.start)-$($range.end)"
$statusFilter = if ($blankRows.Count -gt 0) {
    "blank"
}
elseif ($fixRows.Count -gt 0) {
    "fix"
}
else {
    ""
}

$contentReviewHtmlPath = Join-Path $RepoRoot "content\mvp-content-review.html"
$packetPath = Join-Path $RepoRoot ("content\review-packets\content-review-batch-{0:D3}-{1:D3}.md" -f ([int]$range.start), ([int]$range.end))
$contentReviewGuidePath = Join-Path $RepoRoot "docs\content-quality-review.md"
$precheckReportPath = Join-Path $RepoRoot "acceptance\content-precheck-report.md"
$progressPath = Join-Path $RepoRoot "acceptance\first-version-progress.md"
$handoffPath = Join-Path $RepoRoot "acceptance\first-version-handoff.md"
$humanPlanPath = Join-Path $RepoRoot "acceptance\first-version-human-plan.md"

$query = @{ batch = $batchName }
if (-not [string]::IsNullOrWhiteSpace($statusFilter)) {
    $query.status = $statusFilter
}

$reviewDeskUri = ConvertTo-FileUriWithQuery $contentReviewHtmlPath $query
$packetUri = if (Test-Path -LiteralPath $packetPath) { ConvertTo-FileUri $packetPath } else { "" }
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$rowLines = @(
    "| Row | Scene | Level | Status | Sentence | Translation | Keywords |",
    "| ---: | --- | --- | --- | --- | --- | --- |"
) + @($batchRows | ForEach-Object {
    "| $($_.RowNumber) | $(ConvertTo-MarkdownText $_.SceneCode) | $(ConvertTo-MarkdownText $_.Level) | $(ConvertTo-MarkdownText $_.ReviewStatus) | $(ConvertTo-MarkdownText $_.Text) | $(ConvertTo-MarkdownText $_.Translation) | $(ConvertTo-MarkdownText $_.Keywords) |"
})

$lines = @(
    "# Content Review Session",
    "",
    "Generated at: $generatedAt",
    "",
    "## Batch",
    "",
    "- Batch: $batchName",
    "- Selection reason: $($range.reason)",
    "- Total rows: $($batchRows.Count)",
    "- Pass rows: $($passRows.Count)",
    "- Fix/remove rows: $($fixRows.Count)",
    "- Blank rows: $($blankRows.Count)",
    "",
    "## Start Here",
    "",
    "- Review desk: [open]($reviewDeskUri)",
    "- Review packet: [open]($packetUri)",
    "- Review guide: [open]($(ConvertTo-FileUri $contentReviewGuidePath))",
    "- Automated precheck: [open]($(ConvertTo-FileUri $precheckReportPath))",
    "- Human execution plan: [open]($(ConvertTo-FileUri $humanPlanPath))",
    "- First version progress: [open]($(ConvertTo-FileUri $progressPath))",
    "- First version handoff: [open]($(ConvertTo-FileUri $handoffPath))",
    "",
    "## Reviewer Rules",
    "",
    '- Mark `pass` only after sentence text, translation, keywords, and audio experience are actually checked.',
    '- Use `fix_sentence`, `fix_translation`, `fix_keyword`, `fix_audio`, or `remove` when something needs work.',
    "- Leave notes for every non-pass row.",
    "- Export or save results, then validate before importing.",
    "",
    "## Rows",
    ""
) + $rowLines + @(
    "",
    "## Finish Commands",
    "",
    '```powershell',
    ".\scripts\check-content-review-batch.ps1 -Batch $batchName",
    ".\scripts\check-content-review-batch.ps1 -Batch $batchName -AssertComplete",
    '.\scripts\import-content-review-packets.ps1 -ValidateOnly',
    '.\scripts\import-content-review-packets.ps1 -RefreshArtifacts',
    '.\scripts\import-acceptance-csv.ps1 -Kind content -ValidateOnly',
    '.\scripts\import-acceptance-csv.ps1 -Kind content -RefreshArtifacts',
    '.\scripts\start-content-review-batch.ps1',
    '.\scripts\export-first-version-progress.ps1',
    '.\scripts\export-first-version-human-plan.ps1',
    '.\scripts\check-local-beta-readiness.ps1',
    '```'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

if ($Open) {
    Start-Process -FilePath $OutputPath
    Start-Process -FilePath $reviewDeskUri
    if (-not [string]::IsNullOrWhiteSpace($packetUri)) {
        Start-Process -FilePath $packetUri
    }
}

[pscustomobject]@{
    outputPath = $OutputPath
    batch = $batchName
    selectionReason = $range.reason
    totalRows = $batchRows.Count
    passRows = $passRows.Count
    fixRows = $fixRows.Count
    blankRows = $blankRows.Count
    reviewDeskUri = $reviewDeskUri
    packetPath = $packetPath
} | ConvertTo-Json -Depth 6
