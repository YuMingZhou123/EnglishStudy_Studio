param(
    [string]$ContentReviewPath = "",
    [string]$BetaFeedbackPath = "",
    [string]$OutputPath = "",
    [string]$WebUrl = "http://localhost:3000",
    [string]$ApiUrl = "http://localhost:5180",
    [int]$ContentBatchSize = 20
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ContentReviewPath)) {
    $ContentReviewPath = Join-Path $RepoRoot "content\mvp-content-review.csv"
}

if ([string]::IsNullOrWhiteSpace($BetaFeedbackPath)) {
    $BetaFeedbackPath = Join-Path $RepoRoot "feedback\internal-beta-feedback.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\first-version-handoff.md"
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

function ConvertTo-FileUri([string]$path) {
    return ([System.Uri][System.IO.Path]::GetFullPath($path)).AbsoluteUri
}

function Get-MarkdownLink([string]$label, [string]$path) {
    if (-not (Test-Path -LiteralPath $path)) {
        return "missing"
    }

    return "[$label]($(ConvertTo-FileUri $path))"
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

function Get-Status($value) {
    return ([string]$value).Trim().ToLowerInvariant()
}

function Test-BetaFilled($row) {
    return -not [string]::IsNullOrWhiteSpace([string]$row.CompletedTest) -or
        -not [string]::IsNullOrWhiteSpace([string]$row.IndependentCompletion) -or
        -not [string]::IsNullOrWhiteSpace([string]$row.Notes)
}

function Get-BetaIssueText($row) {
    return @(
        [string]$row.StuckStep,
        [string]$row.AudioIssue,
        [string]$row.PageIssue,
        [string]$row.ContentIssue,
        [string]$row.Notes
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function New-ContentBatchRows($rows) {
    if ($ContentBatchSize -lt 1) {
        throw "ContentBatchSize must be greater than 0."
    }

    $batchCount = [math]::Ceiling($rows.Count / $ContentBatchSize)
    if ($batchCount -lt 1) {
        return @()
    }

    $batchItems = for ($index = 0; $index -lt $batchCount; $index++) {
        $start = ($index * $ContentBatchSize) + 1
        $end = [math]::Min(($index + 1) * $ContentBatchSize, $rows.Count)
        $batchRows = @($rows | Where-Object {
            $rowNumber = 0
            [int]::TryParse([string]$_.RowNumber, [ref]$rowNumber) -and
                $rowNumber -ge $start -and
                $rowNumber -le $end
        })
        $passRows = @($batchRows | Where-Object { (Get-Status $_.ReviewStatus) -eq "pass" })
        $fixRows = @($batchRows | Where-Object {
            $status = Get-Status $_.ReviewStatus
            $status.StartsWith("fix_") -or $status -eq "remove"
        })
        $blankRows = @($batchRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ReviewStatus) })
        $packetPath = Join-Path $RepoRoot ("content\review-packets\content-review-batch-{0:D3}-{1:D3}.md" -f $start, $end)
        $state = if ($blankRows.Count -gt 0) {
            "needs review"
        }
        elseif ($fixRows.Count -gt 0) {
            "needs fix"
        }
        else {
            "ready"
        }

        [pscustomobject]@{
            batch = "$start-$end"
            total = $batchRows.Count
            passRows = $passRows.Count
            fixRows = $fixRows.Count
            blankRows = $blankRows.Count
            state = $state
            packetPath = $packetPath
        }
    }

    return @($batchItems)
}

function New-BetaSlotRows($rows) {
    $slotItems = for ($index = 0; $index -lt $rows.Count; $index++) {
        $row = $rows[$index]
        $userId = [string]$row.UserId
        if ([string]::IsNullOrWhiteSpace($userId)) {
            $userId = "U{0:D2}" -f ($index + 1)
        }

        $filled = Test-BetaFilled $row
        $issueCount = @(Get-BetaIssueText $row).Count
        $priority = ([string]$row.Priority).Trim().ToUpperInvariant()
        $needsTriage = $filled -and $issueCount -gt 0 -and [string]::IsNullOrWhiteSpace($priority)
        $safeUserId = ($userId -replace "[^A-Za-z0-9_-]", "-")
        $packetPath = Join-Path $RepoRoot ("feedback\beta-feedback-packets\beta-feedback-{0}.md" -f $safeUserId)

        [pscustomobject]@{
            userId = $userId
            filled = $filled
            completedTest = [string]$row.CompletedTest
            independentCompletion = [string]$row.IndependentCompletion
            priority = $priority
            needsTriage = $needsTriage
            packetPath = $packetPath
        }
    }

    return @($slotItems)
}

$contentRows = if (Test-Path -LiteralPath $ContentReviewPath) {
    @(Import-Csv -LiteralPath $ContentReviewPath -Encoding UTF8)
}
else {
    @()
}

$betaRows = if (Test-Path -LiteralPath $BetaFeedbackPath) {
    @(Import-Csv -LiteralPath $BetaFeedbackPath -Encoding UTF8)
}
else {
    @()
}

$contentSummary = Invoke-JsonScript -ScriptName "summarize-content-review.ps1"
$betaSummary = Invoke-JsonScript -ScriptName "summarize-beta-feedback.ps1"
$fixPlan = Invoke-JsonScript -ScriptName "export-mvp-fix-plan.ps1"
$releaseGate = Invoke-JsonScript -ScriptName "export-first-version-release-gate.ps1"

$contentBatches = @(New-ContentBatchRows $contentRows)
$betaSlots = @(New-BetaSlotRows $betaRows)
$nextContentBatch = @($contentBatches | Where-Object { $_.blankRows -gt 0 } | Select-Object -First 1)
$nextBetaSlot = @($betaSlots | Where-Object { -not $_.filled } | Select-Object -First 1)
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$contentBatchLines = if ($contentBatches.Count -eq 0) {
    @('- Content review CSV is missing. Run `.\scripts\prepare-mvp-acceptance.ps1`.')
}
else {
    @(
        "| Batch | State | Pass | Fix/remove | Blank | Packet |",
        "| --- | --- | ---: | ---: | ---: | --- |"
    ) + @($contentBatches | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.batch) | $(ConvertTo-MarkdownText $_.state) | $($_.passRows) | $($_.fixRows) | $($_.blankRows) | $(Get-MarkdownLink 'Open' $_.packetPath) |"
    })
}

$betaSlotLines = if ($betaSlots.Count -eq 0) {
    @('- Beta feedback CSV is missing. Run `.\scripts\prepare-mvp-acceptance.ps1`.')
}
else {
    @(
        "| User | Filled | Completed | Independent | Priority | Needs triage | Packet |",
        "| --- | --- | --- | --- | --- | --- | --- |"
    ) + @($betaSlots | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.userId) | $($_.filled) | $(ConvertTo-MarkdownText $_.completedTest) | $(ConvertTo-MarkdownText $_.independentCompletion) | $(ConvertTo-MarkdownText $_.priority) | $($_.needsTriage) | $(Get-MarkdownLink 'Open' $_.packetPath) |"
    })
}

$nextContentLine = if ($nextContentBatch.Count -gt 0) {
    "- Next content review batch: $($nextContentBatch[0].batch) ($(Get-MarkdownLink 'open packet' $nextContentBatch[0].packetPath))"
}
else {
    "- Next content review batch: none"
}

$nextBetaLine = if ($nextBetaSlot.Count -gt 0) {
    "- Next beta tester slot: $($nextBetaSlot[0].userId) ($(Get-MarkdownLink 'open packet' $nextBetaSlot[0].packetPath))"
}
else {
    "- Next beta tester slot: none"
}

$failedGateLines = if ($releaseGate.failedGateNames.Count -eq 0) {
    @("- No failed gates.")
}
else {
    @($releaseGate.failedGateNames | ForEach-Object { "- $_" })
}

$lines = @(
    "# First Version Handoff",
    "",
    "Generated at: $generatedAt",
    "",
    "## Current Decision",
    "",
    "- Ready for release: $($releaseGate.readyForRelease)",
    "- Automated readiness: $($releaseGate.automatedReady)",
    "- Product review readiness: $($releaseGate.productReviewReady)",
    "- First version readiness: $($releaseGate.firstVersionReady)",
    "- Open gate shortages: $($fixPlan.openGateShortages)",
    "",
    "## Start Here",
    "",
    $nextContentLine,
    $nextBetaLine,
    '- Final release gate: `.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady`',
    "",
    "## Local Services",
    "",
    "- Web: [$WebUrl]($WebUrl)",
    "- API health: [$ApiUrl/health]($ApiUrl/health)",
    "- API ready: [$ApiUrl/health/ready]($ApiUrl/health/ready)",
    "- Admin: [$WebUrl/admin]($WebUrl/admin)",
    "",
    "## Test Accounts",
    "",
    '- Learner demo: `learner@example.com / Pass123$`',
    '- Admin demo: `admin@example.com / Admin123$`',
    "- Prefer a new self-registered learner account for each real beta tester.",
    "",
    "## Content Review Gate",
    "",
    "- Current pass rows: $($contentSummary.passRows)",
    "- Current blank rows: $($contentSummary.blankRows)",
    "- Current fix/remove rows: $($contentSummary.fixRows)",
    "- Required: at least 100 pass rows, 0 blank rows, 0 fix/remove rows, each scene and level above the minimum.",
    ""
) + $contentBatchLines + @(
    "",
    "## Beta Feedback Gate",
    "",
    "- Filled rows: $($betaSummary.filledRows)",
    "- Completed users: $($betaSummary.completedUsers)",
    "- Independent users: $($betaSummary.independentUsers)",
    "- Difficulty understood users: $($betaSummary.difficultyUnderstoodUsers)",
    "- Willing next users: $($betaSummary.willingNextUsers)",
    "- P0 issues: $($betaSummary.p0Issues)",
    "- Needs triage: $($fixPlan.betaNeedsTriage)",
    "- Required: at least 5 completed users, 4 independent users, 4 difficulty-understood users, 3 willing-next users, 0 P0 issues, 0 untriaged issue notes.",
    ""
) + $betaSlotLines + @(
    "",
    "## Guardrails",
    "",
    '- Do not mark content as `pass` until the sentence, translation, keywords, and audio have actually been reviewed.',
    "- Do not invent or copy beta feedback. Each filled tester row must come from a real session.",
    '- If a beta tester reports any issue, set `Priority` to `P0`, `P1`, or `P2` before trying the release gate.',
    "- After every import, regenerate the fix plan and release gate.",
    "",
    "## Import Commands",
    "",
    '```powershell',
    '.\scripts\import-content-review-packets.ps1 -ValidateOnly',
    '.\scripts\import-content-review-packets.ps1 -RefreshArtifacts',
    '.\scripts\import-beta-feedback-packets.ps1 -ValidateOnly',
    '.\scripts\import-beta-feedback-packets.ps1 -RefreshArtifacts',
    '.\scripts\export-mvp-fix-plan.ps1',
    '.\scripts\export-first-version-handoff.ps1',
    '.\scripts\validate-first-version-handoff.ps1 -AssertValid',
    '.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady',
    '```',
    "",
    "## Failed Release Gates",
    ""
) + $failedGateLines

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    readyForRelease = [bool]$releaseGate.readyForRelease
    automatedReady = [bool]$releaseGate.automatedReady
    productReviewReady = [bool]$releaseGate.productReviewReady
    firstVersionReady = [bool]$releaseGate.firstVersionReady
    contentBatchCount = $contentBatches.Count
    nextContentBatch = if ($nextContentBatch.Count -gt 0) { $nextContentBatch[0].batch } else { $null }
    betaSlotCount = $betaSlots.Count
    nextBetaSlot = if ($nextBetaSlot.Count -gt 0) { $nextBetaSlot[0].userId } else { $null }
    openGateShortages = $fixPlan.openGateShortages
    failedGateNames = @($releaseGate.failedGateNames)
} | ConvertTo-Json -Depth 8
