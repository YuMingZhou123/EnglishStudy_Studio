param(
    [string]$ContentPath = "",
    [switch]$JsonOnly
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($ContentPath)) {
    $ContentPath = Join-Path $PSScriptRoot "..\content\mvp-sentence-pack.json"
}

$ContentPath = [System.IO.Path]::GetFullPath($ContentPath)
if (-not (Test-Path -LiteralPath $ContentPath)) {
    throw "Content file not found: $ContentPath"
}

$json = Get-Content -LiteralPath $ContentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($json.items)
$allowedLevels = @("beginner", "intermediate", "advanced")
$issues = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Issue([string]$message) {
    $issues.Add($message)
}

function Add-Warning([string]$message) {
    $warnings.Add($message)
}

function Get-WordCount([string]$text) {
    $matches = [regex]::Matches($text, "[A-Za-z]+(?:'[A-Za-z]+)?")
    return $matches.Count
}

if ($items.Count -lt 100 -or $items.Count -gt 300) {
    Add-Issue "Content count must stay within the MVP range of 100 to 300."
}

if ($items.Count -eq 0) {
    Add-Issue "Content pack must contain at least one item."
}

$sceneCounts = [ordered]@{}
foreach ($group in ($items | Group-Object sceneCode)) {
    $sceneCounts[$group.Name] = $group.Count
    if ($group.Count -lt 15) {
        Add-Issue "Scene '$($group.Name)' must contain at least 15 sentences."
    }
}

if ($sceneCounts.Count -lt 5 -or $sceneCounts.Count -gt 8) {
    Add-Issue "Scene count must stay within 5 to 8."
}

$levelCounts = [ordered]@{}
foreach ($level in $allowedLevels) {
    $levelCounts[$level] = @($items | Where-Object { $_.level -eq $level }).Count
    if ($levelCounts[$level] -lt 15) {
        Add-Issue "Level '$level' must contain at least 15 sentences."
    }
}

$wordStats = [ordered]@{}
foreach ($level in $allowedLevels) {
    $levelItems = @($items | Where-Object { $_.level -eq $level })
    if ($levelItems.Count -eq 0) {
        continue
    }

    $wordCounts = @($levelItems | ForEach-Object { Get-WordCount $_.text })
    $wordStats[$level] = [pscustomobject]@{
        min = ($wordCounts | Measure-Object -Minimum).Minimum
        max = ($wordCounts | Measure-Object -Maximum).Maximum
        average = [math]::Round(($wordCounts | Measure-Object -Average).Average, 2)
    }

    $expectedRanges = @{
        beginner = @{ min = 5; max = 10 }
        intermediate = @{ min = 6; max = 14 }
        advanced = @{ min = 6; max = 18 }
    }

    $range = $expectedRanges[$level]
    foreach ($count in $wordCounts) {
        if ($count -lt $range.min -or $count -gt $range.max) {
            Add-Warning "Level '$level' contains a sentence with $count words, outside the recommended range $($range.min)-$($range.max)."
            break
        }
    }
}

$keywordsPerItem = @($items | ForEach-Object { @($_.keywords).Count })
$keywordMin = ($keywordsPerItem | Measure-Object -Minimum).Minimum
$keywordMax = ($keywordsPerItem | Measure-Object -Maximum).Maximum
$keywordAvg = [math]::Round(($keywordsPerItem | Measure-Object -Average).Average, 2)
if ($keywordMin -lt 2) {
    Add-Issue "Every sentence must contain at least 2 keywords."
}

if ($keywordMax -gt 5) {
    Add-Warning "Some sentences contain more than 5 keywords."
}

$duplicateTexts = @($items | Group-Object text | Where-Object { $_.Count -gt 1 })
foreach ($duplicate in $duplicateTexts) {
    Add-Issue "Duplicate sentence text: $($duplicate.Name)"
}

$distinctLemmas = @(
    $items |
        ForEach-Object { $_.keywords } |
        ForEach-Object { ([string]$_.lemma).Trim().ToLowerInvariant() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
)

if ($distinctLemmas.Count -lt 300) {
    Add-Issue "Distinct lemma count must be at least 300."
}

$summary = [pscustomobject]@{
    contentPath = $ContentPath
    items = $items.Count
    scenes = $sceneCounts.Count
    sceneCounts = $sceneCounts
    levelCounts = $levelCounts
    wordStats = $wordStats
    keywordStats = [pscustomobject]@{
        min = [int]$keywordMin
        max = [int]$keywordMax
        average = $keywordAvg
    }
    distinctLemmas = $distinctLemmas.Count
    issueCount = $issues.Count
    warningCount = $warnings.Count
    passesMinimumGate = $issues.Count -eq 0
}

$summary | ConvertTo-Json -Depth 8

if (-not $JsonOnly -and $warnings.Count -gt 0) {
    $warnings | ForEach-Object { Write-Warning $_ }
}

if ($issues.Count -gt 0) {
    $issues | ForEach-Object { Write-Error $_ }
    throw "Content quality audit failed with $($issues.Count) issue(s)."
}

if (-not $JsonOnly) {
    Write-Host "Content quality audit passed."
}
