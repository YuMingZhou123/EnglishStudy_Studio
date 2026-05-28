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
    '.\scripts\import-beta-feedback-packets.ps1 -ValidateOnly',
    '.\scripts\import-beta-feedback-packets.ps1 -RefreshArtifacts',
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
