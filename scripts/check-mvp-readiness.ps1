param(
    [string]$ApiBaseUrl = "http://localhost:5180",
    [string]$WebBaseUrl = "http://localhost:3000",
    [string]$LearnerEmail = "learner@example.com",
    [string]$LearnerPassword = 'Pass123$',
    [string]$AdminEmail = "admin@example.com",
    [string]$AdminPassword = 'Admin123$',
    [switch]$SkipSmoke,
    [switch]$SkipUi,
    [switch]$IncludeBuild
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function ConvertTo-JsonBody($value) {
    return $value | ConvertTo-Json -Depth 12 -Compress
}

function Invoke-ReadinessStep($name, [scriptblock]$action) {
    try {
        $details = & $action
        return [pscustomobject]@{
            name = $name
            passed = $true
            details = $details
            error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            name = $name
            passed = $false
            details = $null
            error = $_.Exception.Message
        }
    }
}

function Get-ContentPackSummary {
    $contentPath = Join-Path $PSScriptRoot "..\content\mvp-sentence-pack.json"
    $json = Get-Content -LiteralPath $contentPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $items = @($json.items)
    $keywordRows = ($items | ForEach-Object { @($_.keywords).Count } | Measure-Object -Sum).Sum
    $distinctLemmas = @(
        $items |
            ForEach-Object { $_.keywords } |
            ForEach-Object { ([string]$_.lemma).Trim().ToLowerInvariant() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    )

    [pscustomobject]@{
        items = $items.Count
        scenes = @($items | ForEach-Object { $_.sceneCode } | Sort-Object -Unique).Count
        keywordRows = [int]$keywordRows
        distinctLemmas = $distinctLemmas.Count
        meetsMinimum = $items.Count -ge 100 -and $distinctLemmas.Count -ge 300
    }
}

function Get-DatabaseContentSummary {
    $sql = @"
SELECT
  COUNT(*) AS total,
  COUNT(*) FILTER (WHERE "Status" = 'published') AS published,
  COUNT(*) FILTER (
    WHERE "Status" = 'published'
      AND COALESCE("AudioUrl", '') = ''
      AND "AudioAssetId" IS NULL
  ) AS published_missing_audio
FROM sentences;
"@

    $raw = $sql |
        docker exec -i english-study-postgres psql -U english_study -d english_study -t -A -F ","

    $values = ([string]$raw).Trim().Split(",")
    if ($values.Count -lt 3) {
        throw "Unexpected database summary output: $raw"
    }

    [pscustomobject]@{
        totalSentences = [int]$values[0]
        publishedSentences = [int]$values[1]
        publishedMissingAudio = [int]$values[2]
        audioCoverageReady = [int]$values[2] -eq 0
    }
}

function Get-DatabasePermissionSummary {
    $sql = @"
SELECT
  COUNT(DISTINCT p."Id") FILTER (WHERE p."Code" = 'content:manage') AS permissions,
  COUNT(DISTINCT r."Id") FILTER (
    WHERE p."Code" = 'content:manage'
      AND r."Name" IN ('Admin', 'ContentAdmin', 'SuperAdmin')
  ) AS assigned_roles
FROM permissions p
LEFT JOIN role_permissions rp ON rp."PermissionId" = p."Id"
LEFT JOIN roles r ON r."Id" = rp."RoleId";
"@

    $raw = $sql |
        docker exec -i english-study-postgres psql -U english_study -d english_study -t -A -F ","

    $values = ([string]$raw).Trim().Split(",")
    if ($values.Count -lt 2) {
        throw "Unexpected permission summary output: $raw"
    }

    [pscustomobject]@{
        contentManagePermissions = [int]$values[0]
        assignedAdminRoles = [int]$values[1]
        ready = [int]$values[0] -eq 1 -and [int]$values[1] -ge 3
    }
}

function Get-OptionalJsonScriptSummary($scriptName, $missingMessage) {
    $scriptPath = Join-Path $PSScriptRoot $scriptName
    try {
        $output = & $scriptPath 2>&1 | Out-String
        return ($output | ConvertFrom-Json)
    }
    catch {
        return [pscustomobject]@{
            missing = $true
            message = $missingMessage
            error = $_.Exception.Message
        }
    }
}

$steps = New-Object System.Collections.Generic.List[object]

$steps.Add((Invoke-ReadinessStep "content-pack" {
    & (Join-Path $PSScriptRoot "validate-mvp-content.ps1") *> $null
    Get-ContentPackSummary
}))

$steps.Add((Invoke-ReadinessStep "content-quality-audit" {
    $output = & (Join-Path $PSScriptRoot "audit-mvp-content-quality.ps1") -JsonOnly
    $summary = $output | ConvertFrom-Json
    if (-not [bool]$summary.passesMinimumGate) {
        throw "Content quality audit did not pass."
    }

    $summary
}))

$steps.Add((Invoke-ReadinessStep "ddd-boundaries" {
    $output = & (Join-Path $PSScriptRoot "check-ddd-boundaries.ps1") -JsonOnly
    $summary = $output | ConvertFrom-Json
    if (-not [bool]$summary.passed) {
        throw "DDD boundary check did not pass."
    }

    $summary
}))

$steps.Add((Invoke-ReadinessStep "api-health" {
    Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/health"
}))

$steps.Add((Invoke-ReadinessStep "api-ready" {
    Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/health/ready"
}))

$steps.Add((Invoke-ReadinessStep "web-home" {
    $response = Invoke-WebRequest -Uri $WebBaseUrl -UseBasicParsing -TimeoutSec 15
    [pscustomobject]@{ statusCode = [int]$response.StatusCode }
}))

$steps.Add((Invoke-ReadinessStep "admin-content-counts" {
    $adminAuth = Invoke-RestMethod `
        -Method Post `
        -Uri "$ApiBaseUrl/api/auth/login" `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody @{ email = $AdminEmail; password = $AdminPassword })

    $token = $adminAuth.accessToken
    $scenes = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/api/admin/scenes" -Headers @{ Authorization = "Bearer $token" }
    $words = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/api/admin/words" -Headers @{ Authorization = "Bearer $token" }
    $sentences = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/api/admin/sentences" -Headers @{ Authorization = "Bearer $token" }

    [pscustomobject]@{
        scenes = @($scenes).Count
        words = @($words).Count
        sentences = @($sentences).Count
        meetsMinimum = @($sentences).Count -ge 100 -and @($words).Count -ge 300
    }
}))

$steps.Add((Invoke-ReadinessStep "permission-policy" {
    $permissionSummary = Get-DatabasePermissionSummary
    if (-not [bool]$permissionSummary.ready) {
        throw "content:manage permission is not assigned to the expected admin roles."
    }

    $adminAuth = Invoke-RestMethod `
        -Method Post `
        -Uri "$ApiBaseUrl/api/auth/login" `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody @{ email = $AdminEmail; password = $AdminPassword })
    $learnerAuth = Invoke-RestMethod `
        -Method Post `
        -Uri "$ApiBaseUrl/api/auth/login" `
        -ContentType "application/json" `
        -Body (ConvertTo-JsonBody @{ email = $LearnerEmail; password = $LearnerPassword })

    $adminResponse = Invoke-WebRequest `
        -Method Get `
        -Uri "$ApiBaseUrl/api/admin/scenes" `
        -Headers @{ Authorization = "Bearer $($adminAuth.accessToken)" } `
        -UseBasicParsing

    $learnerStatus = $null
    try {
        Invoke-WebRequest `
            -Method Get `
            -Uri "$ApiBaseUrl/api/admin/scenes" `
            -Headers @{ Authorization = "Bearer $($learnerAuth.accessToken)" } `
            -UseBasicParsing |
            Out-Null
        $learnerStatus = 200
    }
    catch {
        $learnerStatus = [int]$_.Exception.Response.StatusCode
    }

    if ([int]$adminResponse.StatusCode -ne 200 -or $learnerStatus -ne 403) {
        throw "Permission policy did not allow admin and reject learner as expected."
    }

    [pscustomobject]@{
        contentManagePermissions = $permissionSummary.contentManagePermissions
        assignedAdminRoles = $permissionSummary.assignedAdminRoles
        adminStatus = [int]$adminResponse.StatusCode
        learnerStatus = $learnerStatus
    }
}))

$steps.Add((Invoke-ReadinessStep "database-audio-coverage" {
    Get-DatabaseContentSummary
}))

if (-not $SkipSmoke) {
    $steps.Add((Invoke-ReadinessStep "api-smoke-tts" {
        & (Join-Path $PSScriptRoot "smoke-test.ps1") -IncludeTts *> $null
        [pscustomobject]@{ completed = $true }
    }))
}

if (-not $SkipUi) {
    $steps.Add((Invoke-ReadinessStep "ui-smoke" {
        node (Join-Path $PSScriptRoot "ui-smoke-test.mjs") *> $null
        [pscustomobject]@{ completed = $true }
    }))
}

if ($IncludeBuild) {
    $steps.Add((Invoke-ReadinessStep "dotnet-build" {
        dotnet build (Join-Path $PSScriptRoot "..\EnglishStudy.Studio.slnx") -p:UseAppHost=false *> $null
        [pscustomobject]@{ completed = $true }
    }))

    $steps.Add((Invoke-ReadinessStep "web-lint" {
        Push-Location (Join-Path $PSScriptRoot "..\apps\web")
        try {
            npm run lint *> $null
        }
        finally {
            Pop-Location
        }
        [pscustomobject]@{ completed = $true }
    }))

    $steps.Add((Invoke-ReadinessStep "web-build" {
        Push-Location (Join-Path $PSScriptRoot "..\apps\web")
        try {
            npm run build *> $null
        }
        finally {
            Pop-Location
        }
        [pscustomobject]@{ completed = $true }
    }))
}

$contentReviewPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.csv"
$contentReview = if (Test-Path -LiteralPath $contentReviewPath) {
    Get-OptionalJsonScriptSummary "summarize-content-review.ps1" "Content review sheet is missing."
}
else {
    [pscustomobject]@{
        missing = $true
        message = "Content review sheet is missing. Run .\scripts\export-content-review-sheet.ps1."
    }
}

$betaFeedbackPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv"
$betaFeedback = if (Test-Path -LiteralPath $betaFeedbackPath) {
    Get-OptionalJsonScriptSummary "summarize-beta-feedback.ps1" "Beta feedback sheet is missing."
}
else {
    [pscustomobject]@{
        missing = $true
        message = "Beta feedback sheet is missing. Run .\scripts\export-beta-feedback-template.ps1."
    }
}

$failedSteps = @($steps | Where-Object { -not $_.passed })
$automatedReady = $failedSteps.Count -eq 0
$productReviewReady =
    ($contentReview.PSObject.Properties.Name -contains "passesMinimumGate") -and
    [bool]$contentReview.passesMinimumGate -and
    ($betaFeedback.PSObject.Properties.Name -contains "passesMinimumGate") -and
    [bool]$betaFeedback.passesMinimumGate

[pscustomobject]@{
    checkedAt = (Get-Date).ToString("o")
    automatedReady = $automatedReady
    productReviewReady = $productReviewReady
    firstVersionReady = $automatedReady -and $productReviewReady
    steps = $steps
    contentReview = $contentReview
    betaFeedback = $betaFeedback
    notes = @(
        "automatedReady covers local engineering and content infrastructure checks.",
        "productReviewReady requires filled human content review and beta feedback sheets."
    )
} | ConvertTo-Json -Depth 12
