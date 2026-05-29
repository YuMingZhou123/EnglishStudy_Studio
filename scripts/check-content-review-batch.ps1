param(
    [string]$ReviewPath = "",
    [string]$Batch = "",
    [string]$OutputPath = "",
    [int]$BatchSize = 20,
    [switch]$AssertComplete
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ReviewPath)) {
    $ReviewPath = Join-Path $RepoRoot "content\mvp-content-review.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\content-review-batch-check.md"
}

if ($BatchSize -lt 1) {
    throw "BatchSize must be greater than 0."
}

$ReviewPath = [System.IO.Path]::GetFullPath($ReviewPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $ReviewPath)) {
    throw "Review file not found: $ReviewPath. Run .\scripts\prepare-mvp-acceptance.ps1 first."
}

$AllowedStatuses = @(
    "pass",
    "fix_sentence",
    "fix_translation",
    "fix_keyword",
    "fix_audio",
    "remove"
)

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

function Get-Notes($row) {
    return @(
        [string]$row.SentenceNotes,
        [string]$row.TranslationNotes,
        [string]$row.KeywordNotes,
        [string]$row.AudioNotes,
        [string]$row.FinalNotes
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
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
    $reason = "next incomplete row"
    foreach ($row in $rows) {
        $status = Get-Status $row.ReviewStatus
        $notes = @(Get-Notes $row)
        if ([string]::IsNullOrWhiteSpace($status) -or
            ($AllowedStatuses -notcontains $status) -or
            ($status -ne "pass" -and $notes.Count -eq 0)) {
            $target = $row
            break
        }
    }

    if ($null -eq $target) {
        $target = $rows[0]
        $reason = "all rows complete"
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

$requiredColumns = @(
    "RowNumber",
    "SceneCode",
    "Level",
    "Text",
    "Translation",
    "Keywords",
    "ReviewStatus",
    "SentenceNotes",
    "TranslationNotes",
    "KeywordNotes",
    "AudioNotes",
    "FinalNotes"
)

$columns = @($rows[0].PSObject.Properties.Name)
$missingColumns = @($requiredColumns | Where-Object { $columns -notcontains $_ })
if ($missingColumns.Count -gt 0) {
    throw "Review CSV is missing required columns: $($missingColumns -join ', ')"
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

$rowChecks = @($batchRows | ForEach-Object {
    $status = Get-Status $_.ReviewStatus
    $notes = @(Get-Notes $_)
    $problems = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($status)) {
        $problems.Add("blank status")
    }
    elseif ($AllowedStatuses -notcontains $status) {
        $problems.Add("invalid status")
    }

    if ([string]::IsNullOrWhiteSpace($status) -and $notes.Count -gt 0) {
        $problems.Add("notes without status")
    }

    if (-not [string]::IsNullOrWhiteSpace($status) -and
        $AllowedStatuses -contains $status -and
        $status -ne "pass" -and
        $notes.Count -eq 0) {
        $problems.Add("fix/remove missing notes")
    }

    [pscustomobject]@{
        rowNumber = [int]$_.RowNumber
        scene = [string]$_.SceneCode
        level = [string]$_.Level
        status = $status
        problemCount = $problems.Count
        problems = @($problems)
        notes = ($notes -join "; ")
        text = [string]$_.Text
    }
})

$blankRows = @($rowChecks | Where-Object { $_.problems -contains "blank status" })
$invalidStatusRows = @($rowChecks | Where-Object { $_.problems -contains "invalid status" })
$notesWithoutStatusRows = @($rowChecks | Where-Object { $_.problems -contains "notes without status" })
$missingNoteRows = @($rowChecks | Where-Object { $_.problems -contains "fix/remove missing notes" })
$passRows = @($rowChecks | Where-Object { $_.status -eq "pass" })
$fixRows = @($rowChecks | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.status) -and $_.status -ne "pass"
})
$complete = $blankRows.Count -eq 0 -and
    $invalidStatusRows.Count -eq 0 -and
    $notesWithoutStatusRows.Count -eq 0 -and
    $missingNoteRows.Count -eq 0

$problemLines = if (@($rowChecks | Where-Object { $_.problemCount -gt 0 }).Count -eq 0) {
    @("- No row problems in this batch.")
}
else {
    @(
        "| Row | Status | Problems | Sentence | Notes |",
        "| ---: | --- | --- | --- | --- |"
    ) + @($rowChecks | Where-Object { $_.problemCount -gt 0 } | ForEach-Object {
        "| $($_.rowNumber) | $(ConvertTo-MarkdownText $_.status) | $(ConvertTo-MarkdownText ($_.problems -join ', ')) | $(ConvertTo-MarkdownText $_.text) | $(ConvertTo-MarkdownText $_.notes) |"
    })
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$batchName = "$($range.start)-$($range.end)"
$lines = @(
    "# Content Review Batch Check",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- Batch complete: $complete",
    "- Batch: $batchName",
    "- Selection reason: $($range.reason)",
    ('- Review path: `' + $ReviewPath + '`'),
    "",
    "## Summary",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    "| Total rows | $($batchRows.Count) |",
    "| Pass rows | $($passRows.Count) |",
    "| Fix/remove rows | $($fixRows.Count) |",
    "| Blank rows | $($blankRows.Count) |",
    "| Invalid status rows | $($invalidStatusRows.Count) |",
    "| Notes without status rows | $($notesWithoutStatusRows.Count) |",
    "| Fix/remove missing notes rows | $($missingNoteRows.Count) |",
    "",
    "## Row Problems",
    ""
) + $problemLines + @(
    "",
    "## Next Commands",
    "",
    '```powershell',
    ".\scripts\check-content-review-batch.ps1 -Batch $batchName -AssertComplete",
    ".\scripts\import-acceptance-csv.ps1 -Kind content -ValidateOnly",
    ".\scripts\import-acceptance-csv.ps1 -Kind content -RefreshArtifacts",
    ".\scripts\start-content-review-batch.ps1",
    '```'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

$result = [pscustomobject]@{
    outputPath = $OutputPath
    reviewPath = $ReviewPath
    batch = $batchName
    selectionReason = $range.reason
    complete = $complete
    totalRows = $batchRows.Count
    passRows = $passRows.Count
    fixRows = $fixRows.Count
    blankRows = $blankRows.Count
    invalidStatusRows = $invalidStatusRows.Count
    notesWithoutStatusRows = $notesWithoutStatusRows.Count
    missingNoteRows = $missingNoteRows.Count
    problemRows = @($rowChecks | Where-Object { $_.problemCount -gt 0 } | ForEach-Object { $_.rowNumber })
}

if ($AssertComplete -and -not $complete) {
    $result | ConvertTo-Json -Depth 8
    throw "Content review batch is incomplete: $batchName"
}

$result | ConvertTo-Json -Depth 8
