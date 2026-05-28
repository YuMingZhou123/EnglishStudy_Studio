param(
    [string]$OutputPath = "",
    [switch]$IncludeBuild,
    [switch]$AssertReady
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\first-version-release-gate.md"
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

function ConvertTo-MarkdownText($value) {
    $text = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Replace("\", "\\").Replace("|", "\|").Replace("`r`n", "<br>").Replace("`n", "<br>")
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

function New-GateRow([string]$Name, [bool]$Passed, [string]$Evidence, [string]$Required) {
    [pscustomobject]@{
        name = $Name
        passed = $Passed
        evidence = $Evidence
        required = $Required
    }
}

function New-GateLine($gate) {
    $status = if ([bool]$gate.passed) { "pass" } else { "fail" }
    return "| $(ConvertTo-MarkdownText $gate.name) | $status | $(ConvertTo-MarkdownText $gate.evidence) | $(ConvertTo-MarkdownText $gate.required) |"
}

$git = Get-GitSnapshot

$readinessParams = if ($IncludeBuild) {
    @{ IncludeBuild = $true }
}
else {
    @{ SkipSmoke = $true; SkipUi = $true }
}
$readiness = Invoke-JsonScript -ScriptName "check-mvp-readiness.ps1" -Parameters $readinessParams
$content = $readiness.contentReview
$beta = $readiness.betaFeedback
$fixPlan = Invoke-JsonScript -ScriptName "export-mvp-fix-plan.ps1"

$p0Issues = 0
if ($null -ne $beta -and $beta.PSObject.Properties.Name -contains "p0Issues") {
    $p0Issues = [int]$beta.p0Issues
}

$gates = @(
    (New-GateRow "Git worktree clean" (-not [bool]$git.dirty) "dirty files: $($git.dirtyCount)" "0 dirty files")
    (New-GateRow "Automated readiness" ([bool]$readiness.automatedReady) "automatedReady: $($readiness.automatedReady)" "true")
    (New-GateRow "Product review readiness" ([bool]$readiness.productReviewReady) "productReviewReady: $($readiness.productReviewReady)" "true")
    (New-GateRow "First version readiness" ([bool]$readiness.firstVersionReady) "firstVersionReady: $($readiness.firstVersionReady)" "true")
    (New-GateRow "Content review gate" ([bool]$content.passesMinimumGate) "pass: $($content.passRows), fix: $($content.fixRows), blank: $($content.blankRows)" ">=100 pass, 0 fix, 0 blank, scene/level minimums met")
    (New-GateRow "Beta feedback gate" ([bool]$beta.passesMinimumGate) "filled: $($beta.filledRows), completed: $($beta.completedUsers), independent: $($beta.independentUsers)" ">=5 completed, >=4 independent, >=4 difficulty understood, >=3 willing next")
    (New-GateRow "No P0 beta issues" ($p0Issues -eq 0) "P0 issues: $p0Issues" "0")
    (New-GateRow "No open release shortages" ([int]$fixPlan.openGateShortages -eq 0) "open shortages: $($fixPlan.openGateShortages)" "0")
)

$passedGates = @($gates | Where-Object { [bool]$_.passed })
$failedGates = @($gates | Where-Object { -not [bool]$_.passed })
$readyForRelease = $failedGates.Count -eq 0
$mode = if ($IncludeBuild) { "full" } else { "quick" }
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$remoteText = if ([string]::IsNullOrWhiteSpace($git.upstream)) {
    "no upstream"
}
else {
    "ahead $($git.ahead), behind $($git.behind) vs $($git.upstream)"
}

$gateLines = @(
    "| Gate | Status | Evidence | Required |",
    "| --- | --- | --- | --- |"
) + @($gates | ForEach-Object { New-GateLine $_ })

$failedLines = if ($failedGates.Count -eq 0) {
    @("- No failed gates.")
}
else {
    @($failedGates | ForEach-Object { "- $($_.name): $($_.evidence)" })
}

$lines = @(
    "# First Version Release Gate",
    "",
    "Generated at: $generatedAt",
    "",
    "Mode: $mode",
    "",
    "## Decision",
    "",
    "- Ready for release: $readyForRelease",
    "",
    "## Git",
    "",
    "| Field | Value |",
    "| --- | --- |",
    "| Branch | $(ConvertTo-MarkdownText $git.branch) |",
    "| Commit | $(ConvertTo-MarkdownText $git.commit) |",
    "| Remote | $(ConvertTo-MarkdownText $remoteText) |",
    "| Dirty worktree | $($git.dirty) |",
    "| Dirty file count | $($git.dirtyCount) |",
    "",
    "## Gates",
    ""
) + $gateLines + @(
    "",
    "## Failed Gates",
    ""
) + $failedLines + @(
    "",
    "## Final Command",
    "",
    '```powershell',
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
    mode = $mode
    readyForRelease = $readyForRelease
    passedGates = $passedGates.Count
    failedGates = $failedGates.Count
    failedGateNames = @($failedGates | ForEach-Object { $_.name })
    branch = $git.branch
    commit = $git.commit
    dirty = [bool]$git.dirty
    automatedReady = [bool]$readiness.automatedReady
    productReviewReady = [bool]$readiness.productReviewReady
    firstVersionReady = [bool]$readiness.firstVersionReady
    contentBlankRows = $content.blankRows
    betaFilledRows = $beta.filledRows
    openGateShortages = $fixPlan.openGateShortages
}

if ($AssertReady -and -not $readyForRelease) {
    $result | ConvertTo-Json -Depth 8
    throw "First version release gate failed: $($result.failedGateNames -join ', ')"
}

$result | ConvertTo-Json -Depth 8
