param(
    [string]$FeedbackPath = "",
    [string]$UserId = "",
    [string]$OutputPath = "",
    [string]$WebUrl = "http://localhost:3000",
    [string]$ApiUrl = "http://localhost:5180",
    [switch]$Open
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($FeedbackPath)) {
    $FeedbackPath = Join-Path $RepoRoot "feedback\internal-beta-feedback.csv"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\beta-feedback-session.md"
}

$FeedbackPath = [System.IO.Path]::GetFullPath($FeedbackPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

if (-not (Test-Path -LiteralPath $FeedbackPath)) {
    throw "Feedback file not found: $FeedbackPath. Run .\scripts\prepare-mvp-acceptance.ps1 first."
}

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

function Get-FieldValue($row, [string]$fieldName) {
    if ($null -eq $row) {
        return ""
    }

    $property = $row.PSObject.Properties[$fieldName]
    if ($null -eq $property) {
        return ""
    }

    return [string]$property.Value
}

function Test-BetaFilled($row) {
    return -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "CompletedTest")) -or
        -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "IndependentCompletion")) -or
        -not [string]::IsNullOrWhiteSpace((Get-FieldValue $row "Notes"))
}

function Get-BetaIssueText($row) {
    return @(
        (Get-FieldValue $row "StuckStep"),
        (Get-FieldValue $row "AudioIssue"),
        (Get-FieldValue $row "PageIssue"),
        (Get-FieldValue $row "ContentIssue"),
        (Get-FieldValue $row "Notes")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function New-NormalizedRow($row, [int]$Index) {
    $resolvedUserId = Get-FieldValue $row "UserId"
    if ([string]::IsNullOrWhiteSpace($resolvedUserId)) {
        $resolvedUserId = "U{0:D2}" -f ($Index + 1)
    }

    return [pscustomobject]@{
        row = $row
        index = $Index
        userId = $resolvedUserId
        filled = Test-BetaFilled $row
        issueCount = @(Get-BetaIssueText $row).Count
        priority = (Get-FieldValue $row "Priority").Trim().ToUpperInvariant()
    }
}

$rows = @(Import-Csv -LiteralPath $FeedbackPath -Encoding UTF8)
if ($rows.Count -eq 0) {
    throw "Feedback CSV has no rows: $FeedbackPath"
}

$normalizedRows = @(
    for ($index = 0; $index -lt $rows.Count; $index++) {
        New-NormalizedRow $rows[$index] $index
    }
)

$target = $null
$reason = "next blank tester"
if (-not [string]::IsNullOrWhiteSpace($UserId)) {
    $target = @($normalizedRows | Where-Object {
        $_.userId.Equals($UserId, [System.StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1)

    if ($target.Count -eq 0) {
        throw "UserId was not found in feedback rows: $UserId"
    }

    $target = $target[0]
    $reason = "requested"
}
else {
    $target = @($normalizedRows | Where-Object { -not $_.filled } | Select-Object -First 1)
    if ($target.Count -eq 0) {
        $target = $normalizedRows[0]
        $reason = "all testers have feedback"
    }
    else {
        $target = $target[0]
    }
}

$safeUserId = ($target.userId -replace "[^A-Za-z0-9_-]", "-")
$feedbackHtmlPath = Join-Path $RepoRoot "feedback\internal-beta-feedback.html"
$packetPath = Join-Path $RepoRoot ("feedback\beta-feedback-packets\beta-feedback-{0}.md" -f $safeUserId)
$playbookPath = Join-Path $RepoRoot "docs\internal-beta-playbook.md"
$recruitmentPath = Join-Path $RepoRoot "docs\internal-beta-recruitment-script.md"
$localBetaRunPath = Join-Path $RepoRoot "acceptance\local-beta-run.md"
$localBetaReadinessPath = Join-Path $RepoRoot "acceptance\local-beta-readiness.md"
$progressPath = Join-Path $RepoRoot "acceptance\first-version-progress.md"
$handoffPath = Join-Path $RepoRoot "acceptance\first-version-handoff.md"

$query = @{ user = $target.userId }
if (-not $target.filled) {
    $query.status = "blank"
}
else {
    $query.status = "filled"
}

$feedbackDeskUri = ConvertTo-FileUriWithQuery $feedbackHtmlPath $query
$packetUri = if (Test-Path -LiteralPath $packetPath) { ConvertTo-FileUri $packetPath } else { "" }
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$fields = @(
    "UserId",
    "UserType",
    "EnglishLevel",
    "CompletedTest",
    "IndependentCompletion",
    "StuckStep",
    "UnderstandsDifficulty",
    "WillingNext",
    "PerceivedUseful",
    "AudioIssue",
    "PageIssue",
    "ContentIssue",
    "Priority",
    "Notes"
)

$fieldLines = @(
    "| Field | Current value |",
    "| --- | --- |"
) + @($fields | ForEach-Object {
    "| $_ | $(ConvertTo-MarkdownText (Get-FieldValue $target.row $_)) |"
})

$lines = @(
    "# Beta Feedback Session",
    "",
    "Generated at: $generatedAt",
    "",
    "## Tester",
    "",
    "- User: $($target.userId)",
    "- Selection reason: $reason",
    "- Filled: $($target.filled)",
    "- Priority: $($target.priority)",
    "- Issue note count: $($target.issueCount)",
    "",
    "## Start Here",
    "",
    "- Web: [$WebUrl]($WebUrl)",
    "- API health: [$ApiUrl/health]($ApiUrl/health)",
    "- Feedback desk: [open]($feedbackDeskUri)",
    "- Feedback packet: [open]($packetUri)",
    "- Internal beta playbook: [open]($(ConvertTo-FileUri $playbookPath))",
    "- Recruitment and interview script: [open]($(ConvertTo-FileUri $recruitmentPath))",
    "- Local beta runbook: [open]($(ConvertTo-FileUri $localBetaRunPath))",
    "- Local beta readiness: [open]($(ConvertTo-FileUri $localBetaReadinessPath))",
    "- First version progress: [open]($(ConvertTo-FileUri $progressPath))",
    "- First version handoff: [open]($(ConvertTo-FileUri $handoffPath))",
    "",
    "## Session Tasks",
    "",
    "- Register a new account or sign in with a learner account.",
    "- Complete 2 beginner dictation questions.",
    "- Complete 2 intermediate dictation questions.",
    "- Complete 1 advanced dictation question.",
    "- Try normal speed, slow speed, first-letter hint, and Chinese hint.",
    "- Intentionally answer 1 question incorrectly and check feedback.",
    "- Open vocabulary review and learning records.",
    "",
    "## Recording Rules",
    "",
    '- Fill `CompletedTest`, `IndependentCompletion`, `UnderstandsDifficulty`, `WillingNext`, and `PerceivedUseful` from the real session only.',
    '- Use `Priority` as `P0`, `P1`, or `P2` for every reported issue before checking the release gate.',
    "- Keep observations factual: where the tester got stuck, what they said, and what they tried.",
    "- Export or save results, then validate before importing.",
    "",
    "## Current Row",
    ""
) + $fieldLines + @(
    "",
    "## Finish Commands",
    "",
    '```powershell',
    '.\scripts\import-acceptance-csv.ps1 -Kind beta -ValidateOnly',
    '.\scripts\import-acceptance-csv.ps1 -Kind beta -RefreshArtifacts',
    '.\scripts\import-beta-feedback-packets.ps1 -ValidateOnly',
    '.\scripts\import-beta-feedback-packets.ps1 -RefreshArtifacts',
    '.\scripts\start-beta-feedback-session.ps1',
    '.\scripts\export-first-version-progress.ps1',
    '.\scripts\check-local-beta-readiness.ps1',
    '```'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

if ($Open) {
    Start-Process -FilePath $OutputPath
    Start-Process -FilePath $feedbackDeskUri
    if (-not [string]::IsNullOrWhiteSpace($packetUri)) {
        Start-Process -FilePath $packetUri
    }
}

[pscustomobject]@{
    outputPath = $OutputPath
    userId = $target.userId
    selectionReason = $reason
    filled = [bool]$target.filled
    issueCount = [int]$target.issueCount
    priority = $target.priority
    feedbackDeskUri = $feedbackDeskUri
    packetPath = $packetPath
} | ConvertTo-Json -Depth 4
