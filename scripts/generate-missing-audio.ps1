param(
    [string]$ApiBaseUrl = "http://localhost:5180",
    [string]$AdminEmail = "admin@example.com",
    [string]$AdminPassword = 'Admin123$',
    [int]$Limit = 20,
    [int]$MaxRounds = 20,
    [string]$Status = "published",
    [string]$Level = "all",
    [string]$Voice = "",
    [double]$Speed = 1,
    [switch]$IncludeExternalAudio
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function ConvertTo-JsonBody($value) {
    return $value | ConvertTo-Json -Depth 12 -Compress
}

if ($Limit -lt 1 -or $Limit -gt 20) {
    throw "Limit must be between 1 and 20 because the API clamps batch size to 20."
}

if ($MaxRounds -lt 1) {
    throw "MaxRounds must be greater than 0."
}

Write-Host "Checking API health..."
$health = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/health"
if ($health.status -ne "Healthy") {
    throw "API is not healthy."
}

Write-Host "Logging in admin user..."
$adminAuth = Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/auth/login" `
    -ContentType "application/json" `
    -Body (ConvertTo-JsonBody @{ email = $AdminEmail; password = $AdminPassword })

$token = $adminAuth.accessToken
if ([string]::IsNullOrWhiteSpace($token)) {
    throw "Admin login did not return a token."
}

$totalGenerated = 0
$totalFailed = 0
$rounds = @()
$remainingCandidates = 0

for ($round = 1; $round -le $MaxRounds; $round++) {
    $request = @{
        limit = $Limit
        status = $Status
        level = $Level
        speed = $Speed
        includeExternalAudio = [bool]$IncludeExternalAudio
    }

    if (-not [string]::IsNullOrWhiteSpace($Voice)) {
        $request.voice = $Voice
    }

    Write-Host "Generating missing audio round $round..."
    $result = Invoke-RestMethod `
        -Method Post `
        -Uri "$ApiBaseUrl/api/admin/sentences/generate-missing-audio" `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json; charset=utf-8" `
        -Body (ConvertTo-JsonBody $request)

    $roundSummary = [pscustomobject]@{
        round = $round
        totalCandidates = $result.totalCandidates
        generatedCount = $result.generatedCount
        failedCount = $result.failedCount
    }
    $rounds += $roundSummary
    Write-Host ($roundSummary | ConvertTo-Json -Depth 4)

    $totalGenerated += [int]$result.generatedCount
    $totalFailed += [int]$result.failedCount
    $remainingCandidates = [Math]::Max(
        [int]$result.totalCandidates - [int]$result.generatedCount,
        0)

    if ([int]$result.failedCount -gt 0) {
        $result.items |
            Where-Object { -not $_.succeeded } |
            ConvertTo-Json -Depth 6
        throw "Audio generation failed in round $round."
    }

    if ([int]$result.totalCandidates -eq 0 -or [int]$result.generatedCount -eq 0) {
        break
    }

    if ($round -eq $MaxRounds -and $remainingCandidates -gt 0) {
        throw "MaxRounds was reached with $remainingCandidates candidate(s) still missing audio."
    }
}

$summary = [pscustomobject]@{
    generatedCount = $totalGenerated
    failedCount = $totalFailed
    remainingCandidates = $remainingCandidates
    rounds = $rounds.Count
    status = $Status
    level = $Level
}

Write-Host "Missing audio generation complete."
$summary | ConvertTo-Json -Depth 6
