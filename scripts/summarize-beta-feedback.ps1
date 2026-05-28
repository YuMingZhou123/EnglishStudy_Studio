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

$rows = @(Import-Csv -LiteralPath $FeedbackPath -Encoding UTF8)
$filledRows = @($rows | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.CompletedTest) -or
    -not [string]::IsNullOrWhiteSpace($_.IndependentCompletion) -or
    -not [string]::IsNullOrWhiteSpace($_.Notes)
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
    $p0Issues -eq 0

[pscustomobject]@{
    feedbackPath = $FeedbackPath
    filledRows = $filledRows.Count
    completedUsers = $completedUsers
    independentUsers = $independentUsers
    difficultyUnderstoodUsers = $difficultyUnderstoodUsers
    willingNextUsers = $willingNextUsers
    usefulUsers = $usefulUsers
    p0Issues = $p0Issues
    p1Issues = $p1Issues
    passesMinimumGate = $passesMinimumGate
    gate = [pscustomobject]@{
        completedUsers = ">= 5"
        independentUsers = ">= 4"
        difficultyUnderstoodUsers = ">= 4"
        willingNextUsers = ">= 3"
        p0Issues = "0"
    }
} | ConvertTo-Json -Depth 5
