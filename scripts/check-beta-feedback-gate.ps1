param(
    [string]$FeedbackPath = "",
    [string]$OutputPath = "",
    [switch]$AssertReady
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($FeedbackPath)) {
    $FeedbackPath = Join-Path $RepoRoot "feedback\internal-beta-feedback.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\beta-feedback-gate-check.md"
}

$FeedbackPath = [System.IO.Path]::GetFullPath($FeedbackPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $FeedbackPath)) {
    throw "Feedback file not found: $FeedbackPath. Run .\scripts\prepare-mvp-acceptance.ps1 first."
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

function Get-Priority($value) {
    return ([string]$value).Trim().ToUpperInvariant()
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

function Test-Yes($value) {
    return (Get-Status $value) -eq "yes"
}

function Test-PartialOrYes($value) {
    $value = Get-Status $value
    return $value -eq "yes" -or $value -eq "partial"
}

function Test-Touched($row) {
    foreach ($field in @(
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
    )) {
        if (-not [string]::IsNullOrWhiteSpace((Get-FieldValue $row $field))) {
            return $true
        }
    }

    return $false
}

function Test-Filled($row) {
    return -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "CompletedTest")) -or
        -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "IndependentCompletion")) -or
        -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "Notes"))
}

function Test-AllowedValue($row, [string]$fieldName, [string[]]$allowedValues) {
    $value = Get-Status (Get-FieldValue $row $fieldName)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $true
    }

    $allowed = @{}
    foreach ($allowedValue in $allowedValues) {
        $allowed[(Get-Status $allowedValue)] = $true
    }

    return $allowed.ContainsKey($value)
}

function Get-IssueFields($row) {
    $items = New-Object System.Collections.Generic.List[string]

    foreach ($field in @("StuckStep", "PageIssue", "ContentIssue")) {
        if (-not [string]::IsNullOrWhiteSpace((Get-FieldValue $row $field))) {
            $items.Add($field)
        }
    }

    $audioIssue = Get-Status (Get-FieldValue $row "AudioIssue")
    if (-not [string]::IsNullOrWhiteSpace($audioIssue) -and $audioIssue -ne "none") {
        $items.Add("AudioIssue")
    }

    return $items.ToArray()
}

function New-Shortage([string]$Gate, [int]$Current, [int]$Target) {
    [pscustomobject]@{
        gate = $Gate
        current = $Current
        target = $Target
        missing = [math]::Max(0, $Target - $Current)
    }
}

$rows = @(Import-Csv -LiteralPath $FeedbackPath -Encoding UTF8)
if ($rows.Count -eq 0) {
    throw "Feedback CSV has no rows: $FeedbackPath"
}

$requiredColumns = @(
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

$columns = @($rows[0].PSObject.Properties.Name)
$missingColumns = @($requiredColumns | Where-Object { $columns -notcontains $_ })
if ($missingColumns.Count -gt 0) {
    throw "Feedback CSV is missing required columns: $($missingColumns -join ', ')"
}

$requiredForComplete = @(
    "UserType",
    "EnglishLevel",
    "CompletedTest",
    "IndependentCompletion",
    "UnderstandsDifficulty",
    "WillingNext",
    "PerceivedUseful",
    "AudioIssue",
    "Notes"
)

$rowChecks = @($rows | ForEach-Object {
    $row = $_
    $problems = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $touched = Test-Touched $row
    $filled = Test-Filled $row

    if ($touched) {
        foreach ($field in $requiredForComplete) {
            if ([string]::IsNullOrWhiteSpace((Get-FieldValue $row $field))) {
                $problems.Add("blank $field")
            }
        }
    }

    $valueRules = @(
        @{ field = "UserType"; allowed = @("university_student", "workplace_newcomer", "general_learner") },
        @{ field = "EnglishLevel"; allowed = @("beginner", "intermediate", "advanced", "uncertain") },
        @{ field = "CompletedTest"; allowed = @("yes", "no") },
        @{ field = "IndependentCompletion"; allowed = @("yes", "no") },
        @{ field = "UnderstandsDifficulty"; allowed = @("yes", "partial", "no") },
        @{ field = "WillingNext"; allowed = @("yes", "average", "no") },
        @{ field = "PerceivedUseful"; allowed = @("yes", "partial", "no") },
        @{ field = "AudioIssue"; allowed = @("none", "too_fast", "too_slow", "mechanical", "low_volume", "playback_failed") },
        @{ field = "Priority"; allowed = @("P0", "P1", "P2") }
    )

    foreach ($rule in $valueRules) {
        if (-not (Test-AllowedValue $row $rule.field $rule.allowed)) {
            $problems.Add("invalid $($rule.field)")
        }
    }

    $issueFields = @(Get-IssueFields $row)
    $priority = Get-Priority (Get-FieldValue $row "Priority")
    if ($issueFields.Count -gt 0 -and [string]::IsNullOrWhiteSpace($priority)) {
        $problems.Add("issue fields missing Priority")
    }

    if ($issueFields.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($priority)) {
        $warnings.Add("Priority is set but no issue field is filled")
    }

    [pscustomobject]@{
        userId = Get-FieldValue $row "UserId"
        userType = Get-FieldValue $row "UserType"
        englishLevel = Get-FieldValue $row "EnglishLevel"
        touched = $touched
        filled = $filled
        completed = Test-Yes (Get-FieldValue $row "CompletedTest")
        independent = Test-Yes (Get-FieldValue $row "IndependentCompletion")
        understandsDifficulty = Test-PartialOrYes (Get-FieldValue $row "UnderstandsDifficulty")
        willingNext = Test-Yes (Get-FieldValue $row "WillingNext")
        perceivedUseful = Test-PartialOrYes (Get-FieldValue $row "PerceivedUseful")
        priority = $priority
        p0 = $priority -eq "P0"
        p1 = $priority -eq "P1"
        issueFieldCount = $issueFields.Count
        issueFields = ($issueFields -join ", ")
        problemCount = $problems.Count
        problems = @($problems)
        warningCount = $warnings.Count
        warnings = @($warnings)
        notes = Get-FieldValue $row "Notes"
    }
})

$filledRows = @($rowChecks | Where-Object { $_.filled })
$touchedRows = @($rowChecks | Where-Object { $_.touched })
$completedUsers = @($filledRows | Where-Object { $_.completed }).Count
$independentUsers = @($filledRows | Where-Object { $_.independent }).Count
$difficultyUnderstoodUsers = @($filledRows | Where-Object { $_.understandsDifficulty }).Count
$willingNextUsers = @($filledRows | Where-Object { $_.willingNext }).Count
$usefulUsers = @($filledRows | Where-Object { $_.perceivedUseful }).Count
$p0Issues = @($filledRows | Where-Object { $_.p0 }).Count
$p1Issues = @($filledRows | Where-Object { $_.p1 }).Count
$problemRows = @($rowChecks | Where-Object { $_.problemCount -gt 0 })
$warningRows = @($rowChecks | Where-Object { $_.warningCount -gt 0 })
$untriagedIssueRows = @($touchedRows | Where-Object { $_.issueFieldCount -gt 0 -and [string]::IsNullOrWhiteSpace($_.priority) })
$invalidRows = @($rowChecks | Where-Object { @($_.problems | Where-Object { $_ -like "invalid *" }).Count -gt 0 })
$incompleteTouchedRows = @($touchedRows | Where-Object { @($_.problems | Where-Object { $_ -like "blank *" }).Count -gt 0 })

$shortages = New-Object System.Collections.Generic.List[object]
if ($completedUsers -lt 5) {
    $shortages.Add((New-Shortage "completed users" $completedUsers 5))
}
if ($independentUsers -lt 4) {
    $shortages.Add((New-Shortage "independent users" $independentUsers 4))
}
if ($difficultyUnderstoodUsers -lt 4) {
    $shortages.Add((New-Shortage "difficulty understood users" $difficultyUnderstoodUsers 4))
}
if ($willingNextUsers -lt 3) {
    $shortages.Add((New-Shortage "willing next users" $willingNextUsers 3))
}

$ready =
    $shortages.Count -eq 0 -and
    $p0Issues -eq 0 -and
    $problemRows.Count -eq 0

$shortageLines = if ($shortages.Count -eq 0) {
    @("- No minimum-count shortages.")
}
else {
    @(
        "| Gate | Current | Target | Missing |",
        "| --- | ---: | ---: | ---: |"
    ) + @($shortages | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.gate) | $($_.current) | $($_.target) | $($_.missing) |"
    })
}

$problemLines = if ($problemRows.Count -eq 0) {
    @("- No blocking row problems.")
}
else {
    @(
        "| User | Problems | Issue fields | Priority | Notes |",
        "| --- | --- | --- | --- | --- |"
    ) + @($problemRows | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.userId) | $(ConvertTo-MarkdownText ($_.problems -join ', ')) | $(ConvertTo-MarkdownText $_.issueFields) | $(ConvertTo-MarkdownText $_.priority) | $(ConvertTo-MarkdownText $_.notes) |"
    })
}

$warningLines = if ($warningRows.Count -eq 0) {
    @("- No row warnings.")
}
else {
    @(
        "| User | Warnings |",
        "| --- | --- |"
    ) + @($warningRows | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.userId) | $(ConvertTo-MarkdownText ($_.warnings -join ', ')) |"
    })
}

$userLines = @(
    "| User | Touched | Filled | Completed | Independent | Difficulty | Willing | Useful | Priority | Problems |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | ---: |"
) + @($rowChecks | ForEach-Object {
    "| $(ConvertTo-MarkdownText $_.userId) | $($_.touched) | $($_.filled) | $($_.completed) | $($_.independent) | $($_.understandsDifficulty) | $($_.willingNext) | $($_.perceivedUseful) | $(ConvertTo-MarkdownText $_.priority) | $($_.problemCount) |"
})

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# Beta Feedback Gate Check",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- Beta feedback gate ready: $ready",
    ('- Feedback path: `' + $FeedbackPath + '`'),
    "",
    "## Summary",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    "| Total rows | $($rows.Count) |",
    "| Touched rows | $($touchedRows.Count) |",
    "| Filled rows | $($filledRows.Count) |",
    "| Completed users | $completedUsers |",
    "| Independent users | $independentUsers |",
    "| Difficulty understood users | $difficultyUnderstoodUsers |",
    "| Willing next users | $willingNextUsers |",
    "| Useful users | $usefulUsers |",
    "| P0 issues | $p0Issues |",
    "| P1 issues | $p1Issues |",
    "| Invalid rows | $($invalidRows.Count) |",
    "| Incomplete touched rows | $($incompleteTouchedRows.Count) |",
    "| Untriaged issue rows | $($untriagedIssueRows.Count) |",
    "| Blocking problem rows | $($problemRows.Count) |",
    "",
    "## Minimum Shortages",
    ""
) + $shortageLines + @(
    "",
    "## Row Problems",
    ""
) + $problemLines + @(
    "",
    "## Row Warnings",
    ""
) + $warningLines + @(
    "",
    "## User Status",
    ""
) + $userLines + @(
    "",
    "## Final Commands",
    "",
    '```powershell',
    '.\scripts\check-beta-feedback-gate.ps1 -AssertReady',
    '.\scripts\summarize-beta-feedback.ps1',
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
    feedbackPath = $FeedbackPath
    ready = $ready
    totalRows = $rows.Count
    touchedRows = $touchedRows.Count
    filledRows = $filledRows.Count
    completedUsers = $completedUsers
    independentUsers = $independentUsers
    difficultyUnderstoodUsers = $difficultyUnderstoodUsers
    willingNextUsers = $willingNextUsers
    usefulUsers = $usefulUsers
    p0Issues = $p0Issues
    p1Issues = $p1Issues
    invalidRows = $invalidRows.Count
    incompleteTouchedRows = $incompleteTouchedRows.Count
    untriagedIssueRows = $untriagedIssueRows.Count
    problemRows = $problemRows.Count
    warningRows = $warningRows.Count
    minimumShortages = $shortages.Count
}

if ($AssertReady -and -not $ready) {
    $result | ConvertTo-Json -Depth 8
    throw "Beta feedback gate is not ready."
}

$result | ConvertTo-Json -Depth 8
