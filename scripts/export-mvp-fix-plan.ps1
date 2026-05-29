param(
    [string]$ContentReviewPath = "",
    [string]$BetaFeedbackPath = "",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($ContentReviewPath)) {
    $ContentReviewPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.csv"
}

if ([string]::IsNullOrWhiteSpace($BetaFeedbackPath)) {
    $BetaFeedbackPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\acceptance\mvp-fix-plan.md"
}

$ContentReviewPath = [System.IO.Path]::GetFullPath($ContentReviewPath)
$BetaFeedbackPath = [System.IO.Path]::GetFullPath($BetaFeedbackPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

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

function Test-Yes($value) {
    $normalized = Get-Status $value
    $yesCn = [string][char]0x662f
    $completedCn = -join @([char]0x5b8c, [char]0x6210)
    $usefulCn = -join @([char]0x6709, [char]0x7528)

    return @("yes", "y", "true", "1", $yesCn, $completedCn, $usefulCn) -contains $normalized
}

function Test-PartialOrYes($value) {
    if (Test-Yes $value) {
        return $true
    }

    $normalized = Get-Status $value
    $partialCn = -join @([char]0x90e8, [char]0x5206)
    $averageCn = -join @([char]0x4e00, [char]0x822c)

    return @("partial", "partly", $partialCn, $averageCn) -contains $normalized
}

function Get-ReviewNotes($row) {
    return @(
        [string]$row.SentenceNotes,
        [string]$row.TranslationNotes,
        [string]$row.KeywordNotes,
        [string]$row.AudioNotes,
        [string]$row.FinalNotes
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Get-BetaIssueText($row) {
    $audioIssue = Get-Status $row.AudioIssue
    $audioIssueValue = if (-not [string]::IsNullOrWhiteSpace($audioIssue) -and $audioIssue -ne "none") {
        [string]$row.AudioIssue
    }
    else {
        ""
    }
    $issueText = @(
        [string]$row.StuckStep,
        $audioIssueValue,
        [string]$row.PageIssue,
        [string]$row.ContentIssue
    )

    return $issueText | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function New-ShortageRow([string]$Area, [string]$Gate, [int]$Current, [int]$Target) {
    $missing = [math]::Max(0, $Target - $Current)
    [pscustomobject]@{
        area = $Area
        gate = $Gate
        current = $Current
        target = $Target
        missing = $missing
    }
}

function New-MaximumRow([string]$Area, [string]$Gate, [int]$Current, [int]$Target) {
    $excess = [math]::Max(0, $Current - $Target)
    [pscustomobject]@{
        area = $Area
        gate = $Gate
        current = $Current
        target = $Target
        missing = $excess
    }
}

$contentRows = @()
if (Test-Path -LiteralPath $ContentReviewPath) {
    $contentRows = @(Import-Csv -LiteralPath $ContentReviewPath -Encoding UTF8)
}

$betaRows = @()
if (Test-Path -LiteralPath $BetaFeedbackPath) {
    $betaRows = @(Import-Csv -LiteralPath $BetaFeedbackPath -Encoding UTF8)
}

$contentPassRows = @($contentRows | Where-Object { (Get-Status $_.ReviewStatus) -eq "pass" })
$contentFixRows = @($contentRows | Where-Object {
    $status = Get-Status $_.ReviewStatus
    $status.StartsWith("fix_") -or $status -eq "remove"
})
$contentBlankRows = @($contentRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ReviewStatus) })

$scenePassCounts = @{}
foreach ($group in ($contentPassRows | Group-Object SceneCode)) {
    $scenePassCounts[$group.Name] = $group.Count
}

$levelPassCounts = @{}
foreach ($group in ($contentPassRows | Group-Object Level)) {
    $levelPassCounts[$group.Name] = $group.Count
}

$betaFilledRows = @($betaRows | Where-Object {
    -not [string]::IsNullOrWhiteSpace([string]$_.CompletedTest) -or
    -not [string]::IsNullOrWhiteSpace([string]$_.IndependentCompletion) -or
    -not [string]::IsNullOrWhiteSpace([string]$_.Notes)
})
$completedUsers = @($betaFilledRows | Where-Object { Test-Yes $_.CompletedTest })
$independentUsers = @($betaFilledRows | Where-Object { Test-Yes $_.IndependentCompletion })
$difficultyUnderstoodUsers = @($betaFilledRows | Where-Object { Test-PartialOrYes $_.UnderstandsDifficulty })
$willingNextUsers = @($betaFilledRows | Where-Object { Test-Yes $_.WillingNext })

$betaPriorityRows = @($betaFilledRows | Where-Object {
    $priority = Get-Priority $_.Priority
    @("P0", "P1", "P2") -contains $priority
})

$betaTriageRows = @($betaFilledRows | Where-Object {
    $priority = Get-Priority $_.Priority
    $issues = @(Get-BetaIssueText $_)
    [string]::IsNullOrWhiteSpace($priority) -and $issues.Count -gt 0
})

$shortages = New-Object System.Collections.Generic.List[object]
$shortages.Add((New-ShortageRow "Content" "total rows >= 120" $contentRows.Count 120))
$shortages.Add((New-ShortageRow "Content" "pass rows >= 100" $contentPassRows.Count 100))
$shortages.Add((New-MaximumRow "Content" "blank rows = 0" $contentBlankRows.Count 0))
$shortages.Add((New-MaximumRow "Content" "fix/remove rows = 0" $contentFixRows.Count 0))

foreach ($scene in @($contentRows | ForEach-Object { $_.SceneCode } | Sort-Object -Unique)) {
    $count = if ($scenePassCounts.ContainsKey($scene)) { [int]$scenePassCounts[$scene] } else { 0 }
    $shortages.Add((New-ShortageRow "Content" "scene $scene pass rows >= 15" $count 15))
}

foreach ($level in @("beginner", "intermediate", "advanced")) {
    $count = if ($levelPassCounts.ContainsKey($level)) { [int]$levelPassCounts[$level] } else { 0 }
    $shortages.Add((New-ShortageRow "Content" "level $level pass rows >= 15" $count 15))
}

$shortages.Add((New-ShortageRow "Beta" "completed users >= 5" $completedUsers.Count 5))
$shortages.Add((New-ShortageRow "Beta" "independent users >= 4" $independentUsers.Count 4))
$shortages.Add((New-ShortageRow "Beta" "difficulty understood users >= 4" $difficultyUnderstoodUsers.Count 4))
$shortages.Add((New-ShortageRow "Beta" "willing next users >= 3" $willingNextUsers.Count 3))
$p0Count = @($betaPriorityRows | Where-Object { (Get-Priority $_.Priority) -eq "P0" }).Count
$shortages.Add((New-MaximumRow "Beta" "P0 issues = 0" $p0Count 0))

$openShortages = @($shortages | Where-Object { $_.missing -gt 0 })

$contentIssueLines = if ($contentFixRows.Count -eq 0) {
    @("- No content fix/remove rows yet.")
}
else {
    @(
        "| Row | Status | Scene | Level | Sentence | Notes |",
        "| ---: | --- | --- | --- | --- | --- |"
    ) + @($contentFixRows | ForEach-Object {
        $notes = @(Get-ReviewNotes $_) -join "; "
        "| $($_.RowNumber) | $(ConvertTo-MarkdownText $_.ReviewStatus) | $(ConvertTo-MarkdownText $_.SceneCode) | $(ConvertTo-MarkdownText $_.Level) | $(ConvertTo-MarkdownText $_.Text) | $(ConvertTo-MarkdownText $notes) |"
    })
}

$priorityLines = if ($betaPriorityRows.Count -eq 0) {
    @("- No prioritized beta issues yet.")
}
else {
    @(
        "| Priority | User | Completed | Independent | Issue | Notes |",
        "| --- | --- | --- | --- | --- | --- |"
    ) + @($betaPriorityRows | Sort-Object @{ Expression = { Get-Priority $_.Priority } }, UserId | ForEach-Object {
        $issues = @(Get-BetaIssueText $_) -join "; "
        "| $(ConvertTo-MarkdownText (Get-Priority $_.Priority)) | $(ConvertTo-MarkdownText $_.UserId) | $(ConvertTo-MarkdownText $_.CompletedTest) | $(ConvertTo-MarkdownText $_.IndependentCompletion) | $(ConvertTo-MarkdownText $issues) | $(ConvertTo-MarkdownText $_.Notes) |"
    })
}

$triageLines = if ($betaTriageRows.Count -eq 0) {
    @("- No unprioritized beta issue notes yet.")
}
else {
    @(
        "| User | Completed | Independent | Issue |",
        "| --- | --- | --- | --- |"
    ) + @($betaTriageRows | ForEach-Object {
        $issues = @(Get-BetaIssueText $_) -join "; "
        "| $(ConvertTo-MarkdownText $_.UserId) | $(ConvertTo-MarkdownText $_.CompletedTest) | $(ConvertTo-MarkdownText $_.IndependentCompletion) | $(ConvertTo-MarkdownText $issues) |"
    })
}

$shortageLines = if ($openShortages.Count -eq 0) {
    @("- No gate shortages.")
}
else {
    @(
        "| Area | Gate | Current | Target | Missing |",
        "| --- | --- | ---: | ---: | ---: |"
    ) + @($openShortages | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.area) | $(ConvertTo-MarkdownText $_.gate) | $($_.current) | $($_.target) | $($_.missing) |"
    })
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# MVP Fix Plan",
    "",
    "Generated at: $generatedAt",
    "",
    "## Gate Shortages",
    ""
) + $shortageLines + @(
    "",
    "## Content Fixes",
    "",
    'Rows listed here come from `content/mvp-content-review.csv` where `ReviewStatus` is `fix_*` or `remove`.',
    ""
) + $contentIssueLines + @(
    "",
    "## Beta Issues",
    "",
    'Prioritized issues come from `feedback/internal-beta-feedback.csv` rows with `Priority` set to `P0`, `P1`, or `P2`.',
    ""
) + $priorityLines + @(
    "",
    "## Needs Triage",
    "",
    "These beta rows have issue notes but no priority yet.",
    ""
) + $triageLines + @(
    "",
    "## Finish Commands",
    "",
    '```powershell',
    '.\scripts\import-content-review-packets.ps1 -ValidateOnly',
    '.\scripts\import-content-review-packets.ps1 -RefreshArtifacts',
    '.\scripts\import-beta-feedback-packets.ps1 -ValidateOnly',
    '.\scripts\import-beta-feedback-packets.ps1 -RefreshArtifacts',
    '.\scripts\check-beta-feedback-session.ps1',
    '.\scripts\export-mvp-fix-plan.ps1',
    '.\scripts\export-first-version-handoff.ps1',
    '.\scripts\validate-first-version-handoff.ps1 -AssertValid',
    '.\scripts\export-first-version-progress.ps1',
    '.\scripts\check-local-beta-readiness.ps1',
    '.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady',
    '.\scripts\check-mvp-readiness.ps1 -IncludeBuild',
    '```'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    contentFixRows = $contentFixRows.Count
    contentBlankRows = $contentBlankRows.Count
    betaPriorityIssues = $betaPriorityRows.Count
    betaNeedsTriage = $betaTriageRows.Count
    openGateShortages = $openShortages.Count
} | ConvertTo-Json -Depth 6
