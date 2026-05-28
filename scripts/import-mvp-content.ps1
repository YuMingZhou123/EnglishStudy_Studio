param(
    [string]$ApiBaseUrl = "http://localhost:5180",
    [string]$AdminEmail = "admin@example.com",
    [string]$AdminPassword = 'Admin123$',
    [string]$ContentPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function ConvertTo-JsonBody($value) {
    return $value | ConvertTo-Json -Depth 20 -Compress
}

if ([string]::IsNullOrWhiteSpace($ContentPath)) {
    $ContentPath = Join-Path $PSScriptRoot "..\content\mvp-sentence-pack.json"
}

$ContentPath = [System.IO.Path]::GetFullPath($ContentPath)
if (-not (Test-Path -LiteralPath $ContentPath)) {
    throw "Content file not found: $ContentPath"
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

Write-Host "Importing content from $ContentPath..."
$json = Get-Content -LiteralPath $ContentPath -Raw -Encoding UTF8
$payload = $json | ConvertFrom-Json
$result = Invoke-RestMethod `
    -Method Post `
    -Uri "$ApiBaseUrl/api/admin/sentences/import" `
    -Headers @{ Authorization = "Bearer $token" } `
    -ContentType "application/json; charset=utf-8" `
    -Body $json

Write-Host "Import complete."
$summary = [pscustomobject]@{
    sourceItems = @($payload.items).Count
    totalCount = $result.totalCount
    createdScenes = $result.createdScenes
    createdWords = $result.createdWords
    createdSentences = $result.createdSentences
    updatedSentences = $result.updatedSentences
    skippedCount = $result.skippedCount
    failureCount = @($result.failures).Count
}

$summary | ConvertTo-Json -Depth 6

if (@($result.failures).Count -gt 0) {
    $result.failures | ConvertTo-Json -Depth 8
    throw "Import finished with failures."
}
