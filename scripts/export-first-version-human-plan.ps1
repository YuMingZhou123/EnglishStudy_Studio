param(
    [string]$ContentReviewPath = "",
    [string]$BetaFeedbackPath = "",
    [string]$OutputPath = "",
    [int]$BatchSize = 20
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
    $OutputPath = Join-Path $RepoRoot "acceptance\first-version-human-plan.md"
}

if ($BatchSize -lt 1) {
    throw "BatchSize must be greater than 0."
}

$ContentReviewPath = [System.IO.Path]::GetFullPath($ContentReviewPath)
$BetaFeedbackPath = [System.IO.Path]::GetFullPath($BetaFeedbackPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

$AllowedContentStatuses = @(
    "pass",
    "fix_sentence",
    "fix_translation",
    "fix_keyword",
    "fix_audio",
    "remove"
)

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

function Get-MarkdownLink([string]$label, [string]$path) {
    if ([string]::IsNullOrWhiteSpace($path)) {
        return ""
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

function Get-ContentNotes($row) {
    return @(
        [string]$row.SentenceNotes,
        [string]$row.TranslationNotes,
        [string]$row.KeywordNotes,
        [string]$row.AudioNotes,
        [string]$row.FinalNotes
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Test-BetaFilled($row) {
    return -not [string]::IsNullOrWhiteSpace([string]$row.CompletedTest) -or
        -not [string]::IsNullOrWhiteSpace([string]$row.IndependentCompletion) -or
        -not [string]::IsNullOrWhiteSpace([string]$row.Notes)
}

function Get-BetaIssueText($row) {
    $audioIssue = Get-Status $row.AudioIssue
    $audioIssueValue = if (-not [string]::IsNullOrWhiteSpace($audioIssue) -and $audioIssue -ne "none") {
        [string]$row.AudioIssue
    }
    else {
        ""
    }

    return @(
        [string]$row.StuckStep,
        $audioIssueValue,
        [string]$row.PageIssue,
        [string]$row.ContentIssue
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function New-ContentBatchRows($rows) {
    if ($rows.Count -eq 0) {
        return @()
    }

    $batchCount = [math]::Ceiling($rows.Count / $BatchSize)
    return @(
        for ($index = 0; $index -lt $batchCount; $index++) {
            $start = ($index * $BatchSize) + 1
            $end = [math]::Min(($index + 1) * $BatchSize, $rows.Count)
            $batchRows = @($rows | Where-Object {
                $rowNumber = 0
                [int]::TryParse([string]$_.RowNumber, [ref]$rowNumber) -and
                    $rowNumber -ge $start -and
                    $rowNumber -le $end
            })

            $passRows = @($batchRows | Where-Object { (Get-Status $_.ReviewStatus) -eq "pass" })
            $blankRows = @($batchRows | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.ReviewStatus) })
            $invalidRows = @($batchRows | Where-Object {
                $status = Get-Status $_.ReviewStatus
                -not [string]::IsNullOrWhiteSpace($status) -and $AllowedContentStatuses -notcontains $status
            })
            $fixRows = @($batchRows | Where-Object {
                $status = Get-Status $_.ReviewStatus
                $AllowedContentStatuses -contains $status -and $status -ne "pass"
            })
            $missingNoteRows = @($batchRows | Where-Object {
                $status = Get-Status $_.ReviewStatus
                $AllowedContentStatuses -contains $status -and
                    $status -ne "pass" -and
                    @(Get-ContentNotes $_).Count -eq 0
            })

            $state = if ($invalidRows.Count -gt 0) {
                "repair_status"
            }
            elseif ($missingNoteRows.Count -gt 0) {
                "add_notes"
            }
            elseif ($blankRows.Count -gt 0) {
                "review"
            }
            elseif ($fixRows.Count -gt 0) {
                "fix_content"
            }
            else {
                "done"
            }

            $queryStatus = if ($state -eq "review") { "blank" } elseif ($state -eq "fix_content") { "fix" } else { "" }
            $query = @{ batch = "$start-$end" }
            if (-not [string]::IsNullOrWhiteSpace($queryStatus)) {
                $query.status = $queryStatus
            }

            [pscustomobject]@{
                batch = "$start-$end"
                state = $state
                passRows = $passRows.Count
                fixRows = $fixRows.Count
                blankRows = $blankRows.Count
                invalidRows = $invalidRows.Count
                missingNoteRows = $missingNoteRows.Count
                reviewUrl = ConvertTo-FileUriWithQuery (Join-Path $RepoRoot "content\mvp-content-review.html") $query
                packetPath = Join-Path $RepoRoot ("content\review-packets\content-review-batch-{0:D3}-{1:D3}.md" -f $start, $end)
            }
        }
    )
}

function New-BetaSlotRows($rows) {
    return @(
        for ($index = 0; $index -lt $rows.Count; $index++) {
            $row = $rows[$index]
            $userId = [string]$row.UserId
            if ([string]::IsNullOrWhiteSpace($userId)) {
                $userId = "U{0:D2}" -f ($index + 1)
            }

            $filled = Test-BetaFilled $row
            $requiredMissing = @(
                [string]$row.CompletedTest,
                [string]$row.IndependentCompletion,
                [string]$row.UnderstandsDifficulty,
                [string]$row.WillingNext,
                [string]$row.PerceivedUseful
            ) | Where-Object { [string]::IsNullOrWhiteSpace($_) }
            $issueCount = @(Get-BetaIssueText $row).Count
            $priority = ([string]$row.Priority).Trim().ToUpperInvariant()
            $needsTriage = $filled -and $issueCount -gt 0 -and [string]::IsNullOrWhiteSpace($priority)
            $state = if (-not $filled) {
                "record"
            }
            elseif ($needsTriage) {
                "triage"
            }
            elseif ($requiredMissing.Count -gt 0) {
                "complete_fields"
            }
            else {
                "done"
            }

            $safeUserId = ($userId -replace "[^A-Za-z0-9_-]", "-")
            $query = @{ user = $userId }
            if (-not $filled) {
                $query.status = "blank"
            }

            [pscustomobject]@{
                userId = $userId
                state = $state
                completedTest = [string]$row.CompletedTest
                independentCompletion = [string]$row.IndependentCompletion
                understandsDifficulty = [string]$row.UnderstandsDifficulty
                willingNext = [string]$row.WillingNext
                priority = $priority
                issueCount = $issueCount
                feedbackUrl = ConvertTo-FileUriWithQuery (Join-Path $RepoRoot "feedback\internal-beta-feedback.html") $query
                packetPath = Join-Path $RepoRoot ("feedback\beta-feedback-packets\beta-feedback-{0}.md" -f $safeUserId)
            }
        }
    )
}

if (-not (Test-Path -LiteralPath $ContentReviewPath)) {
    throw "Content review CSV not found: $ContentReviewPath. Run .\scripts\prepare-mvp-acceptance.ps1 first."
}

if (-not (Test-Path -LiteralPath $BetaFeedbackPath)) {
    throw "Beta feedback CSV not found: $BetaFeedbackPath. Run .\scripts\prepare-mvp-acceptance.ps1 first."
}

$contentRows = @(Import-Csv -LiteralPath $ContentReviewPath -Encoding UTF8)
$betaRows = @(Import-Csv -LiteralPath $BetaFeedbackPath -Encoding UTF8)
$contentGate = Invoke-JsonScript -ScriptName "check-content-review-gate.ps1"
$contentAudioReadiness = Invoke-JsonScript -ScriptName "check-content-audio-readiness.ps1"
$betaGate = Invoke-JsonScript -ScriptName "check-beta-feedback-gate.ps1"
$releaseGate = Invoke-JsonScript -ScriptName "export-first-version-release-gate.ps1"
$contentBatches = @(New-ContentBatchRows $contentRows)
$betaSlots = @(New-BetaSlotRows $betaRows)

$nextContentBatch = @($contentBatches | Where-Object { $_.state -ne "done" } | Select-Object -First 1)
$nextBetaSlot = @($betaSlots | Where-Object { $_.state -ne "done" } | Select-Object -First 1)
$contentGateReady = [bool]$contentGate.ready
$audioTechnicalReady = [bool]$contentAudioReadiness.ready
$betaGateReady = [bool]$betaGate.ready
$canInviteBeta = $contentGateReady -and [int]$betaGate.p0Issues -eq 0 -and [int]$betaGate.untriagedIssueRows -eq 0

$lane = if (-not $contentGateReady) {
    "content_review"
}
elseif (-not $betaGateReady) {
    "beta_feedback"
}
elseif ([bool]$releaseGate.readyForRelease) {
    "release_gate"
}
else {
    "fix_gate_shortages"
}

$recommendedCommand = switch ($lane) {
    "content_review" { ".\scripts\start-content-review-batch.ps1 -Open" }
    "beta_feedback" { ".\scripts\start-beta-feedback-session.ps1 -Open" }
    "release_gate" { ".\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady" }
    default { ".\scripts\export-mvp-fix-plan.ps1" }
}

$contentTable = @(
    "| Batch | State | Pass | Fix | Blank | Invalid | Missing notes | Action | Packet |",
    "| --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |"
) + @($contentBatches | ForEach-Object {
    $packet = if (Test-Path -LiteralPath $_.packetPath) { Get-MarkdownLink "Packet" $_.packetPath } else { "" }
    "| $(ConvertTo-MarkdownText $_.batch) | $(ConvertTo-MarkdownText $_.state) | $($_.passRows) | $($_.fixRows) | $($_.blankRows) | $($_.invalidRows) | $($_.missingNoteRows) | [Open]($($_.reviewUrl)) | $packet |"
})

$betaTable = @(
    "| User | State | Completed | Independent | Difficulty | Willing | Priority | Issues | Action | Packet |",
    "| --- | --- | --- | --- | --- | --- | --- | ---: | --- | --- |"
) + @($betaSlots | ForEach-Object {
    $packet = if (Test-Path -LiteralPath $_.packetPath) { Get-MarkdownLink "Packet" $_.packetPath } else { "" }
    "| $(ConvertTo-MarkdownText $_.userId) | $(ConvertTo-MarkdownText $_.state) | $(ConvertTo-MarkdownText $_.completedTest) | $(ConvertTo-MarkdownText $_.independentCompletion) | $(ConvertTo-MarkdownText $_.understandsDifficulty) | $(ConvertTo-MarkdownText $_.willingNext) | $(ConvertTo-MarkdownText $_.priority) | $($_.issueCount) | [Open]($($_.feedbackUrl)) | $packet |"
})

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$nextContentText = if ($nextContentBatch.Count -gt 0) { $nextContentBatch[0].batch } else { "none" }
$nextBetaText = if ($nextBetaSlot.Count -gt 0) { $nextBetaSlot[0].userId } else { "none" }

$lines = @(
    "# First Version Human Execution Plan",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- Current lane: $lane",
    ('- Recommended command: `' + $recommendedCommand + '`'),
    "- Content gate ready: $contentGateReady",
    "- Audio technical ready: $audioTechnicalReady",
    "- Beta gate ready: $betaGateReady",
    "- Can invite beta testers: $canInviteBeta",
    "- Next content batch: $nextContentText",
    "- Next beta slot: $nextBetaText",
    "",
    "## Work Order",
    "",
    '1. Run audio technical readiness before content review, then finish content review first. Do not mark rows as `pass` without checking sentence, translation, keywords, and audio experience.',
    "2. Fix every non-pass content row and rerun the content gate.",
    "3. Invite real beta testers only after the content gate is ready.",
    "4. Record at least 5 completed beta sessions; keep U06-U10 as backup slots.",
    '5. Triage every reported issue as `P0`, `P1`, or `P2` before the release gate.',
    "6. Run the full release gate with build checks.",
    "",
    "## Content Review Queue",
    ""
) + $contentTable + @(
    "",
    "## Beta Feedback Queue",
    "",
    '- Beta testers should wait until `Can invite beta testers` is `True`.',
    ""
) + $betaTable + @(
    "",
    "## Gate Commands",
    "",
    '```powershell',
    '.\scripts\check-content-review-batch.ps1',
    '.\scripts\check-content-audio-readiness.ps1',
    '.\scripts\check-content-review-gate.ps1',
    '.\scripts\check-local-beta-readiness.ps1',
    '.\scripts\check-beta-feedback-session.ps1',
    '.\scripts\check-beta-feedback-gate.ps1',
    '.\scripts\export-mvp-fix-plan.ps1',
    '.\scripts\export-first-version-release-gate.ps1 -IncludeBuild -AssertReady',
    '```',
    "",
    "## Useful Files",
    "",
    "- Acceptance dashboard: $(Get-MarkdownLink 'open' (Join-Path $RepoRoot 'acceptance\mvp-acceptance-dashboard.html'))",
    "- First version work session: $(Get-MarkdownLink 'open' (Join-Path $RepoRoot 'acceptance\first-version-work-session.md'))",
    "- First version progress: $(Get-MarkdownLink 'open' (Join-Path $RepoRoot 'acceptance\first-version-progress.md'))",
    "- First version handoff: $(Get-MarkdownLink 'open' (Join-Path $RepoRoot 'acceptance\first-version-handoff.md'))",
    "- Content audio readiness: $(Get-MarkdownLink 'open' (Join-Path $RepoRoot 'acceptance\content-audio-readiness.md'))",
    "- Local beta readiness: $(Get-MarkdownLink 'open' (Join-Path $RepoRoot 'acceptance\local-beta-readiness.md'))",
    "- Fix plan: $(Get-MarkdownLink 'open' (Join-Path $RepoRoot 'acceptance\mvp-fix-plan.md'))",
    "",
    "## Guardrails",
    "",
    "- Do not fabricate content review status.",
    "- Do not invent or copy beta feedback.",
    "- Do not invite beta testers before content review passes the gate."
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    lane = $lane
    recommendedCommand = $recommendedCommand
    contentGateReady = $contentGateReady
    audioTechnicalReady = $audioTechnicalReady
    missingAudioRows = $contentAudioReadiness.missingAudioRows
    unreadableAudioRows = $contentAudioReadiness.unreadableAudioRows
    betaGateReady = $betaGateReady
    canInviteBeta = $canInviteBeta
    nextContentBatch = $nextContentText
    nextBetaSlot = $nextBetaText
    contentBatchCount = $contentBatches.Count
    betaSlotCount = $betaSlots.Count
    readyForRelease = [bool]$releaseGate.readyForRelease
    openGateShortages = $releaseGate.openGateShortages
} | ConvertTo-Json -Depth 8
