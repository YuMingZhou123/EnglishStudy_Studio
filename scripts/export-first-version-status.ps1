param(
    [string]$OutputPath = "",
    [switch]$SkipReadiness
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\first-version-status.md"
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

function Invoke-Git {
    param([string[]]$Arguments)

    $output = & git @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return ""
    }

    return ($output | Out-String).Trim()
}

function Get-GitSnapshot {
    $branch = Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD")
    $commit = Invoke-Git @("rev-parse", "--short", "HEAD")
    $upstream = Invoke-Git @("rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}")
    $ahead = ""
    $behind = ""

    if (-not [string]::IsNullOrWhiteSpace($upstream)) {
        $ahead = Invoke-Git @("rev-list", "--count", "$upstream..HEAD")
        $behind = Invoke-Git @("rev-list", "--count", "HEAD..$upstream")
    }

    $statusLines = @(& git status --short 2>$null)
    if ($LASTEXITCODE -ne 0) {
        $statusLines = @()
    }

    return [pscustomobject]@{
        branch = $branch
        commit = $commit
        upstream = $upstream
        ahead = $ahead
        behind = $behind
        dirty = $statusLines.Count -gt 0
        dirtyCount = $statusLines.Count
    }
}

function New-ReadyText($value) {
    if ($null -eq $value) {
        return "skipped"
    }

    if ([bool]$value) {
        return "true"
    }

    return "false"
}

function New-Decision($readiness, $content, $beta) {
    if ($null -ne $readiness -and [bool]$readiness.firstVersionReady) {
        return "First version is ready to mark complete after final full build check."
    }

    if ($null -ne $readiness -and -not [bool]$readiness.automatedReady) {
        return "Engineering gates are not ready. Fix automated readiness failures first."
    }

    if (-not [bool]$content.passesMinimumGate -and -not [bool]$beta.passesMinimumGate) {
        return "Engineering is ready for review, but content review and beta feedback are still missing."
    }

    if (-not [bool]$content.passesMinimumGate) {
        return "Beta feedback may be close, but content review is not ready."
    }

    if (-not [bool]$beta.passesMinimumGate) {
        return "Content review may be close, but beta feedback is not ready."
    }

    return "Product review appears ready. Run full readiness with -IncludeBuild before calling the first version complete."
}

function New-LinkLine([string]$Label, [string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        return "- ${Label}: [open]($(ConvertTo-FileUri $Path))"
    }

    return "- ${Label}: missing ($Path)"
}

$git = Get-GitSnapshot
$readiness = if ($SkipReadiness) {
    $null
}
else {
    Invoke-JsonScript -ScriptName "check-mvp-readiness.ps1" -Parameters @{ SkipSmoke = $true; SkipUi = $true }
}

$content = Invoke-JsonScript -ScriptName "summarize-content-review.ps1"
$beta = Invoke-JsonScript -ScriptName "summarize-beta-feedback.ps1"
$fixPlan = Invoke-JsonScript -ScriptName "export-mvp-fix-plan.ps1"

$decision = New-Decision $readiness $content $beta
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$readinessLines = if ($SkipReadiness) {
    @("- Readiness check skipped for this report.")
}
else {
    @(
        "| Gate | Value |",
        "| --- | --- |",
        "| automatedReady | $(New-ReadyText $readiness.automatedReady) |",
        "| productReviewReady | $(New-ReadyText $readiness.productReviewReady) |",
        "| firstVersionReady | $(New-ReadyText $readiness.firstVersionReady) |"
    )
}

$artifactLines = @(
    (New-LinkLine "Acceptance dashboard" (Join-Path $RepoRoot "acceptance\mvp-acceptance-dashboard.html"))
    (New-LinkLine "Acceptance tasks" (Join-Path $RepoRoot "acceptance\mvp-acceptance-tasks.md"))
    (New-LinkLine "Fix plan" (Join-Path $RepoRoot "acceptance\mvp-fix-plan.md"))
    (New-LinkLine "Release gate" (Join-Path $RepoRoot "acceptance\first-version-release-gate.md"))
    (New-LinkLine "First version handoff" (Join-Path $RepoRoot "acceptance\first-version-handoff.md"))
    (New-LinkLine "Handoff validation" (Join-Path $RepoRoot "acceptance\first-version-handoff-validation.md"))
    (New-LinkLine "First version progress" (Join-Path $RepoRoot "acceptance\first-version-progress.md"))
    (New-LinkLine "Local beta runbook" (Join-Path $RepoRoot "acceptance\local-beta-run.md"))
    (New-LinkLine "Content review desk" (Join-Path $RepoRoot "content\mvp-content-review.html"))
    (New-LinkLine "Content review packets" (Join-Path $RepoRoot "content\review-packets\index.md"))
    (New-LinkLine "Beta feedback desk" (Join-Path $RepoRoot "feedback\internal-beta-feedback.html"))
    (New-LinkLine "Beta feedback packets" (Join-Path $RepoRoot "feedback\beta-feedback-packets\index.md"))
)

$gitAheadText = if ([string]::IsNullOrWhiteSpace($git.upstream)) {
    "no upstream"
}
else {
    "ahead $($git.ahead), behind $($git.behind) vs $($git.upstream)"
}

$lines = @(
    "# First Version Status",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- $decision",
    "",
    "## Git",
    "",
    "| Field | Value |",
    "| --- | --- |",
    "| Branch | $(ConvertTo-MarkdownText $git.branch) |",
    "| Commit | $(ConvertTo-MarkdownText $git.commit) |",
    "| Remote | $(ConvertTo-MarkdownText $gitAheadText) |",
    "| Dirty worktree | $($git.dirty) |",
    "| Dirty file count | $($git.dirtyCount) |",
    "",
    "## Readiness",
    ""
) + $readinessLines + @(
    "",
    "## Content Review",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    "| Total rows | $($content.totalRows) |",
    "| Pass rows | $($content.passRows) |",
    "| Fix/remove rows | $($content.fixRows) |",
    "| Blank rows | $($content.blankRows) |",
    "| Minimum gate | $($content.passesMinimumGate) |",
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
    "| P1 issues | $($beta.p1Issues) |",
    "| Minimum gate | $($beta.passesMinimumGate) |",
    "",
    "## Fix Plan",
    "",
    "| Metric | Value |",
    "| --- | ---: |",
    "| Content fix rows | $($fixPlan.contentFixRows) |",
    "| Content blank rows | $($fixPlan.contentBlankRows) |",
    "| Beta priority issues | $($fixPlan.betaPriorityIssues) |",
    "| Beta needs triage | $($fixPlan.betaNeedsTriage) |",
    "| Open gate shortages | $($fixPlan.openGateShortages) |",
    "",
    "## Artifacts",
    ""
) + $artifactLines + @(
    "",
    "## Next Actions",
    "",
    '- Complete content review and import it with `.\scripts\import-content-review-packets.ps1 -RefreshArtifacts` or `.\scripts\import-acceptance-csv.ps1 -Kind content -RefreshArtifacts`.',
    '- Complete beta feedback and import it with `.\scripts\import-beta-feedback-packets.ps1 -RefreshArtifacts` or `.\scripts\import-acceptance-csv.ps1 -Kind beta -RefreshArtifacts`.',
    '- Use `.\scripts\export-mvp-fix-plan.ps1` after each import to review remaining fixes.',
    '- Use `.\scripts\export-first-version-handoff.ps1` to refresh the review and beta handoff queue.',
    '- Run `.\scripts\validate-first-version-handoff.ps1 -AssertValid` before sharing handoff files.',
    '- Run `.\scripts\export-first-version-progress.ps1` to refresh the compact progress brief.',
    '- Run `.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady` as the final release gate.',
    '- Run `.\scripts\check-mvp-readiness.ps1 -IncludeBuild` before declaring the first version complete.'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    decision = $decision
    branch = $git.branch
    commit = $git.commit
    dirty = $git.dirty
    automatedReady = if ($SkipReadiness) { $null } else { [bool]$readiness.automatedReady }
    productReviewReady = if ($SkipReadiness) { $null } else { [bool]$readiness.productReviewReady }
    firstVersionReady = if ($SkipReadiness) { $null } else { [bool]$readiness.firstVersionReady }
    contentPassRows = $content.passRows
    contentBlankRows = $content.blankRows
    betaFilledRows = $beta.filledRows
    openGateShortages = $fixPlan.openGateShortages
} | ConvertTo-Json -Depth 6
