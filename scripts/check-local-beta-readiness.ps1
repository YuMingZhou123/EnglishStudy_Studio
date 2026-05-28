param(
    [string]$ApiBaseUrl = "http://localhost:5180",
    [string]$WebBaseUrl = "http://localhost:3000",
    [string]$OutputPath = "",
    [switch]$AssertBetaReady
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Add-Type -AssemblyName System.Net.Http

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\local-beta-readiness.md"
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

function Test-Url([string]$Url) {
    $client = [System.Net.Http.HttpClient]::new()
    try {
        $client.Timeout = [TimeSpan]::FromSeconds(5)
        $response = $client.GetAsync($Url).GetAwaiter().GetResult()
        return [pscustomobject]@{
            reachable = [bool]$response.IsSuccessStatusCode
            statusCode = [int]$response.StatusCode
            error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            reachable = $false
            statusCode = $null
            error = $_.Exception.Message
        }
    }
    finally {
        $client.Dispose()
    }
}

function New-Check([string]$Name, [bool]$Passed, [string]$Evidence, [string]$Required) {
    [pscustomobject]@{
        name = $Name
        passed = $Passed
        evidence = $Evidence
        required = $Required
    }
}

function New-CheckLine($check) {
    $status = if ([bool]$check.passed) { "pass" } else { "fail" }
    return "| $(ConvertTo-MarkdownText $check.name) | $status | $(ConvertTo-MarkdownText $check.evidence) | $(ConvertTo-MarkdownText $check.required) |"
}

$apiHealth = Test-Url "$ApiBaseUrl/health"
$apiReady = Test-Url "$ApiBaseUrl/health/ready"
$webHome = Test-Url $WebBaseUrl
$readiness = Invoke-JsonScript -ScriptName "check-mvp-readiness.ps1" -Parameters @{ SkipSmoke = $true; SkipUi = $true }
$handoffValidation = Invoke-JsonScript -ScriptName "validate-first-version-handoff.ps1"
$progress = Invoke-JsonScript -ScriptName "export-first-version-progress.ps1"
$content = $readiness.contentReview
$beta = $readiness.betaFeedback
$contentValidation = $readiness.contentReviewValidation
$betaValidation = $readiness.betaFeedbackValidation

$betaSlotAvailable = ([int]$beta.filledRows) -lt 10
$reviewMaterialReady =
    [bool]$apiHealth.reachable -and
    [bool]$apiReady.reachable -and
    [bool]$webHome.reachable -and
    [bool]$readiness.automatedReady -and
    [bool]$handoffValidation.valid -and
    [bool]$contentValidation.valid -and
    [bool]$betaValidation.valid
$betaSessionReady =
    $reviewMaterialReady -and
    [bool]$content.passesMinimumGate -and
    $betaSlotAvailable

$checks = @(
    (New-Check "API health reachable" ([bool]$apiHealth.reachable) "status: $($apiHealth.statusCode); error: $($apiHealth.error)" "HTTP 2xx")
    (New-Check "API ready reachable" ([bool]$apiReady.reachable) "status: $($apiReady.statusCode); error: $($apiReady.error)" "HTTP 2xx")
    (New-Check "Web reachable" ([bool]$webHome.reachable) "status: $($webHome.statusCode); error: $($webHome.error)" "HTTP 2xx")
    (New-Check "Automated readiness" ([bool]$readiness.automatedReady) "automatedReady: $($readiness.automatedReady)" "true")
    (New-Check "Handoff validation" ([bool]$handoffValidation.valid) "failed checks: $($handoffValidation.failedChecks)" "0 failed checks")
    (New-Check "Content review sheet valid" ([bool]$contentValidation.valid) "rows: $($contentValidation.rowCount)" "valid CSV")
    (New-Check "Beta feedback sheet valid" ([bool]$betaValidation.valid) "rows: $($betaValidation.rowCount)" "valid CSV")
    (New-Check "Content ready for beta testers" ([bool]$content.passesMinimumGate) "pass: $($content.passRows), blank: $($content.blankRows), fix: $($content.fixRows)" "content review minimum gate true")
    (New-Check "Beta tester slot available" $betaSlotAvailable "filled: $($beta.filledRows), next: $($progress.nextBetaSlot)" "at least one open tester slot")
    (New-Check "No P0 beta issues" ([int]$beta.p0Issues -eq 0) "P0 issues: $($beta.p0Issues)" "0")
)

$failedChecks = @($checks | Where-Object { -not [bool]$_.passed })
$passedChecks = @($checks | Where-Object { [bool]$_.passed })
$checkLines = @(
    "| Check | Status | Evidence | Required |",
    "| --- | --- | --- | --- |"
) + @($checks | ForEach-Object { New-CheckLine $_ })

$failedLines = if ($failedChecks.Count -eq 0) {
    @("- No failed checks.")
}
else {
    @($failedChecks | ForEach-Object { "- $($_.name): $($_.evidence)" })
}

$decision = if ($betaSessionReady) {
    "Ready to invite real beta testers."
}
elseif ($reviewMaterialReady) {
    "Ready to run content review and prepare tester slots; content review must pass before inviting beta testers."
}
else {
    "Not ready for local beta work. Fix failed preflight checks first."
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# Local Beta Readiness",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- $decision",
    "- Review material ready: $reviewMaterialReady",
    "- Beta session ready: $betaSessionReady",
    "- Automated readiness: $($readiness.automatedReady)",
    "- Handoff valid: $($handoffValidation.valid)",
    "- Product review readiness: $($readiness.productReviewReady)",
    "- First version readiness: $($readiness.firstVersionReady)",
    "",
    "## Next Action",
    "",
    "- Next content review batch: $($progress.nextContentBatch)",
    "- Next beta tester slot: $($progress.nextBetaSlot)",
    '- Do content review before inviting beta testers if `Beta session ready` is `False` because content is not reviewed.',
    "",
    "## Checks",
    ""
) + $checkLines + @(
    "",
    "## Failed Checks",
    ""
) + $failedLines + @(
    "",
    "## Useful Files",
    "",
    "- First version progress: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\first-version-progress.md")))",
    "- First version handoff: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\first-version-handoff.md")))",
    "- Handoff validation: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\first-version-handoff-validation.md")))",
    "- Local beta runbook: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot "acceptance\local-beta-run.md")))",
    "",
    "## Commands",
    "",
    '```powershell',
    '.\scripts\prepare-local-beta-run.ps1 -SkipInfrastructure -SkipServerStart -SkipContentImport -SkipAudio',
    '.\scripts\check-local-beta-readiness.ps1',
    '.\scripts\check-local-beta-readiness.ps1 -AssertBetaReady',
    '```'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

$result = [pscustomobject]@{
    outputPath = $OutputPath
    reviewMaterialReady = $reviewMaterialReady
    betaSessionReady = $betaSessionReady
    automatedReady = [bool]$readiness.automatedReady
    handoffValid = [bool]$handoffValidation.valid
    productReviewReady = [bool]$readiness.productReviewReady
    firstVersionReady = [bool]$readiness.firstVersionReady
    passedChecks = $passedChecks.Count
    failedChecks = $failedChecks.Count
    failedCheckNames = @($failedChecks | ForEach-Object { $_.name })
    nextContentBatch = $progress.nextContentBatch
    nextBetaSlot = $progress.nextBetaSlot
}

if ($AssertBetaReady -and -not $betaSessionReady) {
    $result | ConvertTo-Json -Depth 8
    throw "Local beta session is not ready: $($result.failedCheckNames -join ', ')"
}

$result | ConvertTo-Json -Depth 8
