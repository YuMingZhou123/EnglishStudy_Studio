param(
    [string]$ReviewPath = "",
    [string]$OutputPath = "",
    [int]$BatchSize = 20,
    [switch]$AssertReady
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ReviewPath)) {
    $ReviewPath = Join-Path $RepoRoot "content\mvp-content-review.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\content-review-gate-check.md"
}

if ($BatchSize -lt 1) {
    throw "BatchSize must be greater than 0."
}

$ReviewPath = [System.IO.Path]::GetFullPath($ReviewPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $ReviewPath)) {
    throw "Review file not found: $ReviewPath. Run .\scripts\prepare-mvp-acceptance.ps1 first."
}

$allowedStatuses = @(
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

function New-Shortage([string]$Area, [string]$Gate, [int]$Current, [int]$Target) {
    [pscustomobject]@{
        area = $Area
        gate = $Gate
        current = $Current
        target = $Target
        missing = [math]::Max(0, $Target - $Current)
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

$rowChecks = @($rows | ForEach-Object {
    $status = Get-Status $_.ReviewStatus
    $notes = @(Get-Notes $_)
    $problems = New-Object System.Collections.Generic.List[string]

    if ([string]::IsNullOrWhiteSpace($status)) {
        $problems.Add("blank status")
    }
    elseif ($allowedStatuses -notcontains $status) {
        $problems.Add("invalid status")
    }

    if ([string]::IsNullOrWhiteSpace($status) -and $notes.Count -gt 0) {
        $problems.Add("notes without status")
    }

    if (-not [string]::IsNullOrWhiteSpace($status) -and
        $allowedStatuses -contains $status -and
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

$passRows = @($rowChecks | Where-Object { $_.status -eq "pass" })
$fixRows = @($rowChecks | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.status) -and
        $allowedStatuses -contains $_.status -and
        $_.status -ne "pass"
})
$blankRows = @($rowChecks | Where-Object { $_.problems -contains "blank status" })
$invalidStatusRows = @($rowChecks | Where-Object { $_.problems -contains "invalid status" })
$notesWithoutStatusRows = @($rowChecks | Where-Object { $_.problems -contains "notes without status" })
$missingNoteRows = @($rowChecks | Where-Object { $_.problems -contains "fix/remove missing notes" })

$scenePassCounts = [ordered]@{}
foreach ($group in ($passRows | Group-Object scene | Sort-Object Name)) {
    $scenePassCounts[$group.Name] = $group.Count
}

$levelPassCounts = [ordered]@{}
foreach ($level in @("beginner", "intermediate", "advanced")) {
    $levelPassCounts[$level] = @($passRows | Where-Object { $_.level -eq $level }).Count
}

$shortages = New-Object System.Collections.Generic.List[object]
if ($rows.Count -lt 120) {
    $shortages.Add((New-Shortage "content" "total rows" $rows.Count 120))
}

if ($passRows.Count -lt 100) {
    $shortages.Add((New-Shortage "content" "pass rows" $passRows.Count 100))
}

foreach ($scene in @($rows | ForEach-Object { [string]$_.SceneCode } | Sort-Object -Unique)) {
    $current = if ($scenePassCounts.Contains($scene)) { [int]$scenePassCounts[$scene] } else { 0 }
    if ($current -lt 15) {
        $shortages.Add((New-Shortage "scene:$scene" "pass rows" $current 15))
    }
}

foreach ($level in @("beginner", "intermediate", "advanced")) {
    $current = [int]$levelPassCounts[$level]
    if ($current -lt 15) {
        $shortages.Add((New-Shortage "level:$level" "pass rows" $current 15))
    }
}

$ready =
    $shortages.Count -eq 0 -and
    $fixRows.Count -eq 0 -and
    $blankRows.Count -eq 0 -and
    $invalidStatusRows.Count -eq 0 -and
    $notesWithoutStatusRows.Count -eq 0 -and
    $missingNoteRows.Count -eq 0

$batchCount = [math]::Ceiling($rows.Count / $BatchSize)
$batchRows = @(
    for ($index = 0; $index -lt $batchCount; $index++) {
        $start = ($index * $BatchSize) + 1
        $end = [math]::Min(($index + 1) * $BatchSize, $rows.Count)
        $batch = @($rowChecks | Where-Object { $_.rowNumber -ge $start -and $_.rowNumber -le $end })
        $batchProblems = @($batch | Where-Object { $_.problemCount -gt 0 })
        $batchPassRows = @($batch | Where-Object { $_.status -eq "pass" })
        $batchFixRows = @($batch | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_.status) -and
                $allowedStatuses -contains $_.status -and
                $_.status -ne "pass"
        })
        $batchBlankRows = @($batch | Where-Object { $_.problems -contains "blank status" })

        [pscustomobject]@{
            batch = "$start-$end"
            passRows = $batchPassRows.Count
            fixRows = $batchFixRows.Count
            blankRows = $batchBlankRows.Count
            problemRows = $batchProblems.Count
        }
    }
)

$shortageLines = if ($shortages.Count -eq 0) {
    @("- No minimum-count shortages.")
}
else {
    @(
        "| Area | Gate | Current | Target | Missing |",
        "| --- | --- | ---: | ---: | ---: |"
    ) + @($shortages | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.area) | $(ConvertTo-MarkdownText $_.gate) | $($_.current) | $($_.target) | $($_.missing) |"
    })
}

$problemRows = @($rowChecks | Where-Object { $_.problemCount -gt 0 })
$problemLines = if ($problemRows.Count -eq 0) {
    @("- No row format problems.")
}
else {
    @(
        "| Row | Status | Problems | Sentence | Notes |",
        "| ---: | --- | --- | --- | --- |"
    ) + @($problemRows | Select-Object -First 80 | ForEach-Object {
        "| $($_.rowNumber) | $(ConvertTo-MarkdownText $_.status) | $(ConvertTo-MarkdownText ($_.problems -join ', ')) | $(ConvertTo-MarkdownText $_.text) | $(ConvertTo-MarkdownText $_.notes) |"
    })
}

$batchLines = @(
    "| Batch | Pass | Fix/remove | Blank | Problem rows |",
    "| --- | ---: | ---: | ---: | ---: |"
) + @($batchRows | ForEach-Object {
    "| $(ConvertTo-MarkdownText $_.batch) | $($_.passRows) | $($_.fixRows) | $($_.blankRows) | $($_.problemRows) |"
})

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# Content Review Gate Check",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- Content review gate ready: $ready",
    ('- Review path: `' + $ReviewPath + '`'),
    "",
    "## Summary",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    "| Total rows | $($rows.Count) |",
    "| Pass rows | $($passRows.Count) |",
    "| Fix/remove rows | $($fixRows.Count) |",
    "| Blank rows | $($blankRows.Count) |",
    "| Invalid status rows | $($invalidStatusRows.Count) |",
    "| Notes without status rows | $($notesWithoutStatusRows.Count) |",
    "| Fix/remove missing notes rows | $($missingNoteRows.Count) |",
    "| Minimum-count shortages | $($shortages.Count) |",
    "",
    "## Minimum Shortages",
    ""
) + $shortageLines + @(
    "",
    "## Batch Status",
    ""
) + $batchLines + @(
    "",
    "## Row Problems",
    ""
) + $problemLines + @(
    "",
    "## Final Commands",
    "",
    '```powershell',
    '.\scripts\check-content-review-gate.ps1 -AssertReady',
    '.\scripts\summarize-content-review.ps1',
    '.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady',
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
    ready = $ready
    totalRows = $rows.Count
    passRows = $passRows.Count
    fixRows = $fixRows.Count
    blankRows = $blankRows.Count
    invalidStatusRows = $invalidStatusRows.Count
    notesWithoutStatusRows = $notesWithoutStatusRows.Count
    missingNoteRows = $missingNoteRows.Count
    minimumShortages = $shortages.Count
    problemRows = $problemRows.Count
    batchCount = $batchRows.Count
    scenePassCounts = $scenePassCounts
    levelPassCounts = $levelPassCounts
}

if ($AssertReady -and -not $ready) {
    $result | ConvertTo-Json -Depth 8
    throw "Content review gate is not ready."
}

$result | ConvertTo-Json -Depth 8
