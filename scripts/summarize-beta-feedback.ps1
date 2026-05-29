param(
    [string]$FeedbackPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($FeedbackPath)) {
    $FeedbackPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv"
}

$FeedbackPath = [System.IO.Path]::GetFullPath($FeedbackPath)
if (-not (Test-Path -LiteralPath $FeedbackPath)) {
    throw "Feedback file not found: $FeedbackPath. Run .\scripts\export-beta-feedback-template.ps1 first."
}

function Test-Yes($value) {
    if ($null -eq $value) {
        return $false
    }

    $normalized = ([string]$value).Trim().ToLowerInvariant()
    $yesCn = [string][char]0x662f
    $completedCn = -join @([char]0x5b8c, [char]0x6210)
    $usefulCn = -join @([char]0x6709, [char]0x7528)

    return @("yes", "y", "true", "1", $yesCn, $completedCn, $usefulCn) -contains $normalized
}

function Test-PartialOrYes($value) {
    if (Test-Yes $value) {
        return $true
    }

    $normalized = ([string]$value).Trim().ToLowerInvariant()
    $partialCn = -join @([char]0x90e8, [char]0x5206)
    $averageCn = -join @([char]0x4e00, [char]0x822c)

    return @("partial", "partly", $partialCn, $averageCn) -contains $normalized
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

$rows = @(Import-Csv -LiteralPath $FeedbackPath -Encoding UTF8)
$filledRows = @($rows | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.CompletedTest) -or
    -not [string]::IsNullOrWhiteSpace($_.IndependentCompletion) -or
    -not [string]::IsNullOrWhiteSpace($_.Notes)
})
$touchedRows = @($rows | Where-Object { Test-Touched $_ })

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

$invalidRows = @($rows | Where-Object {
    -not (Test-AllowedValue $_ "UserType" @("university_student", "workplace_newcomer", "general_learner")) -or
    -not (Test-AllowedValue $_ "EnglishLevel" @("beginner", "intermediate", "advanced", "uncertain")) -or
    -not (Test-AllowedValue $_ "CompletedTest" @("yes", "no")) -or
    -not (Test-AllowedValue $_ "IndependentCompletion" @("yes", "no")) -or
    -not (Test-AllowedValue $_ "UnderstandsDifficulty" @("yes", "partial", "no")) -or
    -not (Test-AllowedValue $_ "WillingNext" @("yes", "average", "no")) -or
    -not (Test-AllowedValue $_ "PerceivedUseful" @("yes", "partial", "no")) -or
    -not (Test-AllowedValue $_ "AudioIssue" @("none", "too_fast", "too_slow", "mechanical", "low_volume", "playback_failed")) -or
    -not (Test-AllowedValue $_ "Priority" @("P0", "P1", "P2"))
})

$incompleteTouchedRows = @($touchedRows | Where-Object {
    $row = $_
    @($requiredForComplete | Where-Object {
        [string]::IsNullOrWhiteSpace((Get-FieldValue $row $_))
    }).Count -gt 0
})

$untriagedIssueRows = @($touchedRows | Where-Object {
    @(Get-IssueFields $_).Count -gt 0 -and [string]::IsNullOrWhiteSpace((Get-Priority (Get-FieldValue $_ "Priority")))
})

$completedUsers = @($filledRows | Where-Object { Test-Yes $_.CompletedTest }).Count
$independentUsers = @($filledRows | Where-Object { Test-Yes $_.IndependentCompletion }).Count
$difficultyUnderstoodUsers = @($filledRows | Where-Object { Test-PartialOrYes $_.UnderstandsDifficulty }).Count
$willingNextUsers = @($filledRows | Where-Object { Test-Yes $_.WillingNext }).Count
$usefulUsers = @($filledRows | Where-Object { Test-PartialOrYes $_.PerceivedUseful }).Count
$p0Issues = @($filledRows | Where-Object { ([string]$_.Priority).Trim().ToUpperInvariant() -eq "P0" }).Count
$p1Issues = @($filledRows | Where-Object { ([string]$_.Priority).Trim().ToUpperInvariant() -eq "P1" }).Count

$passesMinimumGate =
    $completedUsers -ge 5 -and
    $independentUsers -ge 4 -and
    $difficultyUnderstoodUsers -ge 4 -and
    $willingNextUsers -ge 3 -and
    $p0Issues -eq 0 -and
    $invalidRows.Count -eq 0 -and
    $incompleteTouchedRows.Count -eq 0 -and
    $untriagedIssueRows.Count -eq 0

[pscustomobject]@{
    feedbackPath = $FeedbackPath
    filledRows = $filledRows.Count
    touchedRows = $touchedRows.Count
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
    passesMinimumGate = $passesMinimumGate
    gate = [pscustomobject]@{
        completedUsers = ">= 5"
        independentUsers = ">= 4"
        difficultyUnderstoodUsers = ">= 4"
        willingNextUsers = ">= 3"
        p0Issues = "0"
        invalidRows = "0"
        incompleteTouchedRows = "0"
        untriagedIssueRows = "0"
    }
} | ConvertTo-Json -Depth 5
