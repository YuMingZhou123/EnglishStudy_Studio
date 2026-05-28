param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\first-version-progress.md"
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

function New-ShortageLine([string]$Metric, [int]$Current, [int]$Target) {
    $missing = [math]::Max(0, $Target - $Current)
    return "| $(ConvertTo-MarkdownText $Metric) | $Current | $Target | $missing |"
}

function Get-NextLine([string]$Text, [string]$Prefix) {
    $line = @($Text -split "`r?`n" | Where-Object { $_.StartsWith($Prefix) } | Select-Object -First 1)
    if ($line.Count -eq 0) {
        return ""
    }

    return $line[0]
}

$content = Invoke-JsonScript -ScriptName "summarize-content-review.ps1"
$beta = Invoke-JsonScript -ScriptName "summarize-beta-feedback.ps1"
$fixPlan = Invoke-JsonScript -ScriptName "export-mvp-fix-plan.ps1"
$releaseGate = Invoke-JsonScript -ScriptName "export-first-version-release-gate.ps1"
$handoff = Invoke-JsonScript -ScriptName "export-first-version-handoff.ps1"
$handoffValidation = Invoke-JsonScript -ScriptName "validate-first-version-handoff.ps1"

$handoffTextPath = Join-Path $RepoRoot "acceptance\first-version-handoff.md"
$handoffText = if (Test-Path -LiteralPath $handoffTextPath) {
    Get-Content -LiteralPath $handoffTextPath -Raw -Encoding UTF8
}
else {
    ""
}

$nextContentLine = Get-NextLine $handoffText "- Next content review batch:"
$nextBetaLine = Get-NextLine $handoffText "- Next beta tester slot:"

$contentShortageLines = @(
    "| Metric | Current | Target | Missing |"
    "| --- | ---: | ---: | ---: |"
    (New-ShortageLine "pass rows" ([int]$content.passRows) 100)
    "| blank rows | $($content.blankRows) | 0 | $($content.blankRows) |"
    "| fix/remove rows | $($content.fixRows) | 0 | $($content.fixRows) |"
)

$betaShortageLines = @(
    "| Metric | Current | Target | Missing |"
    "| --- | ---: | ---: | ---: |"
    (New-ShortageLine "completed users" ([int]$beta.completedUsers) 5)
    (New-ShortageLine "independent users" ([int]$beta.independentUsers) 4)
    (New-ShortageLine "difficulty understood users" ([int]$beta.difficultyUnderstoodUsers) 4)
    (New-ShortageLine "willing next users" ([int]$beta.willingNextUsers) 3)
    "| P0 issues | $($beta.p0Issues) | 0 | $($beta.p0Issues) |"
    "| untriaged issue notes | $($fixPlan.betaNeedsTriage) | 0 | $($fixPlan.betaNeedsTriage) |"
)

$failedGateLines = if ($releaseGate.failedGateNames.Count -eq 0) {
    @("- No failed gates.")
}
else {
    @($releaseGate.failedGateNames | ForEach-Object { "- $_" })
}

$decision = if ([bool]$releaseGate.readyForRelease) {
    "Ready for release."
}
elseif (-not [bool]$releaseGate.automatedReady) {
    "Fix automated readiness failures first."
}
elseif (-not [bool]$handoffValidation.valid) {
    "Fix handoff artifact validation before sharing review materials."
}
else {
    "Engineering is ready; finish human content review and real beta feedback."
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# First Version Progress",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- $decision",
    "- Ready for release: $($releaseGate.readyForRelease)",
    "- Automated readiness: $($releaseGate.automatedReady)",
    "- Handoff valid: $($handoffValidation.valid)",
    "- Product review readiness: $($releaseGate.productReviewReady)",
    "- First version readiness: $($releaseGate.firstVersionReady)",
    "",
    "## Next Human Actions",
    "",
    $nextContentLine,
    $nextBetaLine,
    '- Do not mark content rows as `pass` without real review.',
    "- Do not fill beta feedback without a real tester session.",
    "",
    "## Content Review Progress",
    "",
    "- Total rows: $($content.totalRows)",
    "- Pass rows: $($content.passRows)",
    "- Blank rows: $($content.blankRows)",
    "- Fix/remove rows: $($content.fixRows)",
    "- Minimum gate: $($content.passesMinimumGate)",
    ""
) + $contentShortageLines + @(
    "",
    "## Beta Feedback Progress",
    "",
    "- Filled rows: $($beta.filledRows)",
    "- Completed users: $($beta.completedUsers)",
    "- Independent users: $($beta.independentUsers)",
    "- Difficulty understood users: $($beta.difficultyUnderstoodUsers)",
    "- Willing next users: $($beta.willingNextUsers)",
    "- P0 issues: $($beta.p0Issues)",
    "- Needs triage: $($fixPlan.betaNeedsTriage)",
    "- Minimum gate: $($beta.passesMinimumGate)",
    ""
) + $betaShortageLines + @(
    "",
    "## Release Gate",
    "",
    "- Passed gates: $($releaseGate.passedGates)",
    "- Failed gates: $($releaseGate.failedGates)",
    "- Open gate shortages: $($fixPlan.openGateShortages)",
    "",
    "Failed gates:",
    ""
) + $failedGateLines + @(
    "",
    "## Useful Files",
    "",
    "- Handoff: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\first-version-handoff.md")))",
    "- Handoff validation: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\first-version-handoff-validation.md")))",
    "- Local beta readiness: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\local-beta-readiness.md")))",
    "- Release gate: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\first-version-release-gate.md")))",
    "- Fix plan: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\mvp-fix-plan.md")))",
    "- Content review packets: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "content\review-packets\index.md")))",
    "- Beta feedback packets: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "feedback\beta-feedback-packets\index.md")))",
    "",
    "## Refresh Commands",
    "",
    '```powershell',
    '.\scripts\export-first-version-progress.ps1',
    '.\scripts\check-local-beta-readiness.ps1',
    '.\scripts\validate-first-version-handoff.ps1 -AssertValid',
    '.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady',
    '```'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    readyForRelease = [bool]$releaseGate.readyForRelease
    automatedReady = [bool]$releaseGate.automatedReady
    handoffValid = [bool]$handoffValidation.valid
    productReviewReady = [bool]$releaseGate.productReviewReady
    firstVersionReady = [bool]$releaseGate.firstVersionReady
    contentBlankRows = $content.blankRows
    betaFilledRows = $beta.filledRows
    nextContentBatch = $handoff.nextContentBatch
    nextBetaSlot = $handoff.nextBetaSlot
    openGateShortages = $fixPlan.openGateShortages
} | ConvertTo-Json -Depth 6
