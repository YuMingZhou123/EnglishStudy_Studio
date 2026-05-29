param(
    [string]$OutputPath = "",
    [int]$BatchSize = 20
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\acceptance\mvp-acceptance-tasks.md"
}

if ($BatchSize -lt 1) {
    throw "BatchSize must be greater than 0."
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$contentReviewPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\content\mvp-content-review.csv"))
$contentReviewHtmlPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\content\mvp-content-review.html"))
$betaFeedbackPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv"))
$betaFeedbackHtmlPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.html"))
$betaFeedbackPacketDirectory = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\feedback\beta-feedback-packets"))
$dashboardPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\mvp-acceptance-dashboard.html"))
$contentReviewSessionPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\content-review-session.md"))
$contentPrecheckPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\content-precheck-report.md"))
$contentGateCheckPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\content-review-gate-check.md"))
$betaFeedbackSessionPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\beta-feedback-session.md"))
$betaGateCheckPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\beta-feedback-gate-check.md"))
$fixPlanPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\mvp-fix-plan.md"))
$statusReportPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\first-version-status.md"))
$releaseGatePath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\first-version-release-gate.md"))
$handoffPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\first-version-handoff.md"))
$handoffValidationPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\first-version-handoff-validation.md"))
$progressPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\first-version-progress.md"))
$humanPlanPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\first-version-human-plan.md"))
$localBetaReadinessPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\acceptance\local-beta-readiness.md"))

function ConvertTo-FileUri([string]$path) {
    return ([System.Uri][System.IO.Path]::GetFullPath($path)).AbsoluteUri
}

function ConvertTo-FileUriWithQuery([string]$path, [hashtable]$Query = @{}) {
    $uri = ConvertTo-FileUri $path
    if ($Query.Count -eq 0) {
        return $uri
    }

    $pairs = foreach ($key in ($Query.Keys | Sort-Object)) {
        $escapedKey = [System.Uri]::EscapeDataString([string]$key)
        $escapedValue = [System.Uri]::EscapeDataString([string]$Query[$key])
        "$escapedKey=$escapedValue"
    }

    return "${uri}?$($pairs -join '&')"
}

function Get-Status($value) {
    return ([string]$value).Trim().ToLowerInvariant()
}

function Test-BetaFilled($row) {
    return -not [string]::IsNullOrWhiteSpace([string]$row.CompletedTest) -or
        -not [string]::IsNullOrWhiteSpace([string]$row.IndependentCompletion) -or
        -not [string]::IsNullOrWhiteSpace([string]$row.Notes)
}

function Get-MarkdownLink([string]$label, [string]$href) {
    return "[$label]($href)"
}

$contentRows = @()
if (Test-Path -LiteralPath $contentReviewPath) {
    $contentRows = @(Import-Csv -LiteralPath $contentReviewPath -Encoding UTF8)
}

$betaRows = @()
if (Test-Path -LiteralPath $betaFeedbackPath) {
    $betaRows = @(Import-Csv -LiteralPath $betaFeedbackPath -Encoding UTF8)
}

$contentBatches = @()
if ($contentRows.Count -gt 0) {
    $batchCount = [math]::Ceiling($contentRows.Count / $BatchSize)
    for ($index = 0; $index -lt $batchCount; $index++) {
        $start = ($index * $BatchSize) + 1
        $end = [math]::Min(($index + 1) * $BatchSize, $contentRows.Count)
        $batchRows = @($contentRows | Where-Object {
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
        $batchStatus = if ($blankRows.Count -gt 0) {
            "review"
        }
        elseif ($fixRows.Count -gt 0) {
            "fix"
        }
        else {
            "done"
        }
        $linkStatus = if ($batchStatus -eq "review") { "blank" } elseif ($batchStatus -eq "fix") { "fix" } else { "" }
        $query = @{ batch = "$start-$end" }
        if (-not [string]::IsNullOrWhiteSpace($linkStatus)) {
            $query.status = $linkStatus
        }

        $contentBatches += [pscustomobject]@{
            batch = "$start-$end"
            status = $batchStatus
            totalRows = $batchRows.Count
            passRows = $passRows.Count
            fixRows = $fixRows.Count
            blankRows = $blankRows.Count
            link = ConvertTo-FileUriWithQuery $contentReviewHtmlPath $query
        }
    }
}

$betaTasks = @()
foreach ($row in $betaRows) {
    $userId = if ([string]::IsNullOrWhiteSpace([string]$row.UserId)) { "unknown" } else { [string]$row.UserId }
    $safeUserId = ($userId -replace "[^A-Za-z0-9_-]", "-")
    $packetPath = Join-Path $betaFeedbackPacketDirectory ("beta-feedback-{0}.md" -f $safeUserId)
    $filled = Test-BetaFilled $row
    $completed = (Get-Status $row.CompletedTest) -eq "yes"
    $status = if (-not $filled) {
        "record"
    }
    elseif (-not $completed) {
        "follow_up"
    }
    else {
        "done"
    }
    $query = @{ user = $userId }
    if (-not $filled) {
        $query.status = "blank"
    }

    $betaTasks += [pscustomobject]@{
        userId = $userId
        status = $status
        completedTest = [string]$row.CompletedTest
        independentCompletion = [string]$row.IndependentCompletion
        priority = [string]$row.Priority
        link = ConvertTo-FileUriWithQuery $betaFeedbackHtmlPath $query
        packetLink = if (Test-Path -LiteralPath $packetPath) { ConvertTo-FileUri $packetPath } else { "" }
    }
}

$contentPassRows = @($contentRows | Where-Object { (Get-Status $_.ReviewStatus) -eq "pass" })
$contentFixRows = @($contentRows | Where-Object {
    $status = Get-Status $_.ReviewStatus
    $status.StartsWith("fix_") -or $status -eq "remove"
})
$contentBlankRows = @($contentRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ReviewStatus) })
$betaFilledRows = @($betaRows | Where-Object { Test-BetaFilled $_ })
$betaCompletedUsers = @($betaRows | Where-Object { (Get-Status $_.CompletedTest) -eq "yes" })
$betaP0Issues = @($betaRows | Where-Object { (Get-Status $_.Priority) -eq "p0" })
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$dashboardLink = Get-MarkdownLink "Open dashboard" (ConvertTo-FileUri $dashboardPath)
$contentReviewSessionLink = Get-MarkdownLink "Open content review session" (ConvertTo-FileUri $contentReviewSessionPath)
$contentPrecheckLink = Get-MarkdownLink "Open content precheck" (ConvertTo-FileUri $contentPrecheckPath)
$contentGateCheckLink = Get-MarkdownLink "Open content gate check" (ConvertTo-FileUri $contentGateCheckPath)
$betaFeedbackSessionLink = Get-MarkdownLink "Open beta feedback session" (ConvertTo-FileUri $betaFeedbackSessionPath)
$betaGateCheckLink = Get-MarkdownLink "Open beta gate check" (ConvertTo-FileUri $betaGateCheckPath)
$fixPlanLink = Get-MarkdownLink "Open fix plan" (ConvertTo-FileUri $fixPlanPath)
$statusReportLink = Get-MarkdownLink "Open status" (ConvertTo-FileUri $statusReportPath)
$releaseGateLink = Get-MarkdownLink "Open release gate" (ConvertTo-FileUri $releaseGatePath)
$handoffLink = Get-MarkdownLink "Open handoff" (ConvertTo-FileUri $handoffPath)
$handoffValidationLink = Get-MarkdownLink "Open handoff validation" (ConvertTo-FileUri $handoffValidationPath)
$progressLink = Get-MarkdownLink "Open progress" (ConvertTo-FileUri $progressPath)
$humanPlanLink = Get-MarkdownLink "Open human execution plan" (ConvertTo-FileUri $humanPlanPath)
$localBetaReadinessLink = Get-MarkdownLink "Open local beta readiness" (ConvertTo-FileUri $localBetaReadinessPath)

$contentTable = if ($contentBatches.Count -eq 0) {
    @('- Content review sheet is missing. Run `.\scripts\export-content-review-sheet.ps1` first.')
}
else {
    @(
        "| Batch | Status | Pass | Fix | Blank | Action |",
        "| --- | --- | ---: | ---: | ---: | --- |"
    ) + @($contentBatches | ForEach-Object {
        $link = Get-MarkdownLink "Open" $_.link
        "| $($_.batch) | $($_.status) | $($_.passRows) | $($_.fixRows) | $($_.blankRows) | $link |"
    })
}

$betaTable = if ($betaTasks.Count -eq 0) {
    @('- Beta feedback sheet is missing. Run `.\scripts\export-beta-feedback-template.ps1` first.')
}
else {
    @(
        "| User | Status | Completed | Independent | Priority | Action | Packet |",
        "| --- | --- | --- | --- | --- | --- | --- |"
    ) + @($betaTasks | ForEach-Object {
        $link = Get-MarkdownLink "Open" $_.link
        $packetLink = if ([string]::IsNullOrWhiteSpace([string]$_.packetLink)) { "" } else { Get-MarkdownLink "Packet" $_.packetLink }
        "| $($_.userId) | $($_.status) | $($_.completedTest) | $($_.independentCompletion) | $($_.priority) | $link | $packetLink |"
    })
}

$lines = @(
    "# MVP Acceptance Tasks",
    "",
    "Generated at: $generatedAt",
    "",
    "Dashboard: $dashboardLink",
    "",
    "Content review session: $contentReviewSessionLink",
    "",
    "Content precheck: $contentPrecheckLink",
    "",
    "Content gate check: $contentGateCheckLink",
    "",
    "Beta feedback session: $betaFeedbackSessionLink",
    "",
    "Beta gate check: $betaGateCheckLink",
    "",
    "Fix plan: $fixPlanLink",
    "",
    "First version status: $statusReportLink",
    "",
    "Release gate: $releaseGateLink",
    "",
    "First version handoff: $handoffLink",
    "",
    "Handoff validation: $handoffValidationLink",
    "",
    "First version progress: $progressLink",
    "",
    "Human execution plan: $humanPlanLink",
    "",
    "Local beta readiness: $localBetaReadinessLink",
    "",
    "## Current Gates",
    "",
    "- Content review: $($contentPassRows.Count) pass, $($contentFixRows.Count) fix/remove, $($contentBlankRows.Count) blank, total $($contentRows.Count).",
    "- Beta feedback: $($betaFilledRows.Count) filled, $($betaCompletedUsers.Count) completed, $($betaP0Issues.Count) P0 issues, total $($betaRows.Count).",
    "",
    "## Content Review Batches",
    ""
) + $contentTable + @(
    "",
    "## Beta Feedback Tasks",
    ""
) + $betaTable + @(
    "",
    "## Finish Commands",
    "",
    '```powershell',
    '.\scripts\import-acceptance-csv.ps1 -Kind content -ValidateOnly',
    '.\scripts\import-acceptance-csv.ps1 -Kind content -RefreshArtifacts',
    '.\scripts\start-content-review-batch.ps1',
    '.\scripts\check-content-review-gate.ps1',
    '.\scripts\start-beta-feedback-session.ps1',
    '.\scripts\check-beta-feedback-gate.ps1',
    '.\scripts\import-beta-feedback-packets.ps1 -ValidateOnly',
    '.\scripts\import-beta-feedback-packets.ps1 -RefreshArtifacts',
    '.\scripts\export-mvp-fix-plan.ps1',
    '.\scripts\export-first-version-status.ps1',
    '.\scripts\export-first-version-handoff.ps1',
    '.\scripts\validate-first-version-handoff.ps1 -AssertValid',
    '.\scripts\export-first-version-progress.ps1',
    '.\scripts\export-first-version-human-plan.ps1',
    '.\scripts\check-local-beta-readiness.ps1',
    '.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady',
    '.\scripts\import-acceptance-csv.ps1 -Kind beta -ValidateOnly',
    '.\scripts\import-acceptance-csv.ps1 -Kind beta -RefreshArtifacts',
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
    contentBatches = $contentBatches.Count
    betaTasks = $betaTasks.Count
    contentBlankRows = $contentBlankRows.Count
    betaFilledRows = $betaFilledRows.Count
} | ConvertTo-Json -Depth 5
