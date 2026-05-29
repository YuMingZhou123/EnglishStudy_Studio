param(
    [string]$FeedbackPath = "",
    [string]$UserId = "",
    [string]$OutputPath = "",
    [switch]$AssertComplete
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($FeedbackPath)) {
    $FeedbackPath = Join-Path $RepoRoot "feedback\internal-beta-feedback.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\beta-feedback-session-check.md"
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

function Test-Filled($row) {
    return -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "CompletedTest")) -or
        -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "IndependentCompletion")) -or
        -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "Notes"))
}

function Get-IssueFields($row) {
    $items = New-Object System.Collections.Generic.List[object]

    $stuckStep = Get-FieldValue $row "StuckStep"
    if (-not [string]::IsNullOrWhiteSpace($stuckStep)) {
        $items.Add([pscustomobject]@{ field = "StuckStep"; value = $stuckStep })
    }

    $audioIssue = Get-Status (Get-FieldValue $row "AudioIssue")
    if (-not [string]::IsNullOrWhiteSpace($audioIssue) -and $audioIssue -ne "none") {
        $items.Add([pscustomobject]@{ field = "AudioIssue"; value = Get-FieldValue $row "AudioIssue" })
    }

    foreach ($field in @("PageIssue", "ContentIssue")) {
        $value = Get-FieldValue $row $field
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $items.Add([pscustomobject]@{ field = $field; value = $value })
        }
    }

    return $items.ToArray()
}

function Assert-AllowedValue {
    param(
        [object]$Row,
        [System.Collections.Generic.List[string]]$Problems,
        [string]$Field,
        [string[]]$AllowedValues
    )

    $value = Get-Status (Get-FieldValue $Row $Field)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return
    }

    $allowed = @{}
    foreach ($item in $AllowedValues) {
        $allowed[(Get-Status $item)] = $true
    }

    if (-not $allowed.ContainsKey($value)) {
        $Problems.Add("invalid $Field")
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

$target = $null
$selectionReason = "next incomplete tester"
if (-not [string]::IsNullOrWhiteSpace($UserId)) {
    $target = @($rows | Where-Object {
        (Get-FieldValue $_ "UserId").Equals($UserId, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1)

    if ($target.Count -eq 0) {
        throw "UserId was not found in feedback rows: $UserId"
    }

    $target = $target[0]
    $selectionReason = "requested"
}
else {
    $target = @($rows | Where-Object { -not (Test-Filled $_) } | Select-Object -First 1)
    if ($target.Count -eq 0) {
        $target = $rows[0]
        $selectionReason = "all testers have feedback"
    }
    else {
        $target = $target[0]
    }
}

$problems = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
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

foreach ($field in $requiredForComplete) {
    if ([string]::IsNullOrWhiteSpace((Get-FieldValue $target $field))) {
        $problems.Add("blank $field")
    }
}

Assert-AllowedValue -Row $target -Problems $problems -Field "UserType" -AllowedValues @("university_student", "workplace_newcomer", "general_learner")
Assert-AllowedValue -Row $target -Problems $problems -Field "EnglishLevel" -AllowedValues @("beginner", "intermediate", "advanced", "uncertain")
Assert-AllowedValue -Row $target -Problems $problems -Field "CompletedTest" -AllowedValues @("yes", "no")
Assert-AllowedValue -Row $target -Problems $problems -Field "IndependentCompletion" -AllowedValues @("yes", "no")
Assert-AllowedValue -Row $target -Problems $problems -Field "UnderstandsDifficulty" -AllowedValues @("yes", "partial", "no")
Assert-AllowedValue -Row $target -Problems $problems -Field "WillingNext" -AllowedValues @("yes", "average", "no")
Assert-AllowedValue -Row $target -Problems $problems -Field "PerceivedUseful" -AllowedValues @("yes", "partial", "no")
Assert-AllowedValue -Row $target -Problems $problems -Field "AudioIssue" -AllowedValues @("none", "too_fast", "too_slow", "mechanical", "low_volume", "playback_failed")
Assert-AllowedValue -Row $target -Problems $problems -Field "Priority" -AllowedValues @("P0", "P1", "P2")

$issueFields = @(Get-IssueFields $target)
$priority = Get-Priority (Get-FieldValue $target "Priority")
if ($issueFields.Count -gt 0 -and [string]::IsNullOrWhiteSpace($priority)) {
    $problems.Add("issue fields missing Priority")
}

if ($issueFields.Count -eq 0 -and -not [string]::IsNullOrWhiteSpace($priority)) {
    $warnings.Add("Priority is set but no issue field is filled")
}

$complete = $problems.Count -eq 0
$userIdValue = Get-FieldValue $target "UserId"
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

$fieldLines = @(
    "| Field | Value |",
    "| --- | --- |"
) + @($fields | ForEach-Object {
    "| $_ | $(ConvertTo-MarkdownText (Get-FieldValue $target $_)) |"
})

$problemLines = if ($problems.Count -eq 0) {
    @("- No blocking problems.")
}
else {
    @($problems | ForEach-Object { "- $_" })
}

$warningLines = if ($warnings.Count -eq 0) {
    @("- No warnings.")
}
else {
    @($warnings | ForEach-Object { "- $_" })
}

$issueLines = if ($issueFields.Count -eq 0) {
    @("- No issue fields.")
}
else {
    @(
        "| Field | Value |",
        "| --- | --- |"
    ) + @($issueFields | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.field) | $(ConvertTo-MarkdownText $_.value) |"
    })
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# Beta Feedback Session Check",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- Session complete: $complete",
    "- User: $userIdValue",
    "- Selection reason: $selectionReason",
    ('- Feedback path: `' + $FeedbackPath + '`'),
    "",
    "## Problems",
    ""
) + $problemLines + @(
    "",
    "## Warnings",
    ""
) + $warningLines + @(
    "",
    "## Issue Fields",
    ""
) + $issueLines + @(
    "",
    "## Feedback Row",
    ""
) + $fieldLines + @(
    "",
    "## Next Commands",
    "",
    '```powershell',
    ".\scripts\check-beta-feedback-session.ps1 -UserId $userIdValue -AssertComplete",
    ".\scripts\import-acceptance-csv.ps1 -Kind beta -ValidateOnly",
    ".\scripts\import-acceptance-csv.ps1 -Kind beta -RefreshArtifacts",
    ".\scripts\start-beta-feedback-session.ps1",
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
    userId = $userIdValue
    selectionReason = $selectionReason
    complete = $complete
    problemCount = $problems.Count
    warningCount = $warnings.Count
    issueFieldCount = $issueFields.Count
    priority = $priority
    problems = @($problems)
    warnings = @($warnings)
}

if ($AssertComplete -and -not $complete) {
    $result | ConvertTo-Json -Depth 8
    throw "Beta feedback session is incomplete: $userIdValue"
}

$result | ConvertTo-Json -Depth 8
