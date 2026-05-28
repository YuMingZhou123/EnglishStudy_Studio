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

$contentHtml = Invoke-JsonScript -ScriptName "export-content-review-html.ps1"
$betaHtml = Invoke-JsonScript `
    -ScriptName "export-beta-feedback-html.ps1" `
    -Parameters @{ UserCount = $BetaUserCount }

$contentSummary = Invoke-JsonScript -ScriptName "summarize-content-review.ps1"
$betaSummary = Invoke-JsonScript -ScriptName "summarize-beta-feedback.ps1"

$dashboardParams = @{}
if ($SkipReadiness) {
    $dashboardParams.SkipReadiness = $true
}
$dashboard = Invoke-JsonScript `
    -ScriptName "export-mvp-acceptance-dashboard.ps1" `
    -Parameters $dashboardParams

$readiness = $null
if (-not $SkipReadiness) {
    $readiness = Invoke-JsonScript `
        -ScriptName "check-mvp-readiness.ps1" `
        -Parameters @{ SkipSmoke = $true; SkipUi = $true }
}

if ($Open) {
    Start-Process -FilePath $dashboard.outputPath
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
        html = $contentHtml
        summary = $contentSummary
    }
    betaFeedback = [pscustomobject]@{
        csv = $betaTemplate
        html = $betaHtml
        summary = $betaSummary
    }
    dashboard = $dashboard
    readiness = $readinessSummary
    nextActions = @(
        "Open acceptance/mvp-acceptance-dashboard.html for the current MVP acceptance overview.",
        "Open content/mvp-content-review.html, review every sentence, export mvp-content-review.csv, and place it under content/.",
        "Open feedback/internal-beta-feedback.html after each beta session, export internal-beta-feedback.csv, and place it under feedback/.",
        "Run .\scripts\check-mvp-readiness.ps1 -IncludeBuild before calling the first version complete."
    )
} | ConvertTo-Json -Depth 12
