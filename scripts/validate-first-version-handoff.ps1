param(
    [string]$OutputPath = "",
    [switch]$AssertValid
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\first-version-handoff-validation.md"
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

function ConvertTo-MarkdownText($value) {
    $text = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Replace("\", "\\").Replace("|", "\|").Replace("`r`n", "<br>").Replace("`n", "<br>")
}

function New-Check([string]$Name, [bool]$Passed, [string]$Evidence, [string]$Required) {
    [pscustomobject]@{
        name = $Name
        passed = $Passed
        evidence = $Evidence
        required = $Required
    }
}

function Test-FileExists([string]$Name, [string]$Path) {
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    New-Check $Name (Test-Path -LiteralPath $fullPath) $fullPath "file exists"
}

function Get-FileText([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
}

function Test-TextContains([string]$Name, [string]$Text, [string]$Pattern, [string]$Required) {
    New-Check $Name ($Text.Contains($Pattern)) $Pattern $Required
}

$paths = [ordered]@{
    dashboard = Join-Path $RepoRoot "acceptance\mvp-acceptance-dashboard.html"
    tasks = Join-Path $RepoRoot "acceptance\mvp-acceptance-tasks.md"
    fixPlan = Join-Path $RepoRoot "acceptance\mvp-fix-plan.md"
    releaseGate = Join-Path $RepoRoot "acceptance\first-version-release-gate.md"
    handoff = Join-Path $RepoRoot "acceptance\first-version-handoff.md"
    status = Join-Path $RepoRoot "acceptance\first-version-status.md"
    humanPlan = Join-Path $RepoRoot "acceptance\first-version-human-plan.md"
    localBetaRun = Join-Path $RepoRoot "acceptance\local-beta-run.md"
    localBetaReadiness = Join-Path $RepoRoot "acceptance\local-beta-readiness.md"
    contentPrecheck = Join-Path $RepoRoot "acceptance\content-precheck-report.md"
    contentReviewGateCheck = Join-Path $RepoRoot "acceptance\content-review-gate-check.md"
    contentReviewSession = Join-Path $RepoRoot "acceptance\content-review-session.md"
    betaFeedbackSession = Join-Path $RepoRoot "acceptance\beta-feedback-session.md"
    betaFeedbackGateCheck = Join-Path $RepoRoot "acceptance\beta-feedback-gate-check.md"
    contentReviewCsv = Join-Path $RepoRoot "content\mvp-content-review.csv"
    contentReviewHtml = Join-Path $RepoRoot "content\mvp-content-review.html"
    contentPacketIndex = Join-Path $RepoRoot "content\review-packets\index.md"
    betaFeedbackCsv = Join-Path $RepoRoot "feedback\internal-beta-feedback.csv"
    betaFeedbackHtml = Join-Path $RepoRoot "feedback\internal-beta-feedback.html"
    betaPacketIndex = Join-Path $RepoRoot "feedback\beta-feedback-packets\index.md"
}

$checks = New-Object System.Collections.Generic.List[object]

foreach ($entry in $paths.GetEnumerator()) {
    $checks.Add((Test-FileExists $entry.Key $entry.Value))
}

$contentRows = @()
if (Test-Path -LiteralPath $paths.contentReviewCsv) {
    $contentRows = @(Import-Csv -LiteralPath $paths.contentReviewCsv -Encoding UTF8)
}

$betaRows = @()
if (Test-Path -LiteralPath $paths.betaFeedbackCsv) {
    $betaRows = @(Import-Csv -LiteralPath $paths.betaFeedbackCsv -Encoding UTF8)
}

$contentPacketFiles = @()
$contentPacketDirectory = Join-Path $RepoRoot "content\review-packets"
if (Test-Path -LiteralPath $contentPacketDirectory) {
    $contentPacketFiles = @(Get-ChildItem -LiteralPath $contentPacketDirectory -Filter "content-review-batch-*.md")
}

$betaPacketFiles = @()
$betaPacketDirectory = Join-Path $RepoRoot "feedback\beta-feedback-packets"
if (Test-Path -LiteralPath $betaPacketDirectory) {
    $betaPacketFiles = @(Get-ChildItem -LiteralPath $betaPacketDirectory -Filter "beta-feedback-*.md")
}

$expectedContentPackets = if ($contentRows.Count -gt 0) {
    [math]::Ceiling($contentRows.Count / 20)
}
else {
    0
}

$checks.Add((New-Check "content review row count" ($contentRows.Count -ge 120) "rows: $($contentRows.Count)" ">=120"))
$checks.Add((New-Check "content packet count" ($contentPacketFiles.Count -ge $expectedContentPackets -and $expectedContentPackets -gt 0) "packets: $($contentPacketFiles.Count), expected: $expectedContentPackets" "one packet per 20 content rows"))
$checks.Add((New-Check "beta feedback row count" ($betaRows.Count -ge 10) "rows: $($betaRows.Count)" ">=10"))
$checks.Add((New-Check "beta packet count" ($betaPacketFiles.Count -ge $betaRows.Count -and $betaRows.Count -gt 0) "packets: $($betaPacketFiles.Count), rows: $($betaRows.Count)" "one packet per beta row"))

$handoffText = Get-FileText $paths.handoff
$tasksText = Get-FileText $paths.tasks
$dashboardText = Get-FileText $paths.dashboard
$statusText = Get-FileText $paths.status
$humanPlanText = Get-FileText $paths.humanPlan
$localBetaText = Get-FileText $paths.localBetaRun
$localBetaReadinessText = Get-FileText $paths.localBetaReadiness
$readmeText = Get-FileText (Join-Path $RepoRoot "README.md")

$checks.Add((Test-TextContains "handoff has next content batch" $handoffText "Next content review batch:" "handoff points to the next content review batch"))
$checks.Add((Test-TextContains "handoff has next beta slot" $handoffText "Next beta tester slot:" "handoff points to the next beta tester slot"))
$checks.Add((Test-TextContains "handoff has content precheck command" $handoffText "export-content-precheck-report.ps1" "handoff includes content precheck command"))
$checks.Add((Test-TextContains "handoff has start content review command" $handoffText "start-content-review-batch.ps1" "handoff includes content session command"))
$checks.Add((Test-TextContains "handoff has check content review command" $handoffText "check-content-review-batch.ps1" "handoff includes content review checker command"))
$checks.Add((Test-TextContains "handoff has content review gate command" $handoffText "check-content-review-gate.ps1" "handoff includes full content gate checker command"))
$checks.Add((Test-TextContains "handoff has start beta feedback command" $handoffText "start-beta-feedback-session.ps1" "handoff includes beta session command"))
$checks.Add((Test-TextContains "handoff has check beta feedback command" $handoffText "check-beta-feedback-session.ps1" "handoff includes beta feedback checker command"))
$checks.Add((Test-TextContains "handoff has beta feedback gate command" $handoffText "check-beta-feedback-gate.ps1" "handoff includes full beta feedback gate checker command"))
$checks.Add((Test-TextContains "handoff has final release command" $handoffText ".\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady" "handoff includes final release gate command"))
$checks.Add((Test-TextContains "handoff has guardrail against fake content pass" $handoffText 'Do not mark content as `pass`' "handoff warns against unreviewed pass marks"))
$checks.Add((Test-TextContains "handoff has guardrail against fake beta feedback" $handoffText "Do not invent or copy beta feedback" "handoff warns against fabricated feedback"))
$checks.Add((New-Check "handoff packet links resolved" (-not $handoffText.Contains("missing")) "missing marker present: $($handoffText.Contains('missing'))" "no missing packet links"))
$checks.Add((Test-TextContains "tasks link handoff" $tasksText "first-version-handoff.md" "acceptance tasks link handoff"))
$checks.Add((Test-TextContains "tasks link content review session" $tasksText "content-review-session.md" "acceptance tasks link content review session"))
$checks.Add((Test-TextContains "tasks link beta feedback session" $tasksText "beta-feedback-session.md" "acceptance tasks link beta feedback session"))
$checks.Add((Test-TextContains "tasks link content gate" $tasksText "content-review-gate-check.md" "acceptance tasks link content gate check"))
$checks.Add((Test-TextContains "tasks link beta gate" $tasksText "beta-feedback-gate-check.md" "acceptance tasks link beta gate check"))
$checks.Add((Test-TextContains "tasks link human plan" $tasksText "first-version-human-plan.md" "acceptance tasks link human execution plan"))
$checks.Add((Test-TextContains "dashboard links content gate" $dashboardText "content-review-gate-check.md" "acceptance dashboard links content gate check"))
$checks.Add((Test-TextContains "dashboard links beta gate" $dashboardText "beta-feedback-gate-check.md" "acceptance dashboard links beta gate check"))
$checks.Add((Test-TextContains "dashboard links human plan" $dashboardText "first-version-human-plan.md" "acceptance dashboard links human execution plan"))
$checks.Add((Test-TextContains "status links handoff" $statusText "first-version-handoff.md" "status report links handoff"))
$checks.Add((Test-TextContains "human plan has content queue" $humanPlanText "## Content Review Queue" "human plan includes content review queue"))
$checks.Add((Test-TextContains "human plan has beta queue" $humanPlanText "## Beta Feedback Queue" "human plan includes beta feedback queue"))
$checks.Add((Test-TextContains "human plan guards beta invite order" $humanPlanText "Do not invite beta testers before content review passes the gate." "human plan preserves content-before-beta guardrail"))
$checks.Add((Test-TextContains "local beta run links handoff" $localBetaText "first-version-handoff.md" "local beta runbook links handoff"))
$checks.Add((Test-TextContains "local beta run links readiness" $localBetaText "local-beta-readiness.md" "local beta runbook links readiness"))
$checks.Add((Test-TextContains "local beta readiness has decision" $localBetaReadinessText "## Decision" "readiness report has decision section"))
$checks.Add((Test-TextContains "local beta readiness preserves content gate" $localBetaReadinessText "Content ready for beta testers" "readiness report checks content gate before beta"))
$checks.Add((Test-TextContains "local beta readiness links content gate" $localBetaReadinessText "content-review-gate-check.md" "local beta readiness links content gate check"))
$checks.Add((Test-TextContains "local beta readiness links beta gate" $localBetaReadinessText "beta-feedback-gate-check.md" "local beta readiness links beta gate check"))
$checks.Add((Test-TextContains "readme mentions handoff" $readmeText "export-first-version-handoff.ps1" "README lists handoff command"))
$checks.Add((Test-TextContains "readme mentions local beta readiness" $readmeText "check-local-beta-readiness.ps1" "README lists local beta readiness command"))
$checks.Add((Test-TextContains "readme mentions beta session" $readmeText "start-beta-feedback-session.ps1" "README lists beta session command"))
$checks.Add((Test-TextContains "readme mentions beta session checker" $readmeText "check-beta-feedback-session.ps1" "README lists beta session checker command"))
$checks.Add((Test-TextContains "readme mentions beta feedback gate checker" $readmeText "check-beta-feedback-gate.ps1" "README lists full beta feedback gate checker command"))
$checks.Add((Test-TextContains "readme mentions content batch checker" $readmeText "check-content-review-batch.ps1" "README lists content batch checker command"))
$checks.Add((Test-TextContains "readme mentions content precheck" $readmeText "export-content-precheck-report.ps1" "README lists content precheck command"))
$checks.Add((Test-TextContains "readme mentions content review gate checker" $readmeText "check-content-review-gate.ps1" "README lists full content gate checker command"))
$checks.Add((Test-TextContains "readme mentions human plan" $readmeText "export-first-version-human-plan.ps1" "README lists human execution plan command"))

$failedChecks = @($checks | Where-Object { -not [bool]$_.passed })
$passedChecks = @($checks | Where-Object { [bool]$_.passed })
$valid = $failedChecks.Count -eq 0
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$checkLines = New-Object System.Collections.Generic.List[string]
$checkLines.Add("| Check | Status | Evidence | Required |")
$checkLines.Add("| --- | --- | --- | --- |")
foreach ($check in $checks) {
    $status = if ([bool]$check.passed) { "pass" } else { "fail" }
    $checkLines.Add("| $(ConvertTo-MarkdownText $check.name) | $status | $(ConvertTo-MarkdownText $check.evidence) | $(ConvertTo-MarkdownText $check.required) |")
}

$failedLines = if ($failedChecks.Count -eq 0) {
    @("- No failed checks.")
}
else {
    @($failedChecks | ForEach-Object { "- $($_.name): $($_.evidence)" })
}

$lines = @(
    "# First Version Handoff Validation"
    ""
    "Generated at: $generatedAt"
    ""
    "## Decision"
    ""
    "- Handoff valid: $valid"
    "- Passed checks: $($passedChecks.Count)"
    "- Failed checks: $($failedChecks.Count)"
    ""
    "## Checks"
    ""
) + $checkLines + @(
    ""
    "## Failed Checks"
    ""
) + $failedLines + @(
    ""
    "## Refresh Commands"
    ""
    '```powershell'
    '.\scripts\prepare-mvp-acceptance.ps1 -SkipReadiness'
    '.\scripts\export-first-version-handoff.ps1'
    '.\scripts\validate-first-version-handoff.ps1 -AssertValid'
    '```'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

$result = [pscustomobject]@{
    outputPath = $OutputPath
    valid = $valid
    passedChecks = $passedChecks.Count
    failedChecks = $failedChecks.Count
    failedCheckNames = @($failedChecks | ForEach-Object { $_.name })
    contentReviewRows = $contentRows.Count
    contentPacketCount = $contentPacketFiles.Count
    betaFeedbackRows = $betaRows.Count
    betaPacketCount = $betaPacketFiles.Count
}

if ($AssertValid -and -not $valid) {
    $result | ConvertTo-Json -Depth 8
    throw "First version handoff validation failed: $($result.failedCheckNames -join ', ')"
}

$result | ConvertTo-Json -Depth 8
