param(
    [int]$BetaUserCount = 10,
    [switch]$SkipReadiness,
    [switch]$Open
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ($BetaUserCount -lt 1) {
    throw "BetaUserCount must be greater than 0."
}

function Get-FullPath([string]$path) {
    return [System.IO.Path]::GetFullPath($path)
}

function Invoke-JsonScript {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{}
    )

    $scriptPath = Join-Path $PSScriptRoot $scriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found: $scriptPath"
    }

    $output = & $scriptPath @Parameters
    $text = $output | Out-String
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Script returned empty output: $ScriptName"
    }

    return $text | ConvertFrom-Json
}

function Ensure-Template {
    param(
        [string]$Path,
        [string]$ScriptName,
        [hashtable]$Parameters = @{}
    )

    if (Test-Path -LiteralPath $path) {
        return [pscustomobject]@{
            outputPath = $path
            created = $false
            message = "Existing file kept."
        }
    }

    $summary = Invoke-JsonScript -ScriptName $ScriptName -Parameters $Parameters
    return [pscustomobject]@{
        outputPath = $summary.outputPath
        rows = $summary.rows
        created = $true
        message = "Template created."
    }
}

$contentReviewCsv = Get-FullPath (Join-Path $PSScriptRoot "..\content\mvp-content-review.csv")
$contentReviewHtml = Get-FullPath (Join-Path $PSScriptRoot "..\content\mvp-content-review.html")
$betaFeedbackCsv = Get-FullPath (Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv")
$betaFeedbackHtml = Get-FullPath (Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.html")

$contentTemplate = Ensure-Template -Path $contentReviewCsv -ScriptName "export-content-review-sheet.ps1"
$betaTemplate = Ensure-Template `
    -Path $betaFeedbackCsv `
    -ScriptName "export-beta-feedback-template.ps1" `
    -Parameters @{ UserCount = $BetaUserCount }

$contentValidation = Invoke-JsonScript `
    -ScriptName "import-acceptance-csv.ps1" `
    -Parameters @{ Kind = "content"; SourcePath = $contentReviewCsv; ValidateOnly = $true }
$betaValidation = Invoke-JsonScript `
    -ScriptName "import-acceptance-csv.ps1" `
    -Parameters @{ Kind = "beta"; SourcePath = $betaFeedbackCsv; ValidateOnly = $true }

$contentHtml = Invoke-JsonScript -ScriptName "export-content-review-html.ps1"
$contentPackets = Invoke-JsonScript -ScriptName "export-content-review-packets.ps1"
$betaHtml = Invoke-JsonScript `
    -ScriptName "export-beta-feedback-html.ps1" `
    -Parameters @{ UserCount = $BetaUserCount }
$betaPackets = Invoke-JsonScript `
    -ScriptName "export-beta-feedback-packets.ps1" `
    -Parameters @{ UserCount = $BetaUserCount }

$contentSummary = $contentValidation.summary
$betaSummary = $betaValidation.summary

$dashboardParams = @{}
if ($SkipReadiness) {
    $dashboardParams.SkipReadiness = $true
}
$dashboard = Invoke-JsonScript `
    -ScriptName "export-mvp-acceptance-dashboard.ps1" `
    -Parameters $dashboardParams
$tasks = Invoke-JsonScript -ScriptName "export-mvp-acceptance-tasks.ps1"
$fixPlan = Invoke-JsonScript -ScriptName "export-mvp-fix-plan.ps1"
$releaseGate = Invoke-JsonScript -ScriptName "export-first-version-release-gate.ps1"
$statusReportParams = @{}
if ($SkipReadiness) {
    $statusReportParams.SkipReadiness = $true
}
$statusReport = Invoke-JsonScript -ScriptName "export-first-version-status.ps1" -Parameters $statusReportParams
$handoff = Invoke-JsonScript -ScriptName "export-first-version-handoff.ps1"

$readiness = $null
if (-not $SkipReadiness) {
    $readiness = Invoke-JsonScript `
        -ScriptName "check-mvp-readiness.ps1" `
        -Parameters @{ SkipSmoke = $true; SkipUi = $true }
}

if ($Open) {
    Start-Process -FilePath $dashboard.outputPath
    Start-Process -FilePath $tasks.outputPath
    Start-Process -FilePath $contentReviewHtml
    Start-Process -FilePath $betaFeedbackHtml
}

$readinessSummary = if ($null -ne $readiness) {
    [pscustomobject]@{
        automatedReady = [bool]$readiness.automatedReady
        productReviewReady = [bool]$readiness.productReviewReady
        firstVersionReady = [bool]$readiness.firstVersionReady
    }
}
else {
    $null
}

[pscustomobject]@{
    contentReview = [pscustomobject]@{
        csv = $contentTemplate
        validation = $contentValidation
        html = $contentHtml
        packets = $contentPackets
        summary = $contentSummary
    }
    betaFeedback = [pscustomobject]@{
        csv = $betaTemplate
        validation = $betaValidation
        html = $betaHtml
        packets = $betaPackets
        summary = $betaSummary
    }
    dashboard = $dashboard
    tasks = $tasks
    fixPlan = $fixPlan
    releaseGate = $releaseGate
    statusReport = $statusReport
    handoff = $handoff
    readiness = $readinessSummary
    nextActions = @(
        "Open acceptance/mvp-acceptance-dashboard.html for the current MVP acceptance overview.",
        "Open acceptance/mvp-acceptance-tasks.md for batch-by-batch content review and tester follow-up tasks.",
        "Open acceptance/mvp-fix-plan.md after content review or beta feedback is filled to see what must be fixed before release.",
        "Open acceptance/first-version-release-gate.md to see the final release gates.",
        "Open acceptance/first-version-status.md for the current release decision snapshot.",
        "Open acceptance/first-version-handoff.md for the next content batch and beta tester slot.",
        "Use content/review-packets/index.md if you want to split content review across multiple reviewers.",
        "After reviewed packets are returned, run .\scripts\import-content-review-packets.ps1 -ValidateOnly, then .\scripts\import-content-review-packets.ps1 -RefreshArtifacts.",
        "Open content/mvp-content-review.html, review every sentence, export mvp-content-review.csv, then run .\scripts\import-acceptance-csv.ps1 -Kind content -ValidateOnly before importing.",
        "If the content CSV validates, run .\scripts\import-acceptance-csv.ps1 -Kind content -RefreshArtifacts.",
        "Use feedback/beta-feedback-packets/index.md if you want one feedback packet per beta tester.",
        "After beta packets are returned, run .\scripts\import-beta-feedback-packets.ps1 -ValidateOnly, then .\scripts\import-beta-feedback-packets.ps1 -RefreshArtifacts.",
        "Open feedback/internal-beta-feedback.html after each beta session, export internal-beta-feedback.csv, then run .\scripts\import-acceptance-csv.ps1 -Kind beta -ValidateOnly before importing.",
        "If the beta CSV validates, run .\scripts\import-acceptance-csv.ps1 -Kind beta -RefreshArtifacts.",
        "Run .\scripts\check-mvp-readiness.ps1 -IncludeBuild before calling the first version complete."
    )
} | ConvertTo-Json -Depth 12
