param(
    [string]$OutputPath = "",
    [switch]$SkipReadiness
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\acceptance\mvp-acceptance-dashboard.html"
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

function ConvertTo-HtmlText($value) {
    return [System.Net.WebUtility]::HtmlEncode([string]$value)
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

function Invoke-JsonScript {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{}
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    $output = & $scriptPath @Parameters
    $text = $output | Out-String
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Script returned empty output: $ScriptName"
    }

    return $text | ConvertFrom-Json
}

function Invoke-OptionalJsonScript {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{},
        [string]$MissingMessage = ""
    )

    try {
        return Invoke-JsonScript -ScriptName $ScriptName -Parameters $Parameters
    }
    catch {
        return [pscustomobject]@{
            missing = $true
            message = $MissingMessage
            error = $_.Exception.Message
            passesMinimumGate = $false
        }
    }
}

function Get-ObjectProperty($object, [string]$name, $Default = $null) {
    if ($null -eq $object) {
        return $Default
    }

    $property = $object.PSObject.Properties[$name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
}

function Test-ObjectFlag($object, [string]$name) {
    $value = Get-ObjectProperty $object $name
    if ($null -eq $value) {
        return $false
    }

    return [bool]$value
}

function Get-NextContentReviewBatch([string]$ReviewPath, [int]$BatchSize = 20) {
    if (-not (Test-Path -LiteralPath $ReviewPath)) {
        return [pscustomobject]@{
            batch = "1-20"
            status = "blank"
            label = "Review rows 1-20"
        }
    }

    $rows = @(Import-Csv -LiteralPath $ReviewPath -Encoding UTF8)
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            batch = "1-20"
            status = "blank"
            label = "Review rows 1-20"
        }
    }

    $targetRow = $null
    $status = "blank"
    $labelPrefix = "Review rows"
    foreach ($row in $rows) {
        if ([string]::IsNullOrWhiteSpace([string]$row.ReviewStatus)) {
            $targetRow = $row
            break
        }
    }

    if ($null -eq $targetRow) {
        foreach ($row in $rows) {
            $rowStatus = ([string]$row.ReviewStatus).Trim().ToLowerInvariant()
            if ($rowStatus -ne "pass") {
                $targetRow = $row
                $status = $rowStatus
                $labelPrefix = "Fix rows"
                break
            }
        }
    }

    if ($null -eq $targetRow) {
        $targetRow = $rows[0]
        $status = ""
        $labelPrefix = "Open rows"
    }

    $rowNumber = 1
    if (-not [int]::TryParse([string]$targetRow.RowNumber, [ref]$rowNumber)) {
        $rowNumber = 1
    }

    $start = ([math]::Floor(($rowNumber - 1) / $BatchSize) * $BatchSize) + 1
    $end = [math]::Min($start + $BatchSize - 1, $rows.Count)

    return [pscustomobject]@{
        batch = "$start-$end"
        status = $status
        label = "$labelPrefix $start-$end"
    }
}

function Get-NextBetaFeedbackUser([string]$FeedbackPath) {
    if (-not (Test-Path -LiteralPath $FeedbackPath)) {
        return [pscustomobject]@{
            user = "U01"
            status = "blank"
            label = "Record tester U01"
        }
    }

    $rows = @(Import-Csv -LiteralPath $FeedbackPath -Encoding UTF8)
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            user = "U01"
            status = "blank"
            label = "Record tester U01"
        }
    }

    foreach ($row in $rows) {
        $completed = [string]$row.CompletedTest
        $independent = [string]$row.IndependentCompletion
        $notes = [string]$row.Notes
        if ([string]::IsNullOrWhiteSpace($completed) -and
            [string]::IsNullOrWhiteSpace($independent) -and
            [string]::IsNullOrWhiteSpace($notes)) {
            $userId = if ([string]::IsNullOrWhiteSpace([string]$row.UserId)) { "U01" } else { [string]$row.UserId }
            return [pscustomobject]@{
                user = $userId
                status = "blank"
                label = "Record tester $userId"
            }
        }
    }

    foreach ($row in $rows) {
        $completed = ([string]$row.CompletedTest).Trim().ToLowerInvariant()
        if ($completed -ne "yes") {
            $userId = if ([string]::IsNullOrWhiteSpace([string]$row.UserId)) { "U01" } else { [string]$row.UserId }
            return [pscustomobject]@{
                user = $userId
                status = ""
                label = "Follow up $userId"
            }
        }
    }

    $firstUser = if ([string]::IsNullOrWhiteSpace([string]$rows[0].UserId)) { "U01" } else { [string]$rows[0].UserId }
    return [pscustomobject]@{
        user = $firstUser
        status = ""
        label = "Open tester $firstUser"
    }
}

function New-MetricHtml([string]$label, $value, [string]$className = "") {
    return @"
        <div class="metric $className">
          <strong>$(ConvertTo-HtmlText $value)</strong>
          <span>$(ConvertTo-HtmlText $label)</span>
        </div>
"@
}

function New-GatedMetricHtml([string]$label, $value, [scriptblock]$gate, [string]$FailClass = "gate-warn") {
    $className = "gate-warn"
    if ($null -ne $value -and [string]$value -ne "n/a") {
        if (& $gate ([int]$value)) {
            $className = "gate-ok"
        }
        else {
            $className = $FailClass
        }
    }

    return New-MetricHtml $label $value $className
}

function New-StatusText($value) {
    if ($null -eq $value) {
        return "Skipped"
    }

    if ([bool]$value) {
        return "Ready"
    }

    return "Not ready"
}

function New-StatusClass($value) {
    if ($null -eq $value) {
        return "gate-warn"
    }

    if ([bool]$value) {
        return "gate-ok"
    }

    return "gate-warn"
}

function New-StatusMetricHtml([string]$label, $value, [bool]$CheckFailed = $false) {
    if ($CheckFailed) {
        return New-MetricHtml $label "Check failed" "gate-bad"
    }

    return New-MetricHtml $label $(New-StatusText $value) $(New-StatusClass $value)
}

$contentReview = Invoke-OptionalJsonScript `
    -ScriptName "summarize-content-review.ps1" `
    -MissingMessage "Content review sheet is missing."

$betaFeedback = Invoke-OptionalJsonScript `
    -ScriptName "summarize-beta-feedback.ps1" `
    -MissingMessage "Beta feedback sheet is missing."

$contentGateCheck = Invoke-OptionalJsonScript `
    -ScriptName "check-content-review-gate.ps1" `
    -MissingMessage "Content review gate check could not run."

$contentAudioReadiness = Invoke-OptionalJsonScript `
    -ScriptName "check-content-audio-readiness.ps1" `
    -MissingMessage "Content audio readiness check could not run."

$betaGateCheck = Invoke-OptionalJsonScript `
    -ScriptName "check-beta-feedback-gate.ps1" `
    -MissingMessage "Beta feedback gate check could not run."

$readiness = if ($SkipReadiness) {
    $null
}
else {
    Invoke-OptionalJsonScript `
        -ScriptName "check-mvp-readiness.ps1" `
        -Parameters @{ SkipSmoke = $true; SkipUi = $true } `
        -MissingMessage "Readiness check could not run."
}

$contentReviewHtmlPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.html"
$contentReviewCsvPath = Get-ObjectProperty $contentReview "reviewPath" (Join-Path $PSScriptRoot "..\content\mvp-content-review.csv")
$contentPrecheckPath = Join-Path $PSScriptRoot "..\acceptance\content-precheck-report.md"
$contentAudioReadinessPath = Join-Path $PSScriptRoot "..\acceptance\content-audio-readiness.md"
$contentGateCheckPath = Join-Path $PSScriptRoot "..\acceptance\content-review-gate-check.md"
$betaFeedbackHtmlPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.html"
$betaFeedbackCsvPath = Get-ObjectProperty $betaFeedback "feedbackPath" (Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv")
$betaGateCheckPath = Join-Path $PSScriptRoot "..\acceptance\beta-feedback-gate-check.md"
$acceptanceTasksPath = Join-Path $PSScriptRoot "..\acceptance\mvp-acceptance-tasks.md"
$humanPlanPath = Join-Path $PSScriptRoot "..\acceptance\first-version-human-plan.md"
$contentReviewDocPath = Join-Path $PSScriptRoot "..\docs\content-quality-review.md"
$betaPlaybookPath = Join-Path $PSScriptRoot "..\docs\internal-beta-playbook.md"
$acceptanceChecklistPath = Join-Path $PSScriptRoot "..\docs\mvp-acceptance-checklist.md"

$contentReviewReady = Test-ObjectFlag $contentGateCheck "ready"
$betaFeedbackReady = Test-ObjectFlag $betaGateCheck "ready"
$contentReviewCheckFailed = Test-ObjectFlag $contentReview "missing"
$contentAudioReadinessCheckFailed = Test-ObjectFlag $contentAudioReadiness "missing"
$betaFeedbackCheckFailed = Test-ObjectFlag $betaFeedback "missing"
$contentGateCheckFailed = Test-ObjectFlag $contentGateCheck "missing"
$betaGateCheckFailed = Test-ObjectFlag $betaGateCheck "missing"
$readinessCheckFailed = ($null -ne $readiness) -and (Test-ObjectFlag $readiness "missing")
$automatedValue = Get-ObjectProperty $readiness "automatedReady"
$productReviewValue = Get-ObjectProperty $readiness "productReviewReady"
$firstVersionValue = Get-ObjectProperty $readiness "firstVersionReady"

$contentTotalRows = Get-ObjectProperty $contentReview "totalRows" "n/a"
$contentPassRows = Get-ObjectProperty $contentReview "passRows" "n/a"
$contentFixRows = Get-ObjectProperty $contentReview "fixRows" "n/a"
$contentBlankRows = Get-ObjectProperty $contentReview "blankRows" "n/a"
$contentInvalidRows = Get-ObjectProperty $contentGateCheck "invalidStatusRows" "n/a"
$contentShortages = Get-ObjectProperty $contentGateCheck "minimumShortages" "n/a"
$contentAudioReady = Get-ObjectProperty $contentAudioReadiness "ready"
$contentAudioMissingRows = Get-ObjectProperty $contentAudioReadiness "missingAudioRows" "n/a"
$contentAudioUnreadableRows = Get-ObjectProperty $contentAudioReadiness "unreadableAudioRows" "n/a"
$betaFilledRows = Get-ObjectProperty $betaFeedback "filledRows" "n/a"
$betaCompletedUsers = Get-ObjectProperty $betaFeedback "completedUsers" "n/a"
$betaIndependentUsers = Get-ObjectProperty $betaFeedback "independentUsers" "n/a"
$betaDifficultyUsers = Get-ObjectProperty $betaFeedback "difficultyUnderstoodUsers" "n/a"
$betaWillingNextUsers = Get-ObjectProperty $betaFeedback "willingNextUsers" "n/a"
$betaP0Issues = Get-ObjectProperty $betaFeedback "p0Issues" "n/a"
$betaInvalidRows = Get-ObjectProperty $betaGateCheck "invalidRows" "n/a"
$betaIncompleteRows = Get-ObjectProperty $betaGateCheck "incompleteTouchedRows" "n/a"
$betaShortages = Get-ObjectProperty $betaGateCheck "minimumShortages" "n/a"
$nextContentBatch = Get-NextContentReviewBatch $contentReviewCsvPath
$nextContentBatchQuery = @{ batch = $nextContentBatch.batch }
if (-not [string]::IsNullOrWhiteSpace([string]$nextContentBatch.status)) {
    $nextContentBatchQuery.status = $nextContentBatch.status
}
$nextContentBatchUri = ConvertTo-FileUriWithQuery $contentReviewHtmlPath $nextContentBatchQuery
$nextBetaUser = Get-NextBetaFeedbackUser $betaFeedbackCsvPath
$nextBetaUserQuery = @{ user = $nextBetaUser.user }
if (-not [string]::IsNullOrWhiteSpace([string]$nextBetaUser.status)) {
    $nextBetaUserQuery.status = $nextBetaUser.status
}
$nextBetaUserUri = ConvertTo-FileUriWithQuery $betaFeedbackHtmlPath $nextBetaUserQuery

$contentMetrics = @(
    New-MetricHtml "Total rows" $contentTotalRows
    New-GatedMetricHtml "Pass rows" $contentPassRows { param($value) $value -ge 100 }
    New-GatedMetricHtml "Fix rows" $contentFixRows { param($value) $value -eq 0 } "gate-bad"
    New-GatedMetricHtml "Blank rows" $contentBlankRows { param($value) $value -eq 0 }
    New-GatedMetricHtml "Invalid rows" $contentInvalidRows { param($value) $value -eq 0 } "gate-bad"
    New-GatedMetricHtml "Shortages" $contentShortages { param($value) $value -eq 0 }
    New-StatusMetricHtml "Audio technical" $contentAudioReady $contentAudioReadinessCheckFailed
    New-GatedMetricHtml "Missing audio" $contentAudioMissingRows { param($value) $value -eq 0 } "gate-bad"
    New-GatedMetricHtml "Unreadable audio" $contentAudioUnreadableRows { param($value) $value -eq 0 } "gate-bad"
    New-StatusMetricHtml "Content gate" $contentReviewReady ($contentReviewCheckFailed -or $contentGateCheckFailed)
) -join "`n"

$betaMetrics = @(
    New-GatedMetricHtml "Filled rows" $betaFilledRows { param($value) $value -ge 5 }
    New-GatedMetricHtml "Completed" $betaCompletedUsers { param($value) $value -ge 5 }
    New-GatedMetricHtml "Independent" $betaIndependentUsers { param($value) $value -ge 4 }
    New-GatedMetricHtml "Difficulty" $betaDifficultyUsers { param($value) $value -ge 4 }
    New-GatedMetricHtml "Willing next" $betaWillingNextUsers { param($value) $value -ge 3 }
    New-GatedMetricHtml "P0 issues" $betaP0Issues { param($value) $value -eq 0 } "gate-bad"
    New-GatedMetricHtml "Invalid rows" $betaInvalidRows { param($value) $value -eq 0 } "gate-bad"
    New-GatedMetricHtml "Incomplete" $betaIncompleteRows { param($value) $value -eq 0 }
    New-GatedMetricHtml "Shortages" $betaShortages { param($value) $value -eq 0 }
    New-StatusMetricHtml "Beta gate" $betaFeedbackReady ($betaFeedbackCheckFailed -or $betaGateCheckFailed)
) -join "`n"

$readinessMetrics = @(
    New-StatusMetricHtml "Automated" $automatedValue $readinessCheckFailed
    New-StatusMetricHtml "Product review" $productReviewValue $readinessCheckFailed
    New-StatusMetricHtml "First version" $firstVersionValue $readinessCheckFailed
) -join "`n"

$html = @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EnglishStudy MVP Acceptance Dashboard</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f6f7f9;
      --panel: #ffffff;
      --ink: #17202a;
      --muted: #607080;
      --line: #d8dee8;
      --accent: #0f766e;
      --warn: #b45309;
      --bad: #b91c1c;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--bg);
      color: var(--ink);
      font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.5;
    }
    header {
      border-bottom: 1px solid var(--line);
      background: var(--panel);
    }
    .wrap {
      width: min(1180px, calc(100% - 32px));
      margin: 0 auto;
    }
    .top {
      display: flex;
      gap: 16px;
      align-items: center;
      justify-content: space-between;
      padding: 18px 0;
    }
    h1 {
      margin: 0;
      font-size: 24px;
      letter-spacing: 0;
    }
    h2 {
      margin: 0 0 12px;
      font-size: 18px;
      letter-spacing: 0;
    }
    .hint {
      margin: 4px 0 0;
      color: var(--muted);
      font-size: 13px;
    }
    main {
      display: grid;
      gap: 14px;
      padding: 18px 0 32px;
    }
    .panel {
      border: 1px solid var(--line);
      border-radius: 8px;
      background: var(--panel);
      padding: 14px;
    }
    .metrics {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 10px;
    }
    .metric {
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 12px;
      background: #fff;
    }
    .metric strong {
      display: block;
      font-size: 22px;
    }
    .metric span {
      color: var(--muted);
      font-size: 12px;
    }
    .links {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 12px;
    }
    a.button {
      min-height: 36px;
      display: inline-flex;
      align-items: center;
      border: 1px solid var(--line);
      border-radius: 6px;
      background: white;
      color: var(--ink);
      padding: 0 10px;
      font-weight: 700;
      text-decoration: none;
    }
    a.primary {
      border-color: var(--accent);
      background: var(--accent);
      color: white;
    }
    code {
      border: 1px solid var(--line);
      border-radius: 6px;
      background: #f8fafc;
      padding: 2px 6px;
    }
    .gate-ok { color: var(--accent); }
    .gate-warn { color: var(--warn); }
    .gate-bad { color: var(--bad); }
    @media (max-width: 860px) {
      .top { align-items: flex-start; flex-direction: column; }
      .metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    }
    @media (max-width: 520px) {
      .metrics { grid-template-columns: 1fr; }
    }
  </style>
</head>
<body>
  <header>
    <div class="wrap top">
      <div>
        <h1>MVP Acceptance Dashboard</h1>
        <p class="hint">Generated at $(ConvertTo-HtmlText (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")).</p>
      </div>
      <div class="links">
        <a class="button primary" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $acceptanceTasksPath))">Acceptance tasks</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $humanPlanPath))">Human plan</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $acceptanceChecklistPath))">Acceptance checklist</a>
      </div>
    </div>
  </header>
  <main class="wrap">
    <section class="panel">
      <h2>Readiness</h2>
      <div class="metrics">
$readinessMetrics
      </div>
      <p class="hint">Run <code>.\scripts\check-mvp-readiness.ps1 -IncludeBuild</code> before calling the first version complete.</p>
    </section>
    <section class="panel">
      <h2>Content Review</h2>
      <div class="metrics">
$contentMetrics
      </div>
      <div class="links">
        <a class="button primary" href="$(ConvertTo-HtmlText $nextContentBatchUri)">$(ConvertTo-HtmlText $nextContentBatch.label)</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $contentReviewHtmlPath))">Open review desk</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $contentGateCheckPath))">Gate report</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $contentPrecheckPath))">Precheck</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $contentAudioReadinessPath))">Audio readiness</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $contentReviewDocPath))">Review guide</a>
      </div>
    </section>
    <section class="panel">
      <h2>Beta Feedback</h2>
      <div class="metrics">
$betaMetrics
      </div>
      <div class="links">
        <a class="button primary" href="$(ConvertTo-HtmlText $nextBetaUserUri)">$(ConvertTo-HtmlText $nextBetaUser.label)</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $betaFeedbackHtmlPath))">Open feedback form</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $betaGateCheckPath))">Gate report</a>
        <a class="button" href="$(ConvertTo-HtmlText (ConvertTo-FileUri $betaPlaybookPath))">Beta playbook</a>
      </div>
    </section>
  </main>
</body>
</html>
"@

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value $html -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    contentReviewReady = $contentReviewReady
    betaFeedbackReady = $betaFeedbackReady
    readinessChecked = ($null -ne $readiness) -and -not $readinessCheckFailed
} | ConvertTo-Json -Depth 4
