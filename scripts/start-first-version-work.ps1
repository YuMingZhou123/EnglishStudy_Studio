param(
    [string]$OutputPath = "",
    [switch]$IncludeReadiness,
    [switch]$Open
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\first-version-work-session.md"
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

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

function Invoke-JsonScript {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{}
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found: $scriptPath"
    }

    $output = & $scriptPath @Parameters 6>$null
    $text = $output | Out-String
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Script returned empty output: $ScriptName"
    }

    return $text | ConvertFrom-Json
}

function New-Action([string]$Name, [string]$Reason, [string]$Command, [string]$TargetPath) {
    [pscustomobject]@{
        name = $Name
        reason = $Reason
        command = $Command
        targetPath = $TargetPath
    }
}

$acceptanceParams = @{}
if (-not $IncludeReadiness) {
    $acceptanceParams.SkipReadiness = $true
}

$acceptance = Invoke-JsonScript -ScriptName "prepare-mvp-acceptance.ps1" -Parameters $acceptanceParams
$progress = $acceptance.progress
$releaseGate = $acceptance.releaseGate
$localBetaReadiness = $acceptance.localBetaReadiness
$handoffValidation = $acceptance.handoffValidation
$fixPlan = $acceptance.fixPlan
$content = $acceptance.contentReview.summary
$beta = $acceptance.betaFeedback.summary
$contentSession = $acceptance.contentReview.session
$betaSession = $acceptance.betaFeedback.session

$contentNeedsReview =
    -not [bool]$content.passesMinimumGate -or
    [int]$content.blankRows -gt 0 -or
    [int]$content.fixRows -gt 0
$betaNeedsFeedback = -not [bool]$beta.passesMinimumGate

$action = if ([bool]$releaseGate.readyForRelease) {
    New-Action `
        -Name "Run final release gate" `
        -Reason "All quick release gates are passing; finish with the full build gate." `
        -Command ".\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady" `
        -TargetPath (Join-Path $RepoRoot "acceptance\first-version-release-gate.md")
}
elseif (-not [bool]$releaseGate.automatedReady) {
    New-Action `
        -Name "Fix automated readiness" `
        -Reason "Engineering checks are not ready, so product review should wait." `
        -Command ".\scripts\check-mvp-readiness.ps1 -IncludeBuild" `
        -TargetPath (Join-Path $RepoRoot "acceptance\first-version-release-gate.md")
}
elseif (-not [bool]$handoffValidation.valid) {
    New-Action `
        -Name "Refresh handoff artifacts" `
        -Reason "Review and beta materials must be valid before sharing them." `
        -Command ".\scripts\prepare-mvp-acceptance.ps1 -SkipReadiness; .\scripts\validate-first-version-handoff.ps1 -AssertValid" `
        -TargetPath (Join-Path $RepoRoot "acceptance\first-version-handoff-validation.md")
}
elseif ($contentNeedsReview) {
    New-Action `
        -Name "Continue content review" `
        -Reason "Content still has $($content.blankRows) blank row(s), $($content.fixRows) fix/remove row(s), and $($content.passRows) pass row(s)." `
        -Command ".\scripts\start-content-review-batch.ps1 -Open" `
        -TargetPath $contentSession.outputPath
}
elseif ($betaNeedsFeedback) {
    New-Action `
        -Name "Run beta feedback session" `
        -Reason "Content review is ready, but beta feedback has $($beta.filledRows) filled row(s) and $($beta.completedUsers) completed user(s)." `
        -Command ".\scripts\start-beta-feedback-session.ps1 -Open" `
        -TargetPath $betaSession.outputPath
}
elseif ([int]$fixPlan.betaNeedsTriage -gt 0) {
    New-Action `
        -Name "Triage beta issues" `
        -Reason "Beta feedback has $($fixPlan.betaNeedsTriage) issue note(s) without a priority." `
        -Command ".\scripts\export-mvp-fix-plan.ps1" `
        -TargetPath (Join-Path $RepoRoot "acceptance\mvp-fix-plan.md")
}
else {
    New-Action `
        -Name "Run final release gate" `
        -Reason "Product review appears ready; finish with a full build and release gate assertion." `
        -Command ".\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady" `
        -TargetPath (Join-Path $RepoRoot "acceptance\first-version-release-gate.md")
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# First Version Work Session",
    "",
    "Generated at: $generatedAt",
    "",
    "## Next Action",
    "",
    "- Action: $($action.name)",
    "- Reason: $($action.reason)",
    ('- Command: `' + $action.command + '`'),
    "",
    "## Current Gates",
    "",
    "| Gate | Value |",
    "| --- | --- |",
    "| Ready for release | $($releaseGate.readyForRelease) |",
    "| Automated readiness | $($releaseGate.automatedReady) |",
    "| Product review readiness | $($releaseGate.productReviewReady) |",
    "| First version readiness | $($releaseGate.firstVersionReady) |",
    "| Handoff valid | $($handoffValidation.valid) |",
    "| Local beta review material ready | $($localBetaReadiness.reviewMaterialReady) |",
    "| Local beta session ready | $($localBetaReadiness.betaSessionReady) |",
    "| Open release shortages | $($fixPlan.openGateShortages) |",
    "",
    "## Content Review",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    "| Total rows | $($content.totalRows) |",
    "| Pass rows | $($content.passRows) |",
    "| Blank rows | $($content.blankRows) |",
    "| Fix/remove rows | $($content.fixRows) |",
    "| Minimum gate | $($content.passesMinimumGate) |",
    "| Next batch | $(ConvertTo-MarkdownText $progress.nextContentBatch) |",
    "",
    "## Beta Feedback",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    "| Filled rows | $($beta.filledRows) |",
    "| Completed users | $($beta.completedUsers) |",
    "| Independent users | $($beta.independentUsers) |",
    "| Difficulty understood users | $($beta.difficultyUnderstoodUsers) |",
    "| Willing next users | $($beta.willingNextUsers) |",
    "| P0 issues | $($beta.p0Issues) |",
    "| Needs triage | $($fixPlan.betaNeedsTriage) |",
    "| Minimum gate | $($beta.passesMinimumGate) |",
    "| Next slot | $(ConvertTo-MarkdownText $progress.nextBetaSlot) |",
    "",
    "## Useful Files",
    "",
    "- Work target: [open]($(ConvertTo-FileUri $action.targetPath))",
    "- Content review session: [open]($(ConvertTo-FileUri $contentSession.outputPath))",
    "- Beta feedback session: [open]($(ConvertTo-FileUri $betaSession.outputPath))",
    "- First version progress: [open]($(ConvertTo-FileUri $progress.outputPath))",
    "- First version handoff: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\first-version-handoff.md")))",
    "- Release gate: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\first-version-release-gate.md")))",
    "- Fix plan: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\mvp-fix-plan.md")))",
    "",
    "## Guardrails",
    "",
    '- Do not mark content rows as `pass` without real review.',
    "- Do not fill beta feedback without a real tester session.",
    "- Do not invite beta testers until content review has passed the minimum gate.",
    "",
    "## Commands",
    "",
    '```powershell',
    '.\scripts\start-first-version-work.ps1',
    '.\scripts\start-first-version-work.ps1 -Open',
    '.\scripts\check-mvp-readiness.ps1 -IncludeBuild',
    '.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady',
    '```'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

if ($Open) {
    Start-Process -FilePath $OutputPath
    if (-not [string]::IsNullOrWhiteSpace([string]$action.targetPath)) {
        Start-Process -FilePath $action.targetPath
    }
}

[pscustomobject]@{
    outputPath = $OutputPath
    action = $action.name
    command = $action.command
    reason = $action.reason
    targetPath = $action.targetPath
    readyForRelease = [bool]$releaseGate.readyForRelease
    automatedReady = [bool]$releaseGate.automatedReady
    productReviewReady = [bool]$releaseGate.productReviewReady
    firstVersionReady = [bool]$releaseGate.firstVersionReady
    contentBlankRows = $content.blankRows
    betaFilledRows = $beta.filledRows
    nextContentBatch = $progress.nextContentBatch
    nextBetaSlot = $progress.nextBetaSlot
    openGateShortages = $fixPlan.openGateShortages
} | ConvertTo-Json -Depth 6
